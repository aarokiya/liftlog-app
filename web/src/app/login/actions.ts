"use server";

import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { EMAIL_LINKS, MIN_PASSWORD, OAUTH_PROVIDERS, authErrorCode, safeNext, type AuthMessage } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

/** The site's own address for auth redirects: NEXT_PUBLIC_SITE_URL when set, else the request's origin. */
async function siteUrl() {
  if (process.env.NEXT_PUBLIC_SITE_URL) return process.env.NEXT_PUBLIC_SITE_URL.replace(/\/$/, "");
  const h = await headers();
  return h.get("origin") ?? `https://${h.get("host")}`;
}

function fail(code: AuthMessage, next?: string): never {
  redirect(`/login?error=${code}${next && next !== "/" ? `&next=${encodeURIComponent(next)}` : ""}`);
}

export async function signInWithProvider(formData: FormData) {
  const provider = OAUTH_PROVIDERS.find((p) => p === formData.get("provider"));
  if (!provider) fail("provider");
  const next = safeNext(formData.get("next") as string | null);
  const supabase = await createClient();
  const { data, error } = await supabase.auth.signInWithOAuth({
    provider,
    options: { redirectTo: `${await siteUrl()}/auth/callback?next=${encodeURIComponent(next)}` },
  });
  if (error) fail(authErrorCode(error), next);
  redirect(data.url);
}

export async function signInWithPassword(formData: FormData) {
  const supabase = await createClient();
  const credentials = { email: String(formData.get("email")).trim(), password: String(formData.get("password")) };
  const next = safeNext(formData.get("next") as string | null);
  if (formData.get("mode") === "signup") {
    if (credentials.password.length < MIN_PASSWORD) fail("weak_password", next);
    const { data, error } = await supabase.auth.signUp({
      ...credentials,
      options: { emailRedirectTo: `${await siteUrl()}/auth/callback?next=/settings?welcome=1` },
    });
    if (error) fail(authErrorCode(error), next);
    if (!data.session) redirect("/login?sent=confirm");
    redirect("/settings?welcome=1");
  }
  const { error } = await supabase.auth.signInWithPassword(credentials);
  if (error) fail(authErrorCode(error), next);
  redirect(next);
}

export async function signInWithEmail(formData: FormData) {
  if (!EMAIL_LINKS) fail("email_links_off");
  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithOtp({
    email: String(formData.get("email")).trim(),
    options: { emailRedirectTo: `${await siteUrl()}/auth/callback` },
  });
  if (error) fail(authErrorCode(error));
  redirect("/login?sent=link");
}

export async function sendPasswordReset(formData: FormData) {
  if (!EMAIL_LINKS) fail("email_links_off");
  const supabase = await createClient();
  const { error } = await supabase.auth.resetPasswordForEmail(String(formData.get("email")).trim(), {
    redirectTo: `${await siteUrl()}/auth/callback?next=/auth/reset`,
  });
  if (error) fail(authErrorCode(error));
  redirect("/login?sent=reset");
}

export async function updatePassword(formData: FormData) {
  const password = String(formData.get("password"));
  if (password.length < MIN_PASSWORD) redirect("/auth/reset?error=weak_password");
  const supabase = await createClient();
  const { error } = await supabase.auth.updateUser({ password });
  if (error) redirect(`/auth/reset?error=${authErrorCode(error)}`);
  redirect("/");
}

/** Deletes the signed-in account and everything in it (RPC `delete_account`), after the user types DELETE. */
export async function deleteAccount(formData: FormData) {
  if (String(formData.get("confirm")).trim() !== "DELETE") redirect("/settings?delete=confirm");
  const supabase = await createClient();
  const { error } = await supabase.rpc("delete_account");
  if (error) redirect("/settings?delete=failed");
  await supabase.auth.signOut();
  redirect("/login?error=deleted");
}
