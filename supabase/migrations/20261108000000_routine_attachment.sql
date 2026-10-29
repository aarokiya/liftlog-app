-- What to clip on for an exercise in a routine (e.g. "Rope · top pulley"); the workout screen shows it under the name.
alter table routine_exercises add column attachment text check (char_length(attachment) <= 80);
