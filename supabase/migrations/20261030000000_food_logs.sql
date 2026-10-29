-- Food log: dining-hall menu items, staples, fast food and custom entries. Macros are per serving.
create table food_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  eaten_at timestamptz not null,
  meal text not null default 'snack' check (meal in ('breakfast', 'lunch', 'dinner', 'snack')),
  source text not null check (source in ('dining', 'outside', 'custom')),
  place text,
  name text not null check (char_length(name) between 1 and 200),
  serving text,
  servings numeric(5, 2) not null default 1 check (servings > 0 and servings <= 50),
  kcal numeric(7, 1) not null default 0 check (kcal >= 0),
  protein numeric(6, 1) not null default 0 check (protein >= 0),
  carbs numeric(6, 1) not null default 0 check (carbs >= 0),
  fat numeric(6, 1) not null default 0 check (fat >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index food_logs_user_updated on food_logs (user_id, updated_at);
create index food_logs_user_eaten on food_logs (user_id, eaten_at) where deleted_at is null;
create trigger food_logs_updated_at before update on food_logs for each row execute function set_updated_at();
alter table food_logs enable row level security;
create policy "own rows" on food_logs for all using (user_id = auth.uid()) with check (user_id = auth.uid());
