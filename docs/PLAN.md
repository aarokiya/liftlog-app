# LiftLog plan

## Decisions

| Decision | Choice | Why |
| --- | --- | --- |
| Phone app | Native SwiftUI, iOS 17+ | Best native feel; first-class HealthKit, Live Activities, widgets, Apple Watch later. |
| Local storage | SwiftData | Offline-first; logging never waits on the network. |
| Backend | Supabase (Postgres, Auth, RLS) | Multi-user from day one so friends can sign up later; Sign in with Apple + email. |
| Web | Next.js on Vercel | Full view **and edit** of workouts, routines, exercises. |
| Stats parity | Swift `LiftKit` + TypeScript `web/src/lib/stats`, both tested against `shared/fixtures/*.json` | The math is written twice, so shared golden tests keep it identical. |
| Units | Store weight **as entered + unit**; default **lb** | Avoids lb→kg→lb rounding breaking PR detection. |
| Sync | Client UUIDs, `updated_at`, `deleted_at` tombstones, last-write-wins per row | Simple and correct enough for one user across phone + browser. |
| History import | RepCount CSV export | Existing history powers stats on day one. |

## Stats catalogue

- **Set**: estimated 1RM (Epley default; Brzycki, Lombardi selectable; ignored above 12 reps), volume load, relative intensity.
- **Workout**: duration, volume, sets, reps, PRs hit, density, comparison vs last session of same routine.
- **Exercise**: e1RM over time + trend (lb/week), rep-range PRs (1–20), heaviest weight, best set/session volume, plateau detection, relative strength (÷ body weight), Wilks/DOTS for SBD.
- **Muscle**: weekly hard sets per muscle (primary 1, secondary 0.5), heatmap, push:pull and quad:ham ratios, frequency.
- **Lifetime**: workouts/week, streaks, consistency, calendar heatmap, total tonnage, acute:chronic workload ratio, day-of-week patterns, body weight trend.

## Phases

0. **Setup**: repo, CI, Apple Developer, Supabase, Vercel.
1. **Core logging (offline)**: exercise library, active workout, set logging with previous values, rest timer + notification, history.
2. **Routines and gym UX**: routines/folders, supersets, set types, RPE, notes, plate + warm-up calculators. *MVP.*
3. **Auth, sync, web**: Supabase auth, sync worker, web history + editing.
4. **Stats and charts**: exercise detail, PRs, muscle map, dashboards on phone and web.
5. **iOS polish**: HealthKit, Live Activities, widgets.
6. **Import/export**: RepCount CSV import, CSV/JSON export, backups.
7. **Later**: Apple Watch, progression suggestions, App Store release for friends.

## Gotchas

- Persist every set change immediately; restore an in-progress workout on launch.
- Rest timer: schedule a local notification for the end time; compute remaining from timestamps.
- Store UTC timestamps + workout timezone so weekly stats don't shift when travelling.
- Free Supabase projects pause after ~1 week idle.
- Friends via TestFlight external testing requires Beta App Review; App Store release requires a privacy policy and account deletion in-app.
