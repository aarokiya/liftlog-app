# Programs (splits)

Built-in programs live in `shared/programs/*.json` and are used by both the web (Programs page) and the iPhone app (Routines → Programs): PPL, Upper/Lower, PPLUL, the Arnold split and the LKC split (Push, Pull, Legs, Delts & Arms, Rest, Upper, Rest, with zone-2 cardio on rest days). All exercises are chosen from Georgia Tech CRC equipment (`shared/gyms/gatech-crc.json`), and the gym profile lists same-pattern substitutes for each one.

Switching to a program creates its days as routines (tagged with `routines.program` / `program_day`) the first time and stores the choice in `profiles.active_program`. The phone shows the active program at the top of Routines with the next day marked "Up next".

## Importing a program (e.g. from a video)

Write a program (or have an AI assistant turn a split from a video into one) in this JSON format and paste it into Programs → Import on the web. Re-importing a program with the same name replaces its routines.

```json
{
  "name": "Video split",
  "split": "PPL",
  "schedule": "Six days, run twice a week.",
  "days": [
    {
      "name": "Push",
      "exercises": [
        { "exercise": 36, "sets": 3, "reps": [6, 10], "rest": 150, "notes": "Pause at the bottom" }
      ]
    }
  ]
}
```

- `exercise`: a built-in exercise number (the last digits of its id in `supabase/seed.sql`) or the uuid of any exercise in your library.
- `sets`: 1-20. `reps`: `[min, max]`. `rest` (seconds), `notes` and `attachment` (e.g. `"Rope · top pulley"`, shown under the exercise during a workout) are optional. Built-in templates may leave out `reps` for cardio, which is logged in minutes.
