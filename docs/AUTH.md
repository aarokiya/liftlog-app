# Sign-in

Accounts live in Supabase Auth. Every user table has a `user_id` and row-level security, so each account only ever sees its own rows; the anon key in the apps is public by design.

## Methods

- **Email + password** works everywhere. The public instance doesn't send email, so "Confirm email" is off there; new passwords need 8+ characters.
- **Magic links and password reset** need an email sender. Supabase's built-in email only reaches your own team, so add custom SMTP (Authentication → Emails) first, then set `NEXT_PUBLIC_EMAIL_LINKS=true` (web) and `LIFTLOG_EMAIL_LINKS = YES` (iOS).
- **Google / GitHub** buttons appear for providers listed in `NEXT_PUBLIC_OAUTH_PROVIDERS` (e.g. `google`). Enable the provider in Supabase (Authentication → Sign In / Providers) with your OAuth client first.

## Redirects

- Supabase → Authentication → URL Configuration: set the Site URL to your web address and allow `https://your-site/**` and `liftlog://auth-callback` (the iPhone app).
- Set `NEXT_PUBLIC_SITE_URL` so redirect links don't depend on request headers.
- `/auth/callback` handles OAuth and same-browser email links (PKCE). For links that work on any device, point the email templates at `/auth/confirm`, for example `{{ .SiteURL }}/auth/confirm?token_hash={{ .TokenHash }}&type=email` (magic link) and `&type=recovery` (password reset).
