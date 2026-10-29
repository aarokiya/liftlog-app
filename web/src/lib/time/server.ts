import { cookies } from "next/headers";
import { DEFAULT_TIME_ZONE, validTimeZone } from ".";

/** The viewer's IANA time zone, from the cookie the browser sets (components/time-zone-cookie.tsx). */
export async function userTimeZone(): Promise<string> {
  const value = (await cookies()).get("tz")?.value;
  return validTimeZone(value ? decodeURIComponent(value) : null) ?? DEFAULT_TIME_ZONE;
}
