-- Optional campus. 'gatech' turns on Georgia Tech dining-hall menus and CRC same-movement swaps; null = no campus features.
alter table profiles add column campus text check (campus in ('gatech'));
-- Accounts created before this setting existed were all Georgia Tech users.
update profiles set campus = 'gatech';
