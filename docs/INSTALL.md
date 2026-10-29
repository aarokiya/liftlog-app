# Installing on your iPhone without the $99 Apple Developer Program

A free Apple ID can sign apps for your own devices. The catch: free signatures expire after **7 days**, and each Apple ID can have 3 sideloaded apps active. Your workouts are stored in the app's local database, so re-installing the same app over an expired one keeps your data (and everything is also synced to Supabase when you're signed in).

Not available with a free Apple ID: Sign in with Apple, push notifications, iCloud, TestFlight. LiftLog signs in with an email and a password (magic links only if you set `LIFTLOG_EMAIL_LINKS = YES` and give your Supabase project an email server), and the rest timer uses local notifications, so none of these are needed.

You don't need an account: signed out, everything stays on the phone. To sync with the website, go to Settings → Sign in to sync → **Create account** (8+ character password). The same email and password work at https://liftlog-app-three.vercel.app.

## Option A: Xcode (simplest, needs your Mac every 7 days)

1. `brew install xcodegen && cd ios && cp Config.example.xcconfig Config.xcconfig`. The config already points at the public LiftLog backend; change `SUPABASE_URL`/`SUPABASE_ANON_KEY` to use your own. Set `LIFTLOG_BUNDLE_ID` in `Config.xcconfig` to something unique to you (e.g. `com.yourname.liftlog`), because a free Apple ID can't sign an app id another team already registered. Then `xcodegen generate && open LiftLog.xcodeproj`.
2. Xcode → Settings → Accounts → add your Apple ID. In the LiftLog target → *Signing & Capabilities*, pick **Your Name (Personal Team)**.
3. On the iPhone: Settings → Privacy & Security → **Developer Mode** → On (the phone restarts).
4. Plug in the phone, choose it as the run destination, press Run.
5. First launch only: Settings → General → VPN & Device Management → trust your Apple ID.
6. Every 7 days, plug in and press Run again.

## Option B: SideStore (refreshes itself, no Mac needed)

CI builds an unsigned `LiftLog.ipa` from every push to `main` and attaches it to the [ios-latest release](https://github.com/aarokiya/liftlog-app/releases/tag/ios-latest). Install SideStore once by following https://docs.sidestore.io, download `LiftLog.ipa` on the phone, then SideStore → My Apps → **+** and pick it. SideStore signs it with your Apple ID (giving it a bundle id of your own) and refreshes it before the 7 days run out.

To build the IPA yourself instead:

1. `brew install xcodegen && cd ios && cp Config.example.xcconfig Config.xcconfig`, and set `LIFTLOG_BUNDLE_ID` in it to something unique to you (e.g. `com.yourname.liftlog`).
2. `xcodegen generate && xcodebuild build -project LiftLog.xcodeproj -scheme LiftLog -configuration Release -destination 'generic/platform=iOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO`
3. `rm -rf Payload LiftLog.ipa && mkdir Payload && cp -R build/Build/Products/Release-iphoneos/LiftLog.app Payload/ && codesign --force --sign - --entitlements LiftLog/LiftLog.entitlements Payload/LiftLog.app && zip -qry LiftLog.ipa Payload`
4. Install SideStore once by following https://docs.sidestore.io, AirDrop or download `LiftLog.ipa` to the phone, then SideStore → My Apps → **+** and pick it. SideStore refreshes it before the 7 days run out.

## Apple Health

Turn on Settings → Apple Health in the app. Finished workouts are saved as *Traditional Strength Training* with an active-energy estimate; weight, body fat, waist circumference and height are read from Health. Body weight you log in LiftLog is also written to Health.

Daily calories, protein, carbs and fat that other apps save to Health (turn on MyFitnessPal → Settings → Sharing & Privacy → Apple Health) are added to the Food screen's totals for the day.
