-- Built-in exercises for the machine-first V-taper plan (seed.sql only runs on an empty project).
insert into exercises (id, user_id, name, kind, equipment, primary_muscle, secondary_muscles) values
  ('00000000-0000-4000-8000-000000000067', null, 'Incline Bench Press (Smith)', 'weight_reps', 'machine', 'chest', '{front_delts,triceps}'),
  ('00000000-0000-4000-8000-000000000068', null, 'Bayesian Curl (Cable)', 'weight_reps', 'cable', 'biceps', '{}'),
  ('00000000-0000-4000-8000-000000000069', null, 'Hammer Curl (Cable)', 'weight_reps', 'cable', 'biceps', '{forearms}')
on conflict (id) do nothing;
