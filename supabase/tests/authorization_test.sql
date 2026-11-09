-- Authorization tests for circles, members, cases and device tokens.
-- Runs in one transaction and ROLLS BACK, so it leaves no data behind.
-- Local:  npx supabase db reset && psql "$(npx supabase status -o env | grep DB_URL | cut -d= -f2- | tr -d '"')" -v ON_ERROR_STOP=1 -f supabase/tests/authorization_test.sql
-- Any failed check aborts with an error naming it; success prints "authorization tests: ALL PASS".
begin;

create or replace function pg_temp.login(uid text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true),
         set_config('request.jwt.claim.sub', uid, true);
$$;
grant execute on function pg_temp.login(text) to authenticated, anon;
-- Expect a statement to fail. Usage: select pg_temp.fails('label', $q$ ... $q$);
create or replace function pg_temp.fails(label text, q text) returns void language plpgsql as $$
begin
  begin
    execute q;
  exception when others then return;
  end;
  raise exception 'FAIL (should have been rejected): %', label;
end $$;
grant execute on function pg_temp.fails(text, text) to authenticated, anon;
-- Values passed between steps (GUCs are readable from every role).
create or replace function pg_temp.v(k text) returns text language sql as $$ select current_setting('t.' || k) $$;
grant execute on function pg_temp.v(text) to authenticated, anon;

-- Mum creates a circle and gets a 6-digit code.
set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-000000000001');
do $$ declare r record; begin
  select * into r from public.create_circle('Mum');
  assert r.invite_code ~ '^\d{6}$', 'invite code is 6 digits';
  perform set_config('t.circle', r.circle_id::text, false);
  perform set_config('t.code', r.invite_code, false);
  perform set_config('t.mum', r.member_id::text, false);
  assert (select role from members where id = r.member_id) = 'protected', 'creator is the protected member';
end $$;

-- Eve runs her own, unrelated circle.
select pg_temp.login('00000000-0000-4000-8000-000000000003');
do $$ declare r record; begin
  select * into r from public.create_circle('Eve');
  perform set_config('t.eve_circle', r.circle_id::text, false);
  perform set_config('t.eve_code', r.invite_code, false);
  perform set_config('t.eve', r.member_id::text, false);
end $$;

-- Daniel joins Mum's circle with the code.
select pg_temp.login('00000000-0000-4000-8000-000000000002');
do $$ declare r record; begin
  select * into r from public.join_circle(pg_temp.v('code'), 'Daniel');
  assert r.circle_id::text = pg_temp.v('circle'), 'joined the right circle';
  perform set_config('t.dan', r.member_id::text, false);
  assert (select role from members where id = r.member_id) = 'guardian', 'joiner is a guardian';
  assert (select count(*) from members where circle_id = r.circle_id) = 2, 'guardian sees both members';
  -- Re-joining as "protected" must not change the role.
  perform public.join_circle(pg_temp.v('code'), 'Daniel', 'protected');
  assert (select role from members where id = r.member_id) = 'guardian', 're-join cannot flip role';
  -- Wrong code: rejected (zero rows).
  assert not exists (select 1 from public.join_circle('000000x', 'Daniel')), 'wrong code rejected';
end $$;

-- Codes are single-use, and a circle can't get a second protected member.
select pg_temp.login('00000000-0000-4000-8000-000000000004');
do $$ begin
  assert not exists (select 1 from public.join_circle(pg_temp.v('code'), 'Sara')), 'used code rejected';
end $$;
select pg_temp.login('00000000-0000-4000-8000-000000000001');
do $$ begin perform set_config('t.code2', public.refresh_invite_code(pg_temp.v('circle')::uuid), false); end $$;
select pg_temp.login('00000000-0000-4000-8000-000000000005');
select pg_temp.fails('second protected member', format($q$select public.join_circle(%L, 'Fake Mum', 'protected')$q$, pg_temp.v('code2')));
select pg_temp.login('00000000-0000-4000-8000-000000000004');
do $$ begin
  assert exists (select 1 from public.join_circle(pg_temp.v('code2'), 'Sara')), 'fresh code works for the next guardian';
