-- One phone can belong to several circles (a guardian looking after two people), so a token is
-- unique per membership, not globally. A token presented by a different user (reinstall, new
-- anonymous session) still moves to them: their old rows for it are removed.

alter table public.device_tokens drop constraint if exists device_tokens_device_token_key;
alter table public.device_tokens add constraint device_tokens_member_token unique (member_id, device_token);
create index if not exists device_tokens_token on public.device_tokens (device_token);

create or replace function public.register_device(p_member_id uuid, p_token text, p_environment text default 'production')
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if not exists (select 1 from members m where m.id = p_member_id and m.user_id = auth.uid()) then
    raise exception 'not your membership';
  end if;
  delete from device_tokens where device_token = lower(p_token) and user_id <> auth.uid();
  insert into device_tokens (user_id, member_id, device_token, environment)
    values (auth.uid(), p_member_id, lower(p_token), p_environment)
    on conflict (member_id, device_token) do update
      set environment = excluded.environment, updated_at = now()
    returning id into v_id;
  return v_id;
end $$;

revoke execute on function public.register_device(uuid, text, text) from public, anon;
grant execute on function public.register_device(uuid, text, text) to authenticated;
