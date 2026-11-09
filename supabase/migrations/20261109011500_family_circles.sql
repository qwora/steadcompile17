-- Stead: family circles and shared cases.
-- Privacy rule: no raw message text is ever stored here. Cases hold a short summary only.

create extension if not exists pgcrypto;

-- ── Tables ───────────────────────────────────────────────────────────────

create table public.circles (
  id              uuid primary key default gen_random_uuid(),
  name            text not null default 'Family',
  invite_code     text not null unique,
  code_expires_at timestamptz not null default now() + interval '24 hours',
  created_at      timestamptz not null default now()
);

create table public.members (
  id            uuid primary key default gen_random_uuid(),
  circle_id     uuid not null references public.circles(id) on delete cascade,
  user_id       uuid not null default auth.uid(),
  role          text not null check (role in ('protected', 'guardian')),
  display_name  text not null,
  kitten_color  text not null default 'green',
  auto_share    boolean not null default true,
  created_at    timestamptz not null default now(),
  unique (circle_id, user_id)
);

create table public.cases (
  id                        uuid primary key default gen_random_uuid(),
  circle_id                 uuid not null references public.circles(id) on delete cascade,
  protected_member_id       uuid not null references public.members(id) on delete cascade,
  kind                      text not null default 'warning' check (kind in ('warning', 'verify_identity')),
  level                     int  not null check (level between 1 and 3),
  category                  text not null,
  app                       text,
  sender_label              text,
  claimed_identity          text,
  requested_action          text,
  summary_for_guardian      text not null check (char_length(summary_for_guardian) <= 400),
  recommended_verification  text,
  status                    text not null default 'open' check (status in ('open', 'checking', 'resolved')),
  handled_by                uuid references public.members(id) on delete set null,
  resolution                text,
  verify_target_member_id   uuid references public.members(id) on delete set null,
  verify_answer             text check (verify_answer in ('yes', 'no')),
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now()
);

create index cases_circle_created on public.cases (circle_id, created_at desc);
create index members_user on public.members (user_id);

-- ── Helpers ──────────────────────────────────────────────────────────────

create or replace function public.is_member(target_circle uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.members where circle_id = target_circle and user_id = auth.uid());
$$;

create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

create trigger cases_touch before update on public.cases
  for each row execute function public.touch_updated_at();

-- ── RPCs ─────────────────────────────────────────────────────────────────

-- Creates a circle with a fresh 6-digit code and makes the caller its first member.
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
  loop
    v_code := lpad((floor(random() * 1000000))::int::text, 6, '0');
    exit when not exists (select 1 from circles c where c.invite_code = v_code);
  end loop;
  insert into circles (name, invite_code) values (p_name, v_code) returning id into v_circle;
  insert into members (circle_id, user_id, role, display_name)
    values (v_circle, auth.uid(), p_role, p_display_name) returning id into v_member;
  return query select v_circle, v_code, v_member;
end $$;

-- Joins a circle by its code if the code has not expired.
create or replace function public.join_circle(p_code text, p_display_name text, p_role text default 'guardian')
returns table (circle_id uuid, member_id uuid)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_circle uuid;
  v_member uuid;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select c.id into v_circle from circles c
    where c.invite_code = trim(p_code) and c.code_expires_at > now();
  if v_circle is null then raise exception 'invalid or expired code'; end if;
  insert into members (circle_id, user_id, role, display_name)
    values (v_circle, auth.uid(), p_role, p_display_name)
    on conflict (circle_id, user_id) do update set display_name = excluded.display_name, role = excluded.role
    returning id into v_member;
  return query select v_circle, v_member;
end $$;

-- Makes a new code for a circle the caller belongs to.
create or replace function public.refresh_invite_code(p_circle uuid)
returns text language plpgsql security definer set search_path = public as $$
declare v_code text;
begin
  if not public.is_member(p_circle) then raise exception 'not a member'; end if;
  loop
    v_code := lpad((floor(random() * 1000000))::int::text, 6, '0');
    exit when not exists (select 1 from circles c where c.invite_code = v_code);
  end loop;
  update circles set invite_code = v_code, code_expires_at = now() + interval '24 hours' where id = p_circle;
  return v_code;
end $$;

-- ── Row level security ──────────────────────────────────────────────────

alter table public.circles enable row level security;
alter table public.members enable row level security;
alter table public.cases   enable row level security;

create policy "members read their circle" on public.circles
  for select using (public.is_member(id));

create policy "members read circle members" on public.members
  for select using (public.is_member(circle_id));
create policy "members update themselves" on public.members
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "members read circle cases" on public.cases
  for select using (public.is_member(circle_id));
create policy "protected member creates own cases" on public.cases
  for insert with check (
    public.is_member(circle_id)
    and exists (select 1 from public.members m
                where m.id = protected_member_id and m.user_id = auth.uid() and m.circle_id = cases.circle_id)
  );
create policy "members update circle cases" on public.cases
  for update using (public.is_member(circle_id)) with check (public.is_member(circle_id));

grant execute on function public.create_circle(text, text, text) to authenticated;
grant execute on function public.join_circle(text, text, text) to authenticated;
grant execute on function public.refresh_invite_code(uuid) to authenticated;

-- ── Realtime ────────────────────────────────────────────────────────────

alter publication supabase_realtime add table public.cases;
alter publication supabase_realtime add table public.members;
