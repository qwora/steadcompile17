-- Stead: tighten circle/case authorization, and add guardian push notifications.
-- Forward migration on top of 20261109011500_family_circles.sql (which may already be applied).
-- Privacy rule unchanged: no raw message text anywhere. Push payloads carry only a case id.

-- ── 1. Members can't change who they are or which circle they're in ─────
-- Before: "members update themselves" let a user set their own circle_id to any circle
-- (joining without a code) or flip their role. Only profile fields may change now.
create or replace function public.members_guard()
returns trigger language plpgsql set search_path = public as $$
begin
  if (new.id, new.circle_id, new.user_id, new.role, new.created_at)
     is distinct from (old.id, old.circle_id, old.user_id, old.role, old.created_at) then
    raise exception 'members: only display_name, kitten_color and auto_share can change';
  end if;
  return new;
end $$;

create trigger members_guard before update on public.members
  for each row execute function public.members_guard();

-- Names show on lock-screen pushes; keep them short. NOT VALID: existing rows aren't re-checked.
alter table public.members add constraint members_display_name_len
  check (char_length(display_name) between 1 and 40) not valid;

-- ── 2. Cases: facts are fixed once written; guardians only act on them ──
alter table public.cases add column if not exists requested_by_user boolean not null default false;
comment on column public.cases.requested_by_user is
  'true when the protected person tapped "Ask family"; false for automatic sharing (needs members.auto_share).';

drop policy if exists "protected member creates own cases" on public.cases;
create policy "protected member creates own cases" on public.cases
  for insert with check (
    exists (select 1 from public.members m
            where m.id = protected_member_id and m.user_id = auth.uid()
              and m.circle_id = cases.circle_id and m.role = 'protected')
    and status = 'open' and handled_by is null and resolution is null and verify_answer is null
    and (verify_target_member_id is null or exists (
          select 1 from public.members g
          where g.id = verify_target_member_id and g.circle_id = cases.circle_id and g.role = 'guardian'))
  );

-- Applies to every request made with a user's JWT, including inside SECURITY DEFINER RPCs
-- (current_user would be the owner there). Service role (the push function) is unrestricted.
create or replace function public.cases_guard()
returns trigger language plpgsql set search_path = public as $$
declare
  v_me uuid;
  v_role text;
begin
  if coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '') not in ('authenticated', 'anon')
     and current_user not in ('authenticated', 'anon') then
    return new;
  end if;

  if (new.id, new.circle_id, new.protected_member_id, new.kind, new.level, new.category, new.app, new.sender_label,
      new.claimed_identity, new.requested_action, new.summary_for_guardian, new.recommended_verification,
      new.verify_target_member_id, new.requested_by_user, new.created_at)
     is distinct from
     (old.id, old.circle_id, old.protected_member_id, old.kind, old.level, old.category, old.app, old.sender_label,
      old.claimed_identity, old.requested_action, old.summary_for_guardian, old.recommended_verification,
      old.verify_target_member_id, old.requested_by_user, old.created_at) then
    raise exception 'cases: only status, handled_by, resolution and verify_answer can change';
  end if;

  select m.id, m.role into v_me, v_role from public.members m
    where m.circle_id = old.circle_id and m.user_id = auth.uid();

  if new.handled_by is distinct from old.handled_by and new.handled_by is not null and new.handled_by <> v_me then
    raise exception 'cases: handled_by must be yourself';
  end if;

  if new.verify_answer is distinct from old.verify_answer then
    if old.kind <> 'verify_identity' or v_role <> 'guardian'
       or (old.verify_target_member_id is not null and old.verify_target_member_id <> v_me) then
      raise exception 'cases: only the asked family member can answer';
    end if;
    if old.verify_answer is not null then raise exception 'cases: already answered'; end if;
  end if;
  return new;
end $$;

create trigger cases_guard before update on public.cases
  for each row execute function public.cases_guard();

-- ── 3. Invite codes: strong randomness, no role flips, attempt limit ────
create or replace function public.new_invite_code()
returns text language sql volatile set search_path = public as $$
  -- gen_random_uuid() is backed by a CSPRNG; random() is not.
  select lpad(((('x' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8))::bit(32)::bigint % 1000000))::text, 6, '0');
$$;

