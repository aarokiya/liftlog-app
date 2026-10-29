import Foundation

enum AppConfig {
    /// Read from Info.plist, which XcodeGen fills from Config.xcconfig. Nil means sync is disabled.
    static var supabase: (url: URL, key: String)? {
        guard
            let urlString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
            !urlString.contains("your-project"),
            let url = URL(string: urlString), url.host != nil,
            let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
            !key.isEmpty, !key.hasPrefix("your-")
        else { return nil }
        return (url, key)
    }

    static let authRedirect = URL(string: "liftlog://auth-callback")!

    /// Magic-link sign-in needs an email sender configured in Supabase (LIFTLOG_EMAIL_LINKS in Config.xcconfig).
    static var emailLinks: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "LIFTLOG_EMAIL_LINKS") as? String)?.uppercased() == "YES"
    }

    static let minPassword = 8
}

enum Prefs {
    static let unit = "defaultUnit"
    static let formula = "e1rmFormula"
    static let weeklyTarget = "weeklyWorkoutTarget"
    static let barWeight = "barWeight"
    static let displayName = "displayName"
    static let profileNeedsSync = "profileNeedsSync"
    static let healthEnabled = "healthEnabled"
    static let healthNutritionAsked = "healthNutritionAsked"
    static let healthStepsAsked = "healthStepsAsked"
    static let heightCm = "heightCm"
    static let healthHeightSeenAt = "healthHeightSeenAt"
    /// Set once the signed-in account's profile has been pulled; until then local changes don't overwrite it.
    static let profilePulled = "profilePulled"
    static let activeProgram = "activeProgram"
    /// "gatech" turns on Georgia Tech dining halls and CRC swaps; empty = no campus.
    static let campus = "campus"
    /// "male" or "female" picks the body-fat formulas, plan thresholds and Wilks/DOTS; empty = not set, which hides them.
    static let sex = "sex"
    /// Daily check-ins and 10pm goal alerts as local notifications; off by default.
    static let reminders = "reminders"
}
