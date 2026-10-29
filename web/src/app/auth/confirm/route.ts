import type { EmailOtpType } from "@supabase/supabase-js";
import { NextResponse, type NextRequest } from "next/server";
import { safeNext } from "@/lib/auth";
import { createClient } from "@/lib/supabase/server";

/**
 * Email links that carry a token hash work in any browser or device, unlike PKCE codes. Point the Supabase email
 * templates here, e.g. {{ .SiteURL }}/auth/confirm?token_hash={{ .TokenHash }}&type=email (see docs/AUTH.md).
 */
export async function GET(request: NextRequest) {
  const { searchParams, origin } = new URL(request.url);
  const tokenHash = searchParams.get("token_hash");
  const type = searchParams.get("type") as EmailOtpType | null;
  if (tokenHash && type) {
    const supabase = await createClient();
    const { error } = await supabase.auth.verifyOtp({ token_hash: tokenHash, type });
    if (!error) return NextResponse.redirect(`${origin}${safeNext(type === "recovery" ? "/auth/reset" : searchParams.get("next"))}`);
  }
  return NextResponse.redirect(`${origin}/login?error=link`);
}
