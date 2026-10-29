-- Hardening for a public instance.

-- Foods: everyone shares the USDA (and older Open Food Facts) rows; foods a user adds, including barcode hits from
-- Open Food Facts, are theirs alone, so nobody can push spam or wrong data into other people's search.
drop policy "signed-in users read" on foods;
create policy "read shared and own foods" on foods for select to authenticated
  using (source <> 'user' or created_by = (select auth.uid()));
drop policy "add user or barcode foods" on foods;
create policy "add own foods" on foods for insert to authenticated
  with check (source = 'user' and created_by = (select auth.uid()) and rank = 1);
drop policy "edit own foods" on foods;
create policy "edit own foods" on foods for update to authenticated
  using (source = 'user' and created_by = (select auth.uid()))
  with check (source = 'user' and created_by = (select auth.uid()) and rank = 1);

-- At most 100 new foods per user per day.
create index foods_created_by_at on foods (created_by, created_at) where created_by is not null;
create function foods_insert_quota() returns trigger language plpgsql set search_path = '' as $$
begin
  if (select count(*) from public.foods where created_by = new.created_by and created_at > now() - interval '1 day') >= 100 then
    raise exception 'Daily limit for new foods reached' using errcode = '54000';
  end if;
  return new;
end;
$$;
create trigger foods_insert_quota before insert on foods for each row when (new.created_by is not null)
  execute function foods_insert_quota();

-- Least privilege: TRUNCATE bypasses RLS, and clients never need TRIGGER or REFERENCES.
revoke truncate, trigger, references on all tables in schema public from anon, authenticated;
alter default privileges for role postgres in schema public revoke truncate, trigger, references on tables from anon, authenticated;

-- Functions: fixed search paths; trigger functions don't need EXECUTE; only signed-in users search foods.
alter function set_updated_at() set search_path = '';
revoke execute on function handle_new_user() from public, anon, authenticated;
revoke execute on function foods_insert_quota() from public, anon, authenticated;
revoke execute on function search_foods(text, int) from public, anon;
grant execute on function search_foods(text, int) to authenticated;