create table public.join_attempts (
  user_id    uuid not null,
  created_at timestamptz not null default now()
);
create index join_attempts_user on public.join_attempts (user_id, created_at desc);
alter table public.join_attempts enable row level security; -- no policies: RPC only

create or replace function public.create_circle(p_display_name text, p_role text default 'protected', p_name text default 'Family')
returns table (circle_id uuid, invite_code text, member_id uuid)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_code text;
  v_circle uuid;
  v_member uuid;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if char_length(trim(coalesce(p_display_name, ''))) not between 1 and 40 then raise exception 'invalid display name'; end if;
  loop
    v_code := public.new_invite_code();
    exit when not exists (select 1 from circles c where c.invite_code = v_code);
  end loop;
  insert into circles (name, invite_code) values (left(coalesce(p_name, 'Family'), 40), v_code) returning id into v_circle;
  insert into members (circle_id, user_id, role, display_name)
    values (v_circle, auth.uid(), p_role, trim(p_display_name)) returning id into v_member;
  return query select v_circle, v_code, v_member;
end $$;

-- Rejection of a bad or expired code returns ZERO ROWS (not an exception) so the failed
-- attempt is recorded; 10 failures per user per 15 minutes then raises 'too many attempts'.
-- A code is SINGLE-USE: a successful new join expires it (refresh_invite_code for the next person),
-- so a guessed code is worth at most one seat and the family sees who took it.
-- A joiner can only be 'protected' if the circle has no protected member yet (guardian-created circle).
-- shortcut: per-user limit only; anonymous sign-ups are capped per IP by Supabase Auth (default 30/h).
-- Upgrade to a per-IP limiter in an Edge Function if codes are ever long-lived.
create or replace function public.join_circle(p_code text, p_display_name text, p_role text default 'guardian')
returns table (circle_id uuid, member_id uuid)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_circle uuid;
  v_member uuid;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if char_length(trim(coalesce(p_display_name, ''))) not between 1 and 40 then raise exception 'invalid display name'; end if;
  perform pg_advisory_xact_lock(hashtext('join:' || auth.uid()::text)); -- parallel calls can't skip the count
  if (select count(*) from join_attempts a
      where a.user_id = auth.uid() and a.created_at > now() - interval '15 minutes') >= 10 then
    raise exception 'too many attempts';
  end if;

  select c.id into v_circle from circles c
    where c.invite_code = trim(p_code) and c.code_expires_at > now();
  if v_circle is null then
    insert into join_attempts (user_id) values (auth.uid());
    return;
  end if;

  select m.id into v_member from members m where m.circle_id = v_circle and m.user_id = auth.uid();
  if v_member is not null then
    -- Re-joining keeps the existing role and doesn't use up the code.
    update members set display_name = trim(p_display_name) where id = v_member;
    return query select v_circle, v_member;
    return;
  end if;

  if p_role = 'protected' and exists (select 1 from members m where m.circle_id = v_circle and m.role = 'protected') then
    raise exception 'this circle already has a protected member';
  end if;
  insert into members (circle_id, user_id, role, display_name)
    values (v_circle, auth.uid(), p_role, trim(p_display_name))
    returning id into v_member;
  update circles set code_expires_at = now() where id = v_circle;
  return query select v_circle, v_member;
end $$;

create or replace function public.refresh_invite_code(p_circle uuid)
returns text language plpgsql security definer set search_path = public as $$
declare v_code text;
begin
  if not public.is_member(p_circle) then raise exception 'not a member'; end if;
  loop
    v_code := public.new_invite_code();
    exit when not exists (select 1 from circles c where c.invite_code = v_code);
  end loop;
  update circles set invite_code = v_code, code_expires_at = now() + interval '24 hours' where id = p_circle;
  return v_code;
end $$;

-- Functions are executable by PUBLIC by default; keep the RPCs to signed-in users.
revoke execute on function public.create_circle(text, text, text) from public, anon;
revoke execute on function public.join_circle(text, text, text) from public, anon;
revoke execute on function public.refresh_invite_code(uuid) from public, anon;
revoke execute on function public.new_invite_code() from public, anon, authenticated;

-- ── 3b. AI call budget: 60 `analyze` calls per user per hour ────────────
-- Holds only (user, time). `analyze` calls this with the caller's JWT, which also proves sign-in.
create table public.ai_calls (
  user_id    uuid not null,
  created_at timestamptz not null default now()
);
create index ai_calls_user on public.ai_calls (user_id, created_at desc);
alter table public.ai_calls enable row level security; -- no policies: RPC only

