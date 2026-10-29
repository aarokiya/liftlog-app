"use client";

import { useActionState } from "react";
import { importRepCount, type ImportState } from "./actions";

export function ImportForm({ unit, timeZone }: { unit: string; timeZone: string }) {
  const [state, action, pending] = useActionState<ImportState, FormData>(importRepCount, {});
  return (
    <div className="flex flex-col gap-4">
      <form action={action} className="card flex flex-wrap items-center gap-3">
        <input type="file" name="file" accept=".csv,text/csv" required className="text-sm" />
        <input type="hidden" name="timezone" value={timeZone} />
        <input type="hidden" name="unit" value={unit} />
        <button className="btn" disabled={pending}>
          {pending ? "Importing…" : "Import"}
        </button>
      </form>
      {state.error && <p className="text-sm text-red-500">{state.error}</p>}
      {state.imported !== undefined && (
        <div className="card text-sm">
          <p>
            Imported {state.imported} workouts from {state.source === "gymin" ? "Gymin" : "RepCount"}
            {state.skipped ? `, skipped ${state.skipped} already imported` : ""}
            {state.bodyWeights ? `, plus ${state.bodyWeights} body-weight entries` : ""}.
          </p>
          {state.renamed && Object.keys(state.renamed).length > 0 && (
            <p className="mt-2 text-muted">
              Matched to library:{" "}
              {Object.entries(state.renamed)
                .map(([from, to]) => `${from} → ${to}`)
                .join(", ")}
            </p>
          )}
          {state.createdExercises && state.createdExercises.length > 0 && (
            <p className="mt-2 text-muted">
              New custom exercises (set their muscles on the Exercises page): {state.createdExercises.join(", ")}
            </p>
          )}
        </div>
      )}
      {state.columns && (
        <p className="text-xs text-muted">
          Columns used:{" "}
          {Object.entries(state.columns)
            .map(([field, header]) => `${field} ← “${header}”`)
            .join(", ")}
        </p>
      )}
    </div>
  );
}