end $$;
select pg_temp.fails('display name too long', $q$update members set display_name = repeat('x', 41) where user_id = auth.uid()$q$);
do $$ declare i int; begin
  for i in 1..60 loop assert public.claim_ai_call(), 'AI call within budget'; end loop;
  assert not public.claim_ai_call(), 'AI budget enforced at 61';
end $$;

-- Expired code is rejected.
reset role;
update circles set code_expires_at = now() - interval '1 minute' where id = pg_temp.v('eve_circle')::uuid;
set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-000000000002');
do $$ begin
  assert not exists (select 1 from public.join_circle(pg_temp.v('eve_code'), 'Daniel')), 'expired code rejected';
  assert (select count(*) from members where circle_id = pg_temp.v('eve_circle')::uuid) = 0, 'not in Eve circle';
end $$;

-- Brute force: failures are limited per user.
do $$ declare i int := 0; begin
  loop
    i := i + 1;
    begin
      perform public.join_circle(lpad(i::text, 6, '9'), 'Daniel');
    exception when others then
      assert sqlerrm = 'too many attempts', 'limit error message';
      exit;
    end;
    assert i < 12, 'FAIL: join attempts are not rate limited';
  end loop;
end $$;

-- Mum creates a Level 2 warning case.
select pg_temp.login('00000000-0000-4000-8000-000000000001');
do $$ declare v uuid; begin
  insert into cases (circle_id, protected_member_id, level, category, summary_for_guardian)
    values (pg_temp.v('circle')::uuid, pg_temp.v('mum')::uuid, 2, 'government_impersonation', 'Asks to pay a fine through a link.')
    returning id into v;
  perform set_config('t.case', v::text, false);
  insert into cases (circle_id, protected_member_id, kind, level, category, summary_for_guardian, verify_target_member_id)
    values (pg_temp.v('circle')::uuid, pg_temp.v('mum')::uuid, 'verify_identity', 2, 'family_impersonation',
            'Someone on a new number says they are Daniel and asks for money.', pg_temp.v('dan')::uuid)
    returning id into v;
  perform set_config('t.vcase', v::text, false);
end $$;
select pg_temp.fails('verify target outside the circle', format(
  $q$insert into cases (circle_id, protected_member_id, kind, level, category, summary_for_guardian, verify_target_member_id)
     values (%L, %L, 'verify_identity', 2, 'family_impersonation', 'x', %L)$q$, pg_temp.v('circle'), pg_temp.v('mum'), pg_temp.v('eve')));
select pg_temp.fails('case created pre-resolved', format(
  $q$insert into cases (circle_id, protected_member_id, level, category, summary_for_guardian, status)
     values (%L, %L, 2, 'other', 'x', 'resolved')$q$, pg_temp.v('circle'), pg_temp.v('mum')));
-- Protected user controls consent.
do $$ declare n int; begin
  update members set auto_share = false where id = pg_temp.v('mum')::uuid;
  get diagnostics n = row_count;
  assert n = 1, 'protected user can change auto_share';
end $$;
select pg_temp.fails('protected user changes own role', format(
  $q$update members set role = 'guardian' where id = %L$q$, pg_temp.v('mum')));

-- Daniel (guardian) acts on the case.
select pg_temp.login('00000000-0000-4000-8000-000000000002');
select pg_temp.fails('guardian inserts a case for Mum', format(
  $q$insert into cases (circle_id, protected_member_id, level, category, summary_for_guardian)
     values (%L, %L, 3, 'other', 'fake')$q$, pg_temp.v('circle'), pg_temp.v('mum')));
-- Everyone protects everyone: Daniel shares his own warning, aimed at Mum.
do $$ declare v uuid; begin
  insert into cases (circle_id, protected_member_id, kind, level, category, summary_for_guardian, verify_target_member_id)
    values (pg_temp.v('circle')::uuid, pg_temp.v('dan')::uuid, 'verify_identity', 3, 'family_impersonation',
            'Someone says they are Mum and asks for money.', pg_temp.v('mum')::uuid)
    returning id into v;
  perform set_config('t.dcase', v::text, false);
