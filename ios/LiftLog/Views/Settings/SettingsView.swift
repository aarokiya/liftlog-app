import LiftKit
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AuthService.self) private var auth
    @Environment(SyncService.self) private var sync
    @Environment(HealthService.self) private var health
    @Environment(Reminders.self) private var reminders
    @AppStorage(Prefs.unit) private var unitRaw = WeightUnit.lb.rawValue
    @AppStorage(Prefs.formula) private var formulaRaw = OneRepMaxFormula.epley.rawValue
    @AppStorage(Prefs.weeklyTarget) private var weeklyTarget = 3
    @AppStorage(Prefs.barWeight) private var barWeight = 45.0
    @AppStorage(Prefs.profileNeedsSync) private var profileNeedsSync = false
    @AppStorage(Prefs.campus) private var campus = ""
    @AppStorage(Prefs.reminders) private var remindersOn = false
    @State private var notificationsDenied = false
    @State private var confirmingDelete = false
    @State private var deleteError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    if !auth.isConfigured {
                        Text("Sync is off. Add your Supabase URL and key to ios/Config.xcconfig to sync with the web dashboard.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else if auth.isSignedIn {
                        LabeledContent("Signed in", value: auth.email ?? "—")
                        Button {
                            Task { await sync.run(context: context, auth: auth) }
                        } label: {
                            HStack {
                                Text("Sync now")
                                Spacer()
                                if sync.isSyncing { ProgressView() }
                            }
                        }
                        if let last = sync.lastSyncedAt {
                            LabeledContent("Last synced", value: last.formatted(.relative(presentation: .named)))
                        }
                        if let error = sync.lastError {
                            Text(error).font(.footnote).foregroundStyle(.red)
                        }
                        Button("Sign out", role: .destructive) { Task { await auth.signOut() } }
                        Button("Delete account", role: .destructive) { confirmingDelete = true }
                            .confirmationDialog("Delete your account?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                                Button("Delete account and synced data", role: .destructive) {
                                    Task {
                                        do {
                                            try await auth.deleteAccount()
                                            deleteError = nil
                                        } catch {
                                            deleteError = "Couldn't delete the account: \(error.localizedDescription)"
                                        }
                                    }
                                }
                            } message: {
                                Text("This deletes your account and everything synced to it, on the web too. It can't be undone. Workouts already on this phone stay here.")
                            }
                        if let deleteError {
                            Text(deleteError).font(.footnote).foregroundStyle(.red)
                        }
                    } else {
                        NavigationLink("Sign in to sync") { SignInView() }
                    }
                }

                Section {
                    Picker("Units", selection: $unitRaw.onSet(markDirty)) {
                        ForEach(WeightUnit.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) }
                    }
                    Picker("1RM formula", selection: $formulaRaw.onSet(markDirty)) {
                        ForEach(OneRepMaxFormula.allCases, id: \.rawValue) { Text($0.rawValue.capitalized).tag($0.rawValue) }
                    }
                    Stepper("Weekly goal: \(weeklyTarget) workouts", value: $weeklyTarget.onSet(markDirty), in: 1...14)
                    LabeledContent("Bar weight") {
                        TextField("45", value: $barWeight.onSet(markDirty), format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    Picker("Campus", selection: $campus.onSet(markDirty)) {
                        Text("None").tag("")
                        Text("Georgia Tech").tag("gatech")
                    }
                } header: {
                    Text("Preferences")
                } footer: {
                    Text("Georgia Tech adds dining-hall menus and CRC equipment swaps.")
                }

                Section {
                    if HealthService.isAvailable {
                        Toggle("Sync with Apple Health", isOn: Binding(
                            get: { health.isEnabled },
                            set: { on in
                                if on {
                                    Task {
                                        await health.enable()
                                        await health.sync(context: context)
                                    }
                                } else {
                                    health.isEnabled = false
                                }
                            }
                        ))
                        if let last = health.lastImportAt {
                            LabeledContent("Last read", value: last.formatted(.relative(presentation: .named)))
                        }
                        if let error = health.lastError {
                            Text(error).font(.footnote).foregroundStyle(.red)
                        }
                    } else {
                        Text("Apple Health isn't available on this device.").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Apple Health")
                } footer: {
                    Text("Saves finished workouts as strength training and reads weight, body fat, waist and height.")
                }

                Section {
                    Toggle("Daily reminders", isOn: Binding(get: { remindersOn }, set: setReminders))
                    if notificationsDenied {
                        Text("Notifications are off for LiftLog. Allow them in the iOS Settings app → Notifications → LiftLog.")
                            .font(.footnote).foregroundStyle(.red)
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("Check-ins at 10am, 1pm and 8pm, and at 10pm an alert for each food or water goal not hit yet. Alerts use what's logged in LiftLog and Apple Health as of the last time you opened the app.")
                }

                Section("Tools") {
                    NavigationLink("Plate calculator") { PlateCalculatorView() }
                    NavigationLink("Body & aesthetics") { BodyWeightView() }
                }
            }
            .navigationTitle("Settings")
            .task {
                if remindersOn || notificationsDenied { notificationsDenied = await reminders.isDenied }
            }
        }
    }

    private func markDirty() { profileNeedsSync = true }

    /// On asks for permission and schedules the reminders, or turns back off if notifications are denied; off removes them.
    private func setReminders(_ on: Bool) {
        remindersOn = on
        notificationsDenied = false
        guard on else { return reminders.removeAll() }
        Task {
            if await reminders.requestPermission() {
                reminders.refresh(context: context, health: health)
            } else {
                remindersOn = false
                notificationsDenied = true
            }
        }
    }
}

