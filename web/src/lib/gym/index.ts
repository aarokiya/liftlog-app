import crc from "../../../../shared/gyms/gatech-crc.json";

export interface GymProfile {
  id: string;
  name: string;
  equipment: Record<string, string>;
  plates_lb: number[];
  dumbbell_max_lb: number;
  substitution_groups: { pattern: string; exercises: number[] }[];
}

export const GYMS: GymProfile[] = [crc];

export const builtInId = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;

/** Movement pattern of a built-in exercise, e.g. "vertical_pull". */
export function patternOf(gym: GymProfile, exerciseId: string): string | null {
  return gym.substitution_groups.find((g) => g.exercises.some((n) => builtInId(n) === exerciseId))?.pattern ?? null;
}

/** Other exercises at this gym that train the same pattern, in preference order. */
export function substitutes(gym: GymProfile, exerciseId: string): string[] {
  const group = gym.substitution_groups.find((g) => g.exercises.some((n) => builtInId(n) === exerciseId));
  return group ? group.exercises.map(builtInId).filter((id) => id !== exerciseId) : [];
}
