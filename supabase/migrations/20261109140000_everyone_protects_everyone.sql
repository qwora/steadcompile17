-- Stead: a family circle where everyone protects everyone.
-- Any member shares their own warnings; every other member is told and can help.
-- The 'protected' / 'guardian' role stays as a label only (who created the circle).

drop policy if exists "protected member creates own cases" on public.cases;
create policy "members create their own cases" on public.cases
  for insert with check (
    exists (select 1 from public.members m
            where m.id = protected_member_id and m.user_id = auth.uid() and m.circle_id = cases.circle_id)
    and status = 'open' and handled_by is null and resolution is null and verify_answer is null
    and (verify_target_member_id is null or exists (
          select 1 from public.members g
          where g.id = verify_target_member_id and g.circle_id = cases.circle_id
            and g.id <> cases.protected_member_id))
  );

create or replace function public.cases_guard()
returns trigger language plpgsql set search_path = public as $$
declare
  v_me uuid;
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

  select m.id into v_me from public.members m
    where m.circle_id = old.circle_id and m.user_id = auth.uid();

  if new.handled_by is distinct from old.handled_by and new.handled_by is not null and new.handled_by <> v_me then
    raise exception 'cases: handled_by must be yourself';
  end if;

  if new.verify_answer is distinct from old.verify_answer then
    -- Anyone in the circle except the person who got the message, or the one it was aimed at.
    if old.kind <> 'verify_identity' or v_me is null or v_me = old.protected_member_id
       or (old.verify_target_member_id is not null and old.verify_target_member_id <> v_me) then
      raise exception 'cases: only the asked family member can answer';
    end if;
    if old.verify_answer is not null then raise exception 'cases: already answered'; end if;
  end if;
  return new;
end $$;
