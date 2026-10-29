-- Shared food databank: USDA FoodData Central seed, Open Food Facts barcode cache, and user-created foods.
-- Macros are per serving; serving_g (when known) allows gram-based scaling.
create table foods (
  id uuid primary key default gen_random_uuid(),
  source text not null check (source in ('usda', 'off', 'user')),
  source_id text,
  barcode text check (barcode ~ '^[0-9]{6,14}$'),
  name text not null check (char_length(name) between 1 and 200),
  brand text check (char_length(brand) <= 120),
  serving text not null default '100 g' check (char_length(serving) <= 120),
  serving_g numeric(7, 1) check (serving_g > 0),
  kcal numeric(7, 1) not null default 0 check (kcal >= 0),
  protein numeric(6, 1) not null default 0 check (protein >= 0),
  carbs numeric(6, 1) not null default 0 check (carbs >= 0),
  fat numeric(6, 1) not null default 0 check (fat >= 0),
  rank smallint not null default 1,
  search tsvector generated always as (to_tsvector('simple', coalesce(brand, '') || ' ' || name)) stored,
  created_by uuid default auth.uid() references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on column foods.rank is '0 = generic USDA (preferred in search), 1 = branded / user / Open Food Facts';

create unique index foods_source_key on foods (source, source_id) where source_id is not null;
create index foods_barcode on foods (barcode) where barcode is not null;
create index foods_search on foods using gin (search);
create trigger foods_updated_at before update on foods for each row execute function set_updated_at();

alter table foods enable row level security;
create policy "signed-in users read" on foods for select to authenticated using (true);
create policy "add user or barcode foods" on foods for insert to authenticated
  with check (source in ('user', 'off') and created_by = auth.uid());
create policy "edit own foods" on foods for update to authenticated
  using (source = 'user' and created_by = auth.uid()) with check (source = 'user' and created_by = auth.uid());
create policy "delete own foods" on foods for delete to authenticated using (source = 'user' and created_by = auth.uid());

-- Prefix search over brand + name: every word must match ("chob gree" finds Chobani Greek Yogurt).
create function search_foods(q text, max_rows int default 50) returns setof foods
language sql stable set search_path = public as $$
  with terms as (
    select string_agg(w || ':*', ' & ') as tsq
    from unnest(regexp_split_to_array(lower(regexp_replace(q, '[^[:alnum:] ]', ' ', 'g')), '\s+')) as w
    where w <> ''
  )
  select f.* from foods f, terms
  where terms.tsq is not null and f.search @@ to_tsquery('simple', terms.tsq)
  order by f.rank, ts_rank(f.search, to_tsquery('simple', terms.tsq)) desc, char_length(f.name)
  limit least(greatest(max_rows, 1), 100)
$$;
