-- Training programs (PPL, UL, PPLUL, Arnold or imported). A program is the set of routines sharing `program`;
-- `program_day` orders them. The profile remembers which program is active.
alter table routines add column program text;
alter table routines add column program_day int check (program_day >= 0);
alter table profiles add column active_program text;
create index routines_user_program on routines (user_id, program) where deleted_at is null;