struct SignInView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var message: String?
    @State private var error: String?
    @State private var working = false

    var body: some View {
        Form {
            Section {
                TextField("you@example.com", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
                    .textContentType(.password)
            }
            Section {
                Button("Sign in") { run { try await auth.signIn(email: email, password: password); dismiss() } }
                Button("Create account") {
                    guard password.count >= AppConfig.minPassword else {
                        error = "Use at least \(AppConfig.minPassword) characters for your password."
                        return
                    }
                    run {
                        if try await auth.signUp(email: email, password: password) {
                            message = "Check your email to confirm, then sign in."
                        } else {
                            dismiss()
                        }
                    }
                }
            }
            .disabled(working || email.isEmpty || password.count < 6)
            Section {
                if AppConfig.emailLinks {
                    Button("Email me a sign-in link") {
                        run {
                            try await auth.sendMagicLink(to: email)
                            message = "Check your email on this phone and tap the link."
                        }
                    }
                    .disabled(working || email.isEmpty)
                }
            } footer: {
                Text("New here? Enter an email and a password (\(AppConfig.minPassword)+ characters), then Create account. Use the same account on the website.")
            }
            if let message {
                Text(message).font(.footnote)
            }
            if let error {
                Text(error).foregroundStyle(.red).font(.footnote)
            }
        }
        .navigationTitle("Sign in")
    }

    private func run(_ action: @escaping () async throws -> Void) {
        working = true
        error = nil
        Task {
            defer { working = false }
            do { try await action() } catch { self.error = error.localizedDescription }
        }
    }
}

