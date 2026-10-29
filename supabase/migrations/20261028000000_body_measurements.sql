-- Body measurements for aesthetics stats (waist-to-height, Navy body fat). Height lives on the profile.
alter table profiles add column height_cm numeric(5, 1) check (height_cm between 50 and 260);
alter table body_metrics add column waist_cm numeric(5, 1) check (waist_cm between 30 and 250);
alter table body_metrics add column neck_cm numeric(5, 1) check (neck_cm between 15 and 80);
