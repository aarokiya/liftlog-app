import { getProfile } from "@/lib/data";
import { requireUser } from "@/lib/supabase/server";
import { userTimeZone } from "@/lib/time/server";
import { ImportForm } from "./import-form";

export default async function ImportPage() {
  const { supabase, user } = await requireUser();
  const profile = await getProfile(supabase, user.id);
  return (
    <div className="flex max-w-2xl flex-col gap-4">
      <h1 className="text-xl font-semibold">Import workout history</h1>
      <p className="text-sm text-muted">
        Upload a CSV export from RepCount (Statistics → CSV Export) or Gymin. Workouts already imported are skipped, so
        re-running is safe. Body weight columns go to your body-weight log, notes like “Dropped 140 5” become drop sets, and
        exercise names are matched to the library; anything unmatched becomes a custom exercise.
      </p>
      <ImportForm unit={profile.default_unit} timeZone={await userTimeZone()} />
    </div>
  );
}
