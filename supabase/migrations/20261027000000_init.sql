-- LiftLog core schema. Multi-user from day one: every user-owned row is protected by RLS on user_id.
-- Sync contract: ids are client-generated UUIDs; updated_at drives incremental pulls; deleted_at is a tombstone.

create extension if not exists "pgcrypto";

create type weight_unit as enum ('lb', 'kg');
create type set_type as enum ('warmup', 'working', 'drop', 'failure');
create type exercise_kind as enum ('weight_reps', 'bodyweight', 'weighted_bodyweight', 'assisted_bodyweight', 'duration', 'distance');
create type e1rm_formula as enum ('epley', 'brzycki', 'lombardi');

create or replace function set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  default_unit weight_unit not null default 'lb',
  e1rm_formula e1rm_formula not null default 'epley',
  weekly_workout_target int not null default 3 check (weekly_workout_target between 1 and 14),
  bar_weight numeric(6, 2) not null default 45,
  plate_inventory numeric(6, 2)[] not null default '{45,35,25,10,5,2.5}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- user_id null = built-in library exercise, readable by everyone.
create table exercises (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users (id) on delete cascade,
  name text not null,
  kind exercise_kind not null default 'weight_reps',
  equipment text,
  primary_muscle text not null,
  secondary_muscles text[] not null default '{}',
  unilateral boolean not null default false,
  default_rest_seconds int not null default 120,
  sticky_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table routine_folders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null,
  position int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table routines (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  folder_id uuid references routine_folders (id) on delete set null,
  name text not null,
  notes text,
  position int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table routine_exercises (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  routine_id uuid not null references routines (id) on delete cascade,
  exercise_id uuid not null references exercises (id),
  position int not null default 0,
  superset_group int,
  target_sets int not null default 3 check (target_sets between 0 and 50),
  rep_min int check (rep_min >= 0),
  rep_max int check (rep_max >= rep_min),
  rest_seconds int,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table workouts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  routine_id uuid references routines (id) on delete set null,
  name text not null,
  notes text,
  started_at timestamptz not null,
  ended_at timestamptz check (ended_at is null or ended_at >= started_at),
  timezone text not null default 'UTC',
  source text not null default 'app',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table workout_exercises (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  workout_id uuid not null references workouts (id) on delete cascade,
  exercise_id uuid not null references exercises (id),
  position int not null default 0,
  superset_group int,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table sets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  workout_exercise_id uuid not null references workout_exercises (id) on delete cascade,
  position int not null default 0,
  set_type set_type not null default 'working',
  weight numeric(8, 3),
  weight_unit weight_unit not null default 'lb',
  reps int check (reps >= 0),
  duration_seconds int check (duration_seconds >= 0),
  distance_meters numeric(10, 2) check (distance_meters >= 0),
  rpe numeric(3, 1) check (rpe between 1 and 10),
  rir int check (rir >= 0),
  notes text,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table body_metrics (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  measured_at timestamptz not null,
  body_weight numeric(6, 2),
  unit weight_unit not null default 'lb',
  body_fat_pct numeric(4, 1) check (body_fat_pct between 0 and 100),
  source text not null default 'manual',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- Incremental sync pulls: "everything of mine changed since cursor".
create index exercises_user_updated on exercises (user_id, updated_at);
create index routine_folders_user_updated on routine_folders (user_id, updated_at);
create index routines_user_updated on routines (user_id, updated_at);
create index routine_exercises_user_updated on routine_exercises (user_id, updated_at);
create index workouts_user_updated on workouts (user_id, updated_at);
create index workout_exercises_user_updated on workout_exercises (user_id, updated_at);
create index sets_user_updated on sets (user_id, updated_at);
create index body_metrics_user_updated on body_metrics (user_id, updated_at);

create index workouts_user_started on workouts (user_id, started_at desc) where deleted_at is null;
create index workout_exercises_workout on workout_exercises (workout_id);
create index workout_exercises_exercise on workout_exercises (user_id, exercise_id);
create index sets_workout_exercise on sets (workout_exercise_id);
create index routine_exercises_routine on routine_exercises (routine_id);

do $$
declare t text;
begin
  foreach t in array array['profiles', 'exercises', 'routine_folders', 'routines', 'routine_exercises',
                           'workouts', 'workout_exercises', 'sets', 'body_metrics'] loop
    execute format('create trigger %I_updated_at before update on %I for each row execute function set_updated_at()', t, t);
    execute format('alter table %I enable row level security', t);
  end loop;
end;
$$;

create policy "own profile" on profiles
  for all using (id = auth.uid()) with check (id = auth.uid());

create policy "read library and own exercises" on exercises
  for select using (user_id is null or user_id = auth.uid());
create policy "insert own exercises" on exercises
  for insert with check (user_id = auth.uid());
create policy "update own exercises" on exercises
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "delete own exercises" on exercises
  for delete using (user_id = auth.uid());

do $$
declare t text;
begin
  foreach t in array array['routine_folders', 'routines', 'routine_exercises', 'workouts',
                           'workout_exercises', 'sets', 'body_metrics'] loop
    execute format('create policy "own rows" on %I for all using (user_id = auth.uid()) with check (user_id = auth.uid())', t);
  end loop;
end;
$$;

-- Create a profile row automatically on sign-up.
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name'));
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();
