import Link from "next/link";

export const metadata = { title: "Privacy · LiftLog" };

export default function PrivacyPage() {
  return (
    <main className="mx-auto flex max-w-2xl flex-col gap-4 p-6 text-sm leading-relaxed">
      <h1 className="text-2xl font-semibold">Privacy</h1>
      <p className="text-muted">LiftLog is a free, open-source strength and food tracker. This page says what it keeps and where.</p>

      <h2 className="text-base font-semibold">What&apos;s stored</h2>
      <ul className="list-disc pl-5">
        <li>Your email address and password (hashed by Supabase Auth), so you can sign in.</li>
        <li>What you log: workouts, sets, routines, body weight and measurements, body-fat %, food, water, and settings such as height, sex and units.</li>
        <li>Foods you create or scan, which only you can see.</li>
      </ul>

      <h2 className="text-base font-semibold">Where it&apos;s kept</h2>
      <p>
        Data is stored in a Supabase Postgres database. Row-level security limits every row to the account that owns it. The website is hosted on
        Vercel. In the iPhone app, everything stays on the phone until you sign in to sync.
      </p>

      <h2 className="text-base font-semibold">Apple Health</h2>
      <p>
        If you turn on Apple Health, the app reads weight, height, body fat, waist, daily nutrition and steps on your phone and writes workouts and
        weight. Data read from Health is never uploaded. Only what you log in LiftLog syncs.
      </p>

      <h2 className="text-base font-semibold">Other services</h2>
      <ul className="list-disc pl-5">
        <li>Barcodes you scan that aren&apos;t in the food databank are looked up on Open Food Facts. Only the barcode is sent.</li>
        <li>Georgia Tech dining menus come from Nutrislice. Nothing about you is sent.</li>
      </ul>
      <p>There are no ads and no analytics or tracking scripts. Nothing is sold or shared.</p>

      <h2 className="text-base font-semibold">Deleting your data</h2>
      <p>
        Delete your account from Settings on the website or in the app. That deletes your account and everything logged under it straight
        away. Data on your phone stays there until you delete the app.
      </p>

      <h2 className="text-base font-semibold">Questions</h2>
      <p>
        Open an issue at{" "}
        <a className="text-accent" href="https://github.com/aarokiya/liftlog-app/issues">
          github.com/aarokiya/liftlog-app
        </a>
        .
      </p>
      <Link href="/" className="text-accent">
        ← Back to LiftLog
      </Link>
    </main>
  );
}