end $$;
select pg_temp.fails('member answers his own verify case', format($q$update cases set verify_answer = 'yes' where id = %L$q$, pg_temp.v('dcase')));
do $$ declare n int; begin
  update cases set status = 'checking', handled_by = pg_temp.v('dan')::uuid where id = pg_temp.v('case')::uuid;
  get diagnostics n = row_count;
  assert n = 1, 'guardian can mark checking';
  update cases set status = 'resolved', resolution = 'Called Mum, it was fake.' where id = pg_temp.v('case')::uuid;
  update cases set verify_answer = 'no' where id = pg_temp.v('vcase')::uuid;
  assert (select verify_answer from cases where id = pg_temp.v('vcase')::uuid) = 'no', 'guardian answered';
  update members set auto_share = true where id = pg_temp.v('mum')::uuid;
  get diagnostics n = row_count;
  assert n = 0, 'guardian cannot change Mum''s consent';
end $$;
select pg_temp.fails('guardian rewrites the case level', format($q$update cases set level = 1 where id = %L$q$, pg_temp.v('case')));
select pg_temp.fails('guardian rewrites the summary', format($q$update cases set summary_for_guardian = 'x' where id = %L$q$, pg_temp.v('case')));
select pg_temp.fails('handled_by someone else', format($q$update cases set handled_by = %L where id = %L$q$, pg_temp.v('mum'), pg_temp.v('case')));
select pg_temp.fails('verify answer on a warning case', format($q$update cases set verify_answer = 'yes' where id = %L$q$, pg_temp.v('case')));
select pg_temp.fails('verify answered twice', format($q$update cases set verify_answer = 'yes' where id = %L$q$, pg_temp.v('vcase')));
select pg_temp.fails('guardian becomes protected', format($q$update members set role = 'protected' where id = %L$q$, pg_temp.v('dan')));
select pg_temp.fails('guardian moves to another circle', format($q$update members set circle_id = %L where id = %L$q$, pg_temp.v('eve_circle'), pg_temp.v('dan')));

-- Mum sees what Daniel did.
select pg_temp.login('00000000-0000-4000-8000-000000000001');
do $$ begin
  assert (select status from cases where id = pg_temp.v('case')::uuid) = 'resolved', 'Mum sees the resolution';
  assert (select verify_answer from cases where id = pg_temp.v('vcase')::uuid) = 'no', 'Mum sees the answer';
end $$;
do $$ begin
  update cases set verify_answer = 'no', status = 'resolved' where id = pg_temp.v('dcase')::uuid;
  assert (select verify_answer from cases where id = pg_temp.v('dcase')::uuid) = 'no', 'Mum answers Daniel''s verify case';
end $$;
select pg_temp.fails('protected user answers her own verify case', format($q$update cases set verify_answer = 'yes' where id = %L$q$, pg_temp.v('vcase')));

-- Eve (another family) sees and changes nothing.
select pg_temp.login('00000000-0000-4000-8000-000000000003');
do $$ declare n int; begin
  assert (select count(*) from cases where circle_id = pg_temp.v('circle')::uuid) = 0, 'cross-family case read blocked';
  assert (select count(*) from members where circle_id = pg_temp.v('circle')::uuid) = 0, 'cross-family member read blocked';
  assert (select count(*) from circles where id = pg_temp.v('circle')::uuid) = 0, 'cross-family circle read blocked';
  update cases set status = 'open' where id = pg_temp.v('case')::uuid;
  get diagnostics n = row_count;
  assert n = 0, 'cross-family case update blocked';
end $$;
select pg_temp.fails('cross-family case insert', format(
  $q$insert into cases (circle_id, protected_member_id, level, category, summary_for_guardian)
     values (%L, %L, 2, 'other', 'x')$q$, pg_temp.v('circle'), pg_temp.v('mum')));
select pg_temp.fails('refresh another family''s code', format($q$select public.refresh_invite_code(%L)$q$, pg_temp.v('circle')));