create or replace function public.claim_ai_call()
returns boolean language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  perform pg_advisory_xact_lock(hashtext('ai:' || auth.uid()::text));
  if (select count(*) from ai_calls a where a.user_id = auth.uid() and a.created_at > now() - interval '1 hour') >= 60 then
    return false;
  end if;
  delete from ai_calls a where a.user_id = auth.uid() and a.created_at < now() - interval '1 hour';
  insert into ai_calls (user_id) values (auth.uid());
  return true;
end $$;
revoke execute on function public.claim_ai_call() from public, anon;
grant execute on function public.claim_ai_call() to authenticated;

-- ── 4. Device tokens (APNs) ─────────────────────────────────────────────
create table public.device_tokens (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null,
  member_id     uuid not null references public.members(id) on delete cascade,
  device_token  text not null unique check (device_token ~ '^[0-9a-f]{64,200}$'),
  platform      text not null default 'ios' check (platform = 'ios'),
  environment   text not null check (environment in ('sandbox', 'production')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index device_tokens_member on public.device_tokens (member_id);
alter table public.device_tokens enable row level security;
-- Owners may see their own rows; nobody else (other family members included) can read tokens.
create policy "users read own device tokens" on public.device_tokens
  for select using (user_id = auth.uid());

-- Registers (or moves) this device's token to the caller's membership. A token belongs to one
-- device, so whoever presents it now takes it over (reinstall, new anonymous session).
create or replace function public.register_device(p_member_id uuid, p_token text, p_environment text default 'production')
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if not exists (select 1 from members m where m.id = p_member_id and m.user_id = auth.uid()) then
    raise exception 'not your membership';
  end if;
  insert into device_tokens (user_id, member_id, device_token, environment)
    values (auth.uid(), p_member_id, lower(p_token), p_environment)
    on conflict (device_token) do update
      set user_id = excluded.user_id, member_id = excluded.member_id,
          environment = excluded.environment, updated_at = now()
    returning id into v_id;
  return v_id;
end $$;

create or replace function public.unregister_device(p_token text)
returns void language sql security definer set search_path = public as $$
  delete from device_tokens where device_token = lower(p_token) and user_id = auth.uid();
$$;

revoke execute on function public.register_device(uuid, text, text) from public, anon;
revoke execute on function public.unregister_device(text) from public, anon;
grant execute on function public.register_device(uuid, text, text) to authenticated;
grant execute on function public.unregister_device(text) to authenticated;

-- ── 5. Push delivery: one row per (case, event) so a push is sent at most once ──
create table public.push_log (
  case_id    uuid not null references public.cases(id) on delete cascade,
  event      text not null,
  created_at timestamptz not null default now(),
  primary key (case_id, event)
);
alter table public.push_log enable row level security; -- no policies: service role only

-- Calls the `notify` Edge Function when a case is created or a guardian acts on it.
-- URL and shared secret live in Vault (see docs/BACKEND_TASKS.md). Missing secrets or a
-- failed call never block the case write; the app still has Realtime + recovery fetch.
create extension if not exists pg_net with schema extensions;

create or replace function public.cases_notify()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_event text;
  v_url text;
  v_secret text;
begin
  if tg_op = 'INSERT' then
    v_event := 'created';
  elsif new.verify_answer is distinct from old.verify_answer and new.verify_answer is not null then
    v_event := 'verify:' || new.verify_answer;
  elsif new.status is distinct from old.status and new.status in ('checking', 'resolved') then
    v_event := 'status:' || new.status;
  else
    return null;
  end if;
  begin
    select decrypted_secret into v_url from vault.decrypted_secrets where name = 'stead_notify_url';
    select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'stead_notify_secret';
    if v_url is not null and v_secret is not null then
      perform net.http_post(
        url := v_url,
        body := jsonb_build_object('case_id', new.id, 'event', v_event),
        headers := jsonb_build_object('content-type', 'application/json', 'x-stead-secret', v_secret),
        timeout_milliseconds := 5000);
    end if;
  exception when others then
    raise warning 'cases_notify skipped: %', sqlerrm;
  end;
  return null;
end $$;

create trigger cases_notify after insert or update on public.cases
  for each row execute function public.cases_notify();
