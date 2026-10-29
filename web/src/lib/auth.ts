// Which sign-in methods this deployment offers. Email links (magic link, password reset) need a working email sender
// in Supabase, and each OAuth provider must be enabled in the Supabase project.

export const OAUTH_PROVIDERS = (process.env.NEXT_PUBLIC_OAUTH_PROVIDERS ?? "")
  .split(",")
  .map((p) => p.trim())
  .filter((p): p is "google" | "github" => p === "google" || p === "github");

export const EMAIL_LINKS = process.env.NEXT_PUBLIC_EMAIL_LINKS === "true";

export const MIN_PASSWORD = 8;

/**
 * Messages /login and /auth/reset can show, by code. Pages only show text from this list, so a crafted
 * `?error=` link can't put its own words on the sign-in page.
 */
export const AUTH_MESSAGES = {
  invalid_credentials: "Wrong email or password.",
  user_already_exists: "There's already an account with that email. Sign in instead.",
  weak_password: `Use at least ${MIN_PASSWORD} characters for your password.`,
  email_address_invalid: "That email address doesn't look right.",
  email_not_confirmed: "Confirm your email first, then sign in.",
  rate_limited: "Too many tries. Wait a minute and try again.",
  signup_disabled: "New accounts aren't open on this site.",
  provider: "That sign-in method isn't available.",
  email_links_off: "Email links aren't available on this site.",
  link: "That link is invalid or has expired.",
  callback: "Sign-in didn't finish. Try again.",
  deleted: "Your account and its data were deleted.",
  failed: "Something went wrong. Try again.",
} as const;

export type AuthMessage = keyof typeof AUTH_MESSAGES;

/** The code for a Supabase auth error, falling back to a generic one. */
export function authErrorCode(error: { code?: string; status?: number }): AuthMessage {
  const code = error.code ?? "";
  if (code in AUTH_MESSAGES) return code as AuthMessage;
  if (code.startsWith("over_") || error.status === 429) return "rate_limited";
  if (code === "email_provider_disabled") return "signup_disabled";
  return "failed";
}

export const authMessage = (code: string | undefined) => (code ? AUTH_MESSAGES[code as AuthMessage] ?? AUTH_MESSAGES.failed : null);

/** A same-site path to continue to after sign-in; anything else falls back to "/". */
export function safeNext(next: string | null | undefined): string {
  return next && next.startsWith("/") && !next.startsWith("//") && !next.startsWith("/\\") ? next : "/";
}
