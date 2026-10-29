import type { OneRepMaxFormula, SetType, WeightUnit } from "./stats";

export interface Profile {
  id: string;
  display_name: string | null;
  default_unit: WeightUnit;
  e1rm_formula: OneRepMaxFormula;
  weekly_workout_target: number;
  bar_weight: number;
  plate_inventory: number[];
  height_cm?: number | null;
  active_program?: string | null;
  /** 'gatech' turns on Georgia Tech dining halls and CRC swaps. */
  campus?: "gatech" | null;
  /** Picks the body-fat formulas, plan thresholds and Wilks/DOTS; null hides them. */
  sex?: "male" | "female" | null;
}

export interface Exercise {
  id: string;
  user_id: string | null;
  name: string;
  kind: string;
  equipment: string | null;
  primary_muscle: string;
  secondary_muscles: string[];
}

export interface SetRow {
  id: string;
  position: number;
  set_type: SetType;
  weight: number | null;
  weight_unit: WeightUnit;
  reps: number | null;
  rpe: number | null;
  notes: string | null;
  deleted_at: string | null;
}

export interface WorkoutExerciseRow {
  id: string;
  exercise_id: string;
  position: number;
  notes: string | null;
  deleted_at: string | null;
  exercises: Pick<Exercise, "id" | "name" | "primary_muscle" | "secondary_muscles"> | null;
  sets: SetRow[];
}

export interface WorkoutRow {
  id: string;
  name: string;
  notes: string | null;
  started_at: string;
  ended_at: string | null;
  timezone: string;
  workout_exercises: WorkoutExerciseRow[];
}

export const MUSCLE_LABELS: Record<string, string> = {
  chest: "Chest",
  back: "Back",
  traps: "Traps",
  front_delts: "Front delts",
  side_delts: "Side delts",
  rear_delts: "Rear delts",
  biceps: "Biceps",
  triceps: "Triceps",
  forearms: "Forearms",
  core: "Core",
  quads: "Quads",
  hamstrings: "Hamstrings",
  glutes: "Glutes",
  calves: "Calves",
  adductors: "Adductors",
  abductors: "Abductors",
  hip_flexors: "Hip flexors",
};
