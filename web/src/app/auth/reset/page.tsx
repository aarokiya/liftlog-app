import { redirect } from "next/navigation";
import { MIN_PASSWORD, authMessage } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";
import { updatePassword } from "../../login/actions";

export default async function ResetPasswordPage({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  const { error } = await searchParams;
  // Reached from a reset email (which signs you in) or while signed in; without a session there's nothing to update.
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const message = authMessage(error);
  return (
    <main className="mx-auto flex min-h-screen max-w-sm flex-col justify-center gap-4 p-6">
      <h1 className="text-2xl font-semibold">Choose a new password</h1>
      <form action={updatePassword} className="flex flex-col gap-2">
        <label className="flex flex-col gap-1 text-sm">
          New password
          <input name="password" type="password" required minLength={MIN_PASSWORD} placeholder={`${MIN_PASSWORD}+ characters`} className="input py-2" autoComplete="new-password" />
        </label>
        <button className="btn py-2">Save password</button>
      </form>
      {message && <p className="text-sm text-red-500">{message}</p>}
    </main>
  );
}