struct PlateCalculatorView: View {
    @AppStorage(Prefs.unit) private var unitRaw = WeightUnit.lb.rawValue
    @AppStorage(Prefs.barWeight) private var barWeight = 45.0
    @State private var target: Double? = 135

    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .lb }
    private var available: [Double] { unit == .lb ? [45, 35, 25, 10, 5, 2.5] : [25, 20, 15, 10, 5, 2.5, 1.25] }

    var body: some View {
        Form {
            LabeledContent("Target (\(unit.rawValue))") {
                TextField("135", value: $target, format: .number)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
            LabeledContent("Bar", value: Format.weight(barWeight, unit))
            if let target {
                let result = PlateCalculator.plates(target: target, bar: barWeight, available: available)
                Section("Each side") {
                    if result.perSide.isEmpty {
                        Text("Just the bar")
                    } else {
                        Text(result.perSide.map(Format.number).joined(separator: " + ")).font(.title3.bold())
                    }
                    if result.remainder > 0 {
                        Text("\(Format.weight(result.remainder, unit)) can't be loaded with standard plates")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Plate calculator")
    }
}

struct BodyWeightView: View {
    @Environment(\.modelContext) private var context
    @Environment(HealthService.self) private var health
    @AppStorage(Prefs.unit) private var unitRaw = WeightUnit.lb.rawValue
    @AppStorage(Prefs.heightCm) private var heightCm: Double?
    @AppStorage(Prefs.profileNeedsSync) private var profileNeedsSync = false
    @AppStorage(Prefs.sex) private var sexRaw = ""
    @Query(filter: #Predicate<BodyMetric> { $0.deletedAt == nil }, sort: \BodyMetric.measuredAt, order: .reverse)
    private var entries: [BodyMetric]
    @State private var weight: Double?
    @State private var waist: Double?
    @State private var neck: Double?
    @State private var hips: Double?
    @State private var bodyFat: Double?

    /// Lengths are entered in inches for lb users and cm for kg users.
    private var inches: Bool { unitRaw == WeightUnit.lb.rawValue }
    private var lengthUnit: String { inches ? "in" : "cm" }
    private func toCm(_ value: Double?) -> Double? { value.map { ((inches ? $0 * 2.54 : $0) * 10).rounded() / 10 } }
    private func fromCm(_ cm: Double) -> String { (inches ? cm / 2.54 : cm).formatted(.number.precision(.fractionLength(0...1))) + " " + lengthUnit }

    private var latestWaist: Double? { entries.first { $0.waistCm != nil }?.waistCm }
    private var latestNeck: Double? { entries.first { $0.neckCm != nil }?.neckCm }
    private var latestHips: Double? { entries.first { $0.hipsCm != nil }?.hipsCm }
    private var latestBodyFat: Double? { entries.first { $0.bodyFatPct != nil }?.bodyFatPct }

    private var sex: Advanced.Sex? { Advanced.Sex(pref: sexRaw) }

    /// The tape formulas differ by sex, so there's no estimate until it's set.
    private var tapeBodyFat: Double? {
        guard let sex, let heightCm, let latestWaist else { return nil }
        return Aesthetics.bodyFatEstimate(sex: sex, heightCm: heightCm, waistCm: latestWaist, neckCm: latestNeck, hipsCm: latestHips)
    }

    /// Women's Navy formula also needs hips; without the measurements it falls back to RFM.
    private var tapeMethod: String { latestNeck != nil && (sex == .male || latestHips != nil) ? "Navy" : "RFM" }

    /// A logged body-fat % (your own estimate, a scan, or Health) beats the tape formulas.
    private var currentBodyFat: Double? { latestBodyFat ?? tapeBodyFat }

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("Weight", value: $weight, format: .number).keyboardType(.decimalPad)
                    Text(unitRaw).foregroundStyle(.secondary)
                }
                HStack {
                    TextField("Waist at lower belly", value: $waist, format: .number).keyboardType(.decimalPad)
                    Text(lengthUnit).foregroundStyle(.secondary)
                }
                HStack {
                    TextField("Hips (widest point)", value: $hips, format: .number).keyboardType(.decimalPad)
                    Text(lengthUnit).foregroundStyle(.secondary)
                }
                HStack {
                    TextField("Neck (optional)", value: $neck, format: .number).keyboardType(.decimalPad)
                    Text(lengthUnit).foregroundStyle(.secondary)
                }
                HStack {
                    TextField("Body fat (optional, your estimate)", value: $bodyFat, format: .number).keyboardType(.decimalPad)
                    Text("%").foregroundStyle(.secondary)
                }
                Button("Log") { log() }
                    .disabled(weight == nil && waist == nil && neck == nil && hips == nil && bodyFat == nil)
            } header: {
                Text("Today")
            }
            Section {
                Picker("Sex", selection: $sexRaw.onSet { profileNeedsSync = true }) {
                    Text("Not set").tag("")
                    Text("Male").tag("male")
                    Text("Female").tag("female")
                }
                HStack {
                    Text("Height")
                    Spacer()
                    TextField("Add", value: Binding(
                        get: { heightCm.map { inches ? ($0 / 2.54 * 10).rounded() / 10 : $0 } },
                        set: { heightCm = toCm($0); profileNeedsSync = true }
                    ), format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text(lengthUnit).foregroundStyle(.secondary)
                }
                if let heightCm, let latestWaist, let ratio = Aesthetics.waistToHeight(waistCm: latestWaist, heightCm: heightCm) {
                    LabeledContent("Waist-to-height", value: "\(ratio.formatted(.number.precision(.fractionLength(2)))) (\(Aesthetics.band(ratio).rawValue))")
                    if let latestBodyFat {
                        LabeledContent("Body fat (logged)", value: "\(latestBodyFat.formatted())%")
                    } else if let bf = tapeBodyFat {
                        LabeledContent("Body fat (\(tapeMethod) est.)", value: "\(bf.formatted())%")
                    }
                    if let latestHips, let whr = Aesthetics.waistToHip(waistCm: latestWaist, hipsCm: latestHips) {
                        LabeledContent("Waist-to-hip", value: whr.formatted(.number.precision(.fractionLength(2))))
                    }
                    if sex == .male {
                        LabeledContent("Shoulder target (1.618 × waist)", value: fromCm(Aesthetics.shoulderTarget(waistCm: latestWaist)))
                    }
                } else {
                    Text("Add height and waist to see waist-to-height and body fat.").font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("Aesthetics")
            } footer: {
                if sex == nil {
                    Text("Set your sex to see body-fat estimates, a plan and Wilks/DOTS; the formulas differ for men and women.")
                }
            }
            if let sex, let bf = currentBodyFat, let entry = entries.first(where: { $0.bodyWeight != nil }), let bw = entry.bodyWeight {
                let unit = WeightUnit(rawValue: unitRaw) ?? .lb
                // A logged body-fat % fixes the plan from the weight at that time; tape estimates follow the current weight.
                let plan = Aesthetics.bodyPlan(bodyWeight: entry.unit.convert(bw, to: unit), unit: unit, bodyFatPct: bf,
                                               startWeight: latestBodyFat == nil ? nil : entries.planStartWeight(in: unit), sex: sex)
                let goalPct = Aesthetics.defaultGoalPct(sex).formatted()
                Section {
                    LabeledContent("Phase", value: plan.phase.label)
                    LabeledContent("First checkpoint", value: Format.weight(plan.checkpoint, unit))
                    LabeledContent("Goal weight (\(goalPct)%)", value: Format.weight(plan.goalWeight, unit))
                    LabeledContent(plan.phase == .leanBulk ? "Gain per week" : "Lose per week",
                                   value: "\(Format.number(plan.weeklyLow))–\(Format.weight(plan.weeklyHigh, unit))")
                    if let weeks = plan.weeks { LabeledContent("Time to checkpoint", value: "~\(weeks) weeks") }
                    LabeledContent("Protein", value: "\(plan.proteinG) g/day")
                } header: {
                    Text("Plan")
                } footer: {
                    Text("Based on \(bf.formatted())% body fat. Reassess at the checkpoint using your waist and photos; the \(goalPct)% goal assumes your lean mass stays the same.")
                }
            }
            Section("History") {
                ForEach(entries) { entry in
                    LabeledContent(entry.measuredAt.formatted(date: .abbreviated, time: .omitted), value: summary(entry))
                }
                .onDelete { offsets in
                    for index in offsets { entries[index].softDelete() }
                }
            }
        }
        .navigationTitle("Body")
    }

    private func summary(_ entry: BodyMetric) -> String {
        var parts: [String] = []
        if let w = entry.bodyWeight { parts.append(Format.weight(w, entry.unit)) }
        if let w = entry.waistCm { parts.append("waist " + fromCm(w)) }
        if let h = entry.hipsCm { parts.append("hips " + fromCm(h)) }
        if let n = entry.neckCm { parts.append("neck " + fromCm(n)) }
        if let bf = entry.bodyFatPct { parts.append("\(bf.formatted())%") }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private func log() {
        let unit = WeightUnit(rawValue: unitRaw) ?? .lb
        let entry = BodyMetric(bodyWeight: weight, unit: unit)
        entry.waistCm = toCm(waist)
        entry.neckCm = toCm(neck)
        entry.hipsCm = toCm(hips)
        entry.bodyFatPct = bodyFat
        context.insert(entry)
        try? context.save()
        if let weight { Task { await health.saveBodyWeight(weight, unit: unit, at: entry.measuredAt) } }
        weight = nil
        waist = nil
        neck = nil
        hips = nil
        bodyFat = nil
    }
}
