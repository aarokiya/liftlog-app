# LiftLog

A strength-training tracker: a native **SwiftUI iPhone app** for logging in the gym and a **Next.js web app** for viewing and editing your training, stats, food and water. Works offline on the phone and syncs through Supabase.

**Try it:** https://liftlog-app-three.vercel.app (create an account with an email and a password).

## Features

- **Workouts:** routines and built-in programs (PPL, Upper/Lower, PPL + Upper/Lower, Arnold), JSON program import, rest days with optional cardio (Stairmaster, incline walk) logged in minutes, rest timer, set types, last session's numbers as placeholders.
- **Stats:** estimated 1RM and growth per exercise, PRs by rep range, plateau detection, weekly sets per muscle against targets, push:pull and quad:ham balance, workload (ACWR), streaks, Wilks/DOTS.
- **Body:** weight and tape measurements, body-fat estimates for men and women (Navy, RFM, or your own), a cut/bulk plan with a first checkpoint, Apple Health import and export.
- **Daily targets:** calories, protein, carbs and fat from your cut/bulk plan, with maintenance learned from your logs and weigh-ins and a 3-day carryover for days over or under. A goals calendar, editable food logs, and optional reminders (10am, 1pm, 8pm, plus 10pm for goals not hit).
- **Food and water:** official menus for 39 restaurant chains, 88 snack and drink brands, a 442k-item USDA food database with barcode lookup (Open Food Facts fallback), and a daily water goal.
- **Equipment swaps:** replace any exercise with another one for the same movement when your gym lacks the machine.
- **Campus extras (optional):** pick Georgia Tech in Settings for live dining-hall menus.
- **CSV import** from RepCount and Gymin.

## Privacy

Every row is private to its account (Postgres row-level security), Apple Health data stays on the phone, and there are no ads or trackers. You can delete your account and everything in it from Settings on the web or in the app. See [/privacy](https://liftlog-app-three.vercel.app/privacy).

## Prerequisites

- **iPhone app:** a Mac with a recent Xcode (the app is built with Xcode 27), [Homebrew](https://brew.sh) for XcodeGen, and a free Apple ID.
- **Web app:** Node.js 22.13 or later (pnpm 11 needs it). pnpm itself runs through `npx`, so you don't have to install it.

## Repo layout

| Path | What |
| --- | --- |
| `ios/` | SwiftUI app (iOS 17+, SwiftData, offline-first). The Xcode project is generated with XcodeGen. |
| `ios/Packages/LiftKit/` | Pure-Swift stats engine. |
| `web/` | Next.js (App Router) + Supabase, including the TypeScript port of the stats engine. |
| `shared/` | JSON shared by both apps: golden stats fixtures, program templates, gym equipment, food data. |
| `supabase/` | Postgres schema and row-level security (migrations) plus built-in exercises (`seed.sql`). |
| `scripts/` | Data generators and deploy/migration helpers. |
| `docs/` | Install guide, program format, sign-in setup, product plan. |

## iPhone app

No paid Apple developer account is needed. `ios/Config.example.xcconfig` points at the public backend, so you only need a unique bundle id:

```bash
brew install xcodegen
cd ios
cp Config.example.xcconfig Config.xcconfig   # set LIFTLOG_BUNDLE_ID to something unique
xcodegen generate
open LiftLog.xcodeproj
```

Pick your Personal Team (free Apple ID) under *Signing & Capabilities*, plug in your iPhone and run. To sync with the website, go to Settings → Sign in to sync → Create account (8+ character password). See [docs/INSTALL.md](docs/INSTALL.md) for details, including SideStore.

## Web app

```bash
cd web
cp .env.example .env.local   # fill in a Supabase URL and anon key (see below)
npx --yes pnpm@11.21.0 install
npx --yes pnpm@11.21.0 dev
```

To run against the public backend, copy `SUPABASE_URL` and `SUPABASE_ANON_KEY` from `ios/Config.example.xcconfig` into `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY`. Remove the `$()` from the URL (xcconfig needs it, `.env` doesn't), so it reads `https://fextdjsijkertbcdejsy.supabase.co`. The anon key is public by design; row-level security keeps each account's data private. To run against your own project, use its values instead.

## Self-hosting

1. Create a Supabase project and apply the schema: `SUPABASE_ACCESS_TOKEN=... SUPABASE_URL=... python3 scripts/supabase_migrate.py` (or `supabase db push`, then run `seed.sql`).
2. Optionally load the food database with `scripts/gen_foods.py` and `scripts/load_foods.py` (USDA FoodData Central CSVs).
3. Deploy `web/` with `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` set. `scripts/vercel_deploy.py` does this for Vercel. It reads `VERCEL_TOKEN`, `SUPABASE_URL` and `SUPABASE_ANON_KEY`, plus optional `VERCEL_PROJECT` (default `liftlog`), and passes through any `NEXT_PUBLIC_*` variables you set.
4. Sign-in options are configuration; see [docs/AUTH.md](docs/AUTH.md).

## Tests

```bash
cd web && npx --yes pnpm@11.21.0 typecheck && npx --yes pnpm@11.21.0 lint && npx --yes pnpm@11.21.0 test
cd ios/Packages/LiftKit && swift test
```

The stats math exists in both Swift and TypeScript; both suites run the same cases in `shared/fixtures/`.