-- Device tokens.
select pg_temp.login('00000000-0000-4000-8000-000000000002');
do $$ begin
  perform public.register_device(pg_temp.v('dan')::uuid, repeat('ab', 32), 'sandbox');
  perform public.register_device(pg_temp.v('dan')::uuid, repeat('ab', 32), 'production'); -- update, not duplicate
  assert (select count(*) from device_tokens) = 1, 'one row per token';
  assert (select environment from device_tokens) = 'production', 'token update applied';
end $$;
-- Another user presenting Daniel's token (reinstall / new session) takes it over.
select pg_temp.login('00000000-0000-4000-8000-000000000003');
do $$ begin
  perform public.register_device(pg_temp.v('eve')::uuid, repeat('ab', 32), 'sandbox');
  assert (select count(*) from device_tokens) = 1, 'new owner sees the moved token';
end $$;
select pg_temp.login('00000000-0000-4000-8000-000000000002');
do $$ begin
  assert (select count(*) from device_tokens) = 0, 'old owner lost the moved token';
  perform public.register_device(pg_temp.v('dan')::uuid, repeat('ab', 32), 'production');
end $$;
select pg_temp.fails('register a token for someone else''s membership',
  format($q$select public.register_device(%L, %L, 'sandbox')$q$, pg_temp.v('mum'), repeat('cd', 32)));
select pg_temp.fails('malformed token', format($q$select public.register_device(%L, 'not-a-token', 'sandbox')$q$, pg_temp.v('dan')));
select pg_temp.fails('direct insert into device_tokens', format(
  $q$insert into device_tokens (user_id, member_id, device_token, environment) values (auth.uid(), %L, %L, 'sandbox')$q$,
  pg_temp.v('dan'), repeat('ef', 32)));
select pg_temp.login('00000000-0000-4000-8000-000000000001');
do $$ begin
  assert (select count(*) from device_tokens) = 0, 'family members cannot read each other''s tokens';
  perform public.unregister_device(repeat('ab', 32));
end $$;
select pg_temp.login('00000000-0000-4000-8000-000000000002');
do $$ begin
  assert (select count(*) from device_tokens) = 1, 'someone else cannot unregister my token';
  perform public.unregister_device(repeat('ab', 32));
  assert (select count(*) from device_tokens) = 0, 'token removed';
end $$;
reset role;
insert into push_log (case_id, event) values (pg_temp.v('case')::uuid, 'test');
set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-000000000002');
do $$ begin
  assert (select count(*) from push_log) = 0, 'push_log is not readable by users';
end $$;

-- Not signed in (anon key only).
reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true), set_config('request.jwt.claim.sub', '', true);
select pg_temp.fails('anon creates a circle', $q$select public.create_circle('x')$q$);
select pg_temp.fails('anon registers a device', format($q$select public.register_device(%L, %L)$q$, pg_temp.v('dan'), repeat('ab', 32)));

-- Retention cleanup: old cases and stale rate-limit rows go, recent ones stay.
reset role;
insert into cases (circle_id, protected_member_id, level, category, summary_for_guardian, created_at)
  values (pg_temp.v('circle')::uuid, pg_temp.v('mum')::uuid, 2, 'other', 'old', now() - interval '31 days');
insert into join_attempts (user_id, created_at) values ('00000000-0000-4000-8000-000000000009', now() - interval '2 days');
insert into ai_calls (user_id, created_at) values ('00000000-0000-4000-8000-000000000009', now() - interval '2 days');
do $$ declare before int; begin
  before := (select count(*) from cases where created_at > now() - interval '1 day');
  perform public.stead_cleanup();
  assert not exists (select 1 from cases where summary_for_guardian = 'old'), 'old case deleted';
  assert (select count(*) from cases where created_at > now() - interval '1 day') = before, 'recent cases kept';
  assert not exists (select 1 from join_attempts where user_id = '00000000-0000-4000-8000-000000000009'), 'stale join attempts deleted';
  assert not exists (select 1 from ai_calls where user_id = '00000000-0000-4000-8000-000000000009'), 'stale ai calls deleted';
end $$;
set local role authenticated;
select pg_temp.fails('users cannot run the cleanup', $q$select public.stead_cleanup()$q$);

reset role;
do $$ begin raise notice 'authorization tests: ALL PASS'; end $$;
rollback;
