// Wall-clock helpers. Pages render on the server (UTC), so times are shown and parsed in an explicit IANA zone.

export const DEFAULT_TIME_ZONE = "America/New_York";

/** The zone if Intl knows it, else null. */
export function validTimeZone(timeZone: string | null | undefined): string | null {
  if (!timeZone) return null;
  try {
    new Intl.DateTimeFormat("en-US", { timeZone });
    return timeZone;
  } catch {
    return null;
  }
}

/** `YYYY-MM-DDTHH:mm` wall-clock time of an instant in `timeZone`, for datetime-local inputs. */
export function toZonedInput(instant: string | Date, timeZone: string): string {
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat("en-CA", {
      timeZone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      hourCycle: "h23",
    })
      .formatToParts(new Date(instant))
      .map((p) => [p.type, p.value]),
  );
  return `${parts.year}-${parts.month}-${parts.day}T${parts.hour}:${parts.minute}`;
}

/** The instant a wall-clock `YYYY-MM-DDTHH:mm` time in `timeZone` refers to. */
export function fromZonedInput(local: string, timeZone: string): Date {
  const asUtc = new Date(`${local.slice(0, 16)}:00Z`).getTime();
  const offset = (t: number) => new Date(`${toZonedInput(new Date(t), timeZone)}:00Z`).getTime() - t;
  const first = asUtc - offset(asUtc);
  // Second pass settles times near a daylight-saving change.
  return new Date(asUtc - offset(first));
}
