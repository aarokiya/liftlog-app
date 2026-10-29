import Link from "next/link";
import { EMAIL_LINKS, MIN_PASSWORD, OAUTH_PROVIDERS, authMessage, safeNext } from "@/lib/auth";
import { sendPasswordReset, signInWithEmail, signInWithPassword, signInWithProvider } from "./actions";

const PROVIDER_LABELS = { google: "Google", github: "GitHub" } as const;

export default async function LoginPage({ searchParams }: { searchParams: Promise<{ sent?: string; error?: string; next?: string }> }) {
  const { sent, error, next: rawNext } = await searchParams;
  const next = safeNext(rawNext);
  const message = authMessage(error);
  return (
    <main className="mx-auto flex min-h-screen max-w-sm flex-col justify-center gap-6 p-6">
      <div>
        <h1 className="text-2xl font-semibold">LiftLog</h1>
        <p className="text-sm text-muted">Log workouts, track strength and food. New here? Enter an email and a password, then Create account.</p>
      </div>
      <form action={signInWithPassword} className="flex flex-col gap-2">
        <input type="hidden" name="next" value={next} />
        <label className="flex flex-col gap-1 text-sm">
          Email
          <input name="email" type="email" required placeholder="you@example.com" className="input py-2" autoComplete="email" />
        </label>
        <label className="flex flex-col gap-1 text-sm">
          Password
          <input
            name="password"
            type="password"
            required
            minLength={6}
            placeholder={`${MIN_PASSWORD}+ characters for new accounts`}
            className="input py-2"
            autoComplete="current-password"
          />
        </label>
        <div className="flex gap-2">
          <button name="mode" value="signin" className="btn flex-1 py-2">
            Sign in
          </button>
          <button name="mode" value="signup" className="btn flex-1 py-2">
            Create account
          </button>
        </div>
      </form>
      {OAUTH_PROVIDERS.map((provider) => (
        <form key={provider} action={signInWithProvider}>
          <input type="hidden" name="provider" value={provider} />
          <input type="hidden" name="next" value={next} />
          <button className="w-full rounded-md bg-foreground px-3 py-2 text-background">Continue with {PROVIDER_LABELS[provider]}</button>
        </form>
      ))}
      {EMAIL_LINKS && (
        <div className="flex flex-col gap-2 text-sm">
          <details>
            <summary className="cursor-pointer text-muted">Email me a sign-in link instead</summary>
            <form action={signInWithEmail} className="mt-2 flex flex-col gap-2">
              <label className="flex flex-col gap-1">
                Email
                <input name="email" type="email" required placeholder="you@example.com" className="input py-2" />
              </label>
              <button className="btn py-2">Send link</button>
            </form>
          </details>
          <details>
            <summary className="cursor-pointer text-muted">Forgot password?</summary>
            <form action={sendPasswordReset} className="mt-2 flex flex-col gap-2">
              <label className="flex flex-col gap-1">
                Email
                <input name="email" type="email" required placeholder="you@example.com" className="input py-2" />
              </label>
              <button className="btn py-2">Email me a reset link</button>
            </form>
          </details>
        </div>
      )}
      {sent === "link" && <p className="text-sm text-muted">Check your email for the sign-in link.</p>}
      {sent === "reset" && <p className="text-sm text-muted">Check your email for a link to choose a new password.</p>}
      {sent === "confirm" && <p className="text-sm text-muted">Check your email to confirm your account, then sign in.</p>}
      {message && <p className={`text-sm ${error === "deleted" ? "text-muted" : "text-red-500"}`}>{message}</p>}
      <Link href="/privacy" className="text-xs text-muted hover:text-accent">
        Privacy
      </Link>
    </main>
  );
}
