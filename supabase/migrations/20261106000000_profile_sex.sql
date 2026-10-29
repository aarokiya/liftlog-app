-- Sex for the body-fat formulas, plan thresholds and Wilks/DOTS; null hides them until it's set.
alter table profiles add column sex text check (sex in ('male', 'female'));
-- Accounts created before this setting existed got the male formulas.
update profiles set sex = 'male';
