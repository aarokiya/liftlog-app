import Link from "next/link";
import { getProfile } from "@/lib/data";
import { requireUser } from "@/lib/supabase/server";
import { deleteAccount } from "../../login/actions";
import { logMeasurement, updateSettings } from "./actions";

export default async function SettingsPage({ searchParams }: { searchParams: Promise<{ welcome?: string; delete?: string }> }) {
  const { welcome, delete: deleteState } = await searchParams;
  const { supabase, user } = await requireUser();
  const p = await getProfile(supabase, user.id);
  const len = p.default_unit === "lb" ? "in" : "cm";
  const height = p.height_cm ? (p.default_unit === "lb" ? Math.round((p.height_cm / 2.54) * 10) / 10 : p.height_cm) : "";
  return (
    <div className="flex flex-col gap-6">
    {welcome && (
      <div className="card max-w-md text-sm">
        <h1 className="mb-1 text-lg font-semibold">Welcome to LiftLog</h1>
        <p className="text-muted">
          Pick your units, sex and height so stats and the body plan work, then log a workout on your phone or under
          Workouts. Pick Georgia Tech as your campus for dining-hall menus and CRC equipment swaps.
        </p>
      </div>
    )}
    <form action={updateSettings} className="card flex max-w-md flex-col gap-3 text-sm">
      <label className="flex flex-col gap-1">Name<input name="display_name" defaultValue={p.display_name ?? ""} className="input" /></label>
      <label className="flex flex-col gap-1">Default unit
        <select name="default_unit" defaultValue={p.default_unit} className="input"><option>lb</option><option>kg</option></select>
      </label>
      <label className="flex flex-col gap-1">1RM formula
        <select name="e1rm_formula" defaultValue={p.e1rm_formula} className="input"><option>epley</option><option>brzycki</option><option>lombardi</option></select>
      </label>
      <label className="flex flex-col gap-1">Weekly workout target<input name="weekly_workout_target" type="number" min={1} max={14} defaultValue={p.weekly_workout_target} className="input" /></label>
      <label className="flex flex-col gap-1">Bar weight<input name="bar_weight" type="number" step="0.5" defaultValue={p.bar_weight} className="input" /></label>
      <label className="flex flex-col gap-1">Height ({len})<input name="height" type="number" step="0.1" defaultValue={height} className="input" /></label>
      <label className="flex flex-col gap-1">Sex (for body-fat formulas, the body plan and Wilks/DOTS)
        <select name="sex" defaultValue={p.sex ?? ""} className="input">
          <option value="">Not set</option>
          <option value="male">Male</option>
          <option value="female">Female</option>
        </select>
      </label>
      <label className="flex flex-col gap-1">Campus
        <select name="campus" defaultValue={p.campus ?? ""} className="input">
          <option value="">None</option>
          <option value="gatech">Georgia Tech (dining halls, CRC swaps)</option>
        </select>
      </label>
      <button className="btn self-start">Save</button>
    </form>
    <form action={logMeasurement} className="card flex max-w-md flex-col gap-3 text-sm">
      <h2 className="font-medium">Log body measurements</h2>
      <p className="text-xs text-muted">Waist at the lower belly, relaxed; hips at the widest point; neck just below the larynx. Used for body fat, waist-to-height and waist-to-hip on the dashboard. Neck is optional: without it body fat is estimated from height and waist.</p>
      <input type="hidden" name="unit" value={p.default_unit} />
      <label className="flex flex-col gap-1">Body weight ({p.default_unit})<input name="body_weight" type="number" step="0.1" className="input" /></label>
      <label className="flex flex-col gap-1">Waist ({len})<input name="waist" type="number" step="0.1" className="input" /></label>
      <label className="flex flex-col gap-1">Hips ({len})<input name="hips" type="number" step="0.1" className="input" /></label>
      <label className="flex flex-col gap-1">Neck ({len})<input name="neck" type="number" step="0.1" className="input" /></label>
      <label className="flex flex-col gap-1">Body fat % (optional: your own estimate or a scan; overrides the tape formulas)<input name="body_fat" type="number" step="0.1" min={2} max={70} className="input" /></label>
      <button className="btn self-start">Log</button>
    </form>
    <form action={deleteAccount} className="card flex max-w-md flex-col gap-3 text-sm">
      <h2 className="font-medium">Delete account</h2>
      <p className="text-xs text-muted">
        Deletes your account ({user.email}) and everything logged under it, on the web and for sync. This can&apos;t be undone. Data already on
        your phone stays there. <Link href="/privacy" className="text-accent">Privacy</Link>
      </p>
      <label className="flex flex-col gap-1">Type DELETE to confirm<input name="confirm" autoComplete="off" className="input" /></label>
      {deleteState === "confirm" && <p className="text-xs text-red-500">Type DELETE in capitals to confirm.</p>}
      {deleteState === "failed" && <p className="text-xs text-red-500">Couldn&apos;t delete the account. Try again.</p>}
      <button className="self-start rounded-lg bg-red-600 px-3 py-1.5 text-sm font-medium text-white hover:brightness-110">Delete account</button>
    </form>
    </div>
  );
}
