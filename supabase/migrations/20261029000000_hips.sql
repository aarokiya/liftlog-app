-- Hip circumference for waist-to-hip ratio.
alter table body_metrics add column hips_cm numeric(5, 1) check (hips_cm between 40 and 250);
