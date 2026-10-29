-- Lets a signed-in user delete their own account. Their rows go with it (every user table cascades from auth.users);
-- foods they created are deleted too rather than left behind without an owner.
create or replace function public.delete_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;
  delete from public.foods where created_by = auth.uid() and source = 'user';
  delete from auth.users where id = auth.uid();
end;
$$;

revoke execute on function public.delete_account() from public, anon;
grant execute on function public.delete_account() to authenticated;
