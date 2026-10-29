-- Water log: amounts are stored as entered, in US fluid ounces or millilitres.
create table water_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  drank_at timestamptz not null,
  amount numeric(6, 1) not null check (amount > 0 and amount <= 5000),
  unit text not null default 'oz' check (unit in ('oz', 'ml')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index water_logs_user_updated on water_logs (user_id, updated_at);
create index water_logs_user_drank on water_logs (user_id, drank_at) where deleted_at is null;
create trigger water_logs_updated_at before update on water_logs for each row execute function set_updated_at();
alter table water_logs enable row level security;
create policy "own rows" on water_logs for all using (user_id = auth.uid()) with check (user_id = auth.uid());
