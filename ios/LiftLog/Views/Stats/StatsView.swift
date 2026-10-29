import Charts
import LiftKit
import SwiftData
import SwiftUI

struct StatsView: View {
    @AppStorage(Prefs.unit) private var unitRaw = WeightUnit.lb.rawValue
    @AppStorage(Prefs.formula) private var formulaRaw = OneRepMaxFormula.epley.rawValue
    @AppStorage(Prefs.weeklyTarget) private var weeklyTarget = 3
    @AppStorage(Prefs.sex) private var sexRaw = ""
    @Query(filter: Workout.finished) private var workouts: [Workout]
    @Query(filter: #Predicate<Exercise> { $0.deletedAt == nil }) private var exercises: [Exercise]
    @Query(filter: #Predicate<BodyMetric> { $0.deletedAt == nil && $0.bodyWeight != nil }, sort: \BodyMetric.measuredAt, order: .reverse)
    private var weights: [BodyMetric]
    @Query(filter: #Predicate<BodyMetric> { $0.deletedAt == nil && $0.bodyFatPct != nil }, sort: \BodyMetric.measuredAt, order: .reverse)
    private var bodyFats: [BodyMetric]
    @State private var growthWindow = 0

    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .lb }
    private var sex: Advanced.Sex? { Advanced.Sex(pref: sexRaw) }

    var body: some View {
        let data = TrainingData(workouts: workouts, unit: unit, formula: OneRepMaxFormula(rawValue: formulaRaw) ?? .epley)
        let streak = data.streak(target: weeklyTarget)
        let bw = weights.first.flatMap { m in m.bodyWeight.map { (value: $0, unit: m.unit) } }
        let b = data.balance(exercises: exercises, bodyWeight: bw, sex: sex)
        NavigationStack {
            if workouts.isEmpty {
                ContentUnavailableView("No stats yet", systemImage: "chart.xyaxis.line", description: Text("Finish a workout to see your stats."))
                    .navigationTitle("Stats")
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        GroupBox("This week") {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                StatCard(title: "Workouts", value: "\(data.thisWeekCount) / \(weeklyTarget)",
                                         detail: weekPaceText(data.thisWeekCount), goal: weekGoal(data.thisWeekCount))
                                StatCard(title: "Week streak", value: "\(streak.current)", detail: "Best \(streak.longest)",
                                         goal: streak.current > 0 ? .hit : nil)
                                weightTrendCard
                                StatCard(title: "Workload 7d:28d", value: b.workload.map { Format.number($0) } ?? "—", detail: "0.8–1.3 is steady",
                                         goal: b.workload.map { Goal.band($0, 0.8...1.3, slack: 0.2) })
                            }
                        }

                        GroupBox("Training balance") {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                StatCard(title: "Push : pull", value: b.ratios.pushPull.map { Format.number($0) } ?? "—", detail: "aim 0.7–1.0",
                                         goal: b.ratios.pushPull.map { Goal.band($0, 0.7...1.0, slack: 0.15) })
                                StatCard(title: "Quad : ham", value: b.ratios.quadHam.map { Format.number($0) } ?? "—", detail: "aim 1.0–1.5",
                                         goal: b.ratios.quadHam.map { Goal.band($0, 1.0...1.5, slack: 0.25) })
                            }
                            MuscleTargetsView(counts: data.muscleSets(days: 7, exercises: exercises))
                                .padding(.top, 8)
                            if !b.recency.isEmpty {
                                Text("Days since last trained").font(.caption).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                                ForEach(b.recency, id: \.muscle) { item in
                                    HStack {
                                        Text(Muscle.label(item.muscle))
                                        Spacer()
                                        Text("\(item.days)d").monospacedDigit()
                                            .foregroundStyle((item.days >= 7 ? Goal.missed : item.days >= 4 ? Goal.close : Goal.hit).color)
                                    }
                                }
                            }
                        }

                        GroupBox("Weekly volume (\(data.unit.rawValue))") {
                            Chart(data.weeklyVolume()) { point in
                                BarMark(x: .value("Week", point.week, unit: .weekOfYear), y: .value("Volume", point.volume))
                                    .foregroundStyle(.orange)
                            }
                            .frame(height: 180)
                        }

                        GroupBox {
                            Picker("Window", selection: $growthWindow) {
                                Text("All time").tag(0)
                                Text("90 days").tag(90)
                                Text("30 days").tag(30)
                            }
                            .pickerStyle(.segmented)
                            let rows = data.growth(exercises: exercises, days: growthWindow == 0 ? nil : growthWindow)
                            if rows.isEmpty {
                                Text("No lifts in this window.").foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                            }
                            ForEach(rows) { row in
                                NavigationLink {
                                    ExerciseStatsView(exercise: row.exercise, data: data)
                                } label: {
                                    GrowthRowView(row: row, unit: data.unit)
                                }
                                .buttonStyle(.plain)
                                Divider()
                            }
                        } label: {
                            Label("Exercise growth", systemImage: "chart.line.uptrend.xyaxis")
                        }

                        GroupBox("Strength") {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                StatCard(title: "Workouts", value: "\(workouts.count)", detail: "all time")
                                StatCard(title: "Lifetime volume", value: Format.volume(data.lifetimeVolume, data.unit))
                                StatCard(title: "Density", value: b.density.map { "\(Format.number($0)) \(data.unit.rawValue)/min" } ?? "—", detail: "last 10 workouts")
                                StatCard(title: "Big-3 e1RM", value: b.bigThreeTotal.map { Format.weight($0, data.unit) } ?? "—", detail: "squat + bench + deadlift")
                                StatCard(title: "Wilks / DOTS", value: b.wilks.flatMap { w in b.dots.map { "\(Format.number(w)) / \(Format.number($0))" } } ?? "—",
                                         detail: sex == nil ? "set sex in Body" : bw == nil ? "log body weight" : nil)
                            }
                        }
                    }
                    .padding()
                }
                .navigationTitle("Stats")
            }
        }
    }

    /// Days of the week so far, Monday first.
    private var daysIntoWeek: Int {
        (Calendar.current.component(.weekday, from: .now) + 5) % 7 + 1
    }

    /// Hit once the target is reached, close while on pace, missed when behind.
    private func weekGoal(_ count: Int) -> Goal {
        if count >= weeklyTarget { return .hit }
        let expected = Double(weeklyTarget) * Double(daysIntoWeek) / 7
        return Double(count) >= expected.rounded(.down) ? .close : .missed
    }

    private func weekPaceText(_ count: Int) -> String {
        count >= weeklyTarget ? "target hit" : "\(weeklyTarget - count) to go, \(7 - daysIntoWeek) days left"
    }

    /// Body-weight change per week over the last 4 weeks, against the plan's weekly range.
    @ViewBuilder private var weightTrendCard: some View {
        let cutoff = Date.now.addingTimeInterval(-28 * 86_400)
        let points = weights.filter { $0.measuredAt >= cutoff }.compactMap { m in
            m.bodyWeight.map { (days: m.measuredAt.timeIntervalSince(cutoff) / 86_400, value: m.unit.convert($0, to: unit)) }
        }
        let span = (points.map(\.days).max() ?? 0) - (points.map(\.days).min() ?? 0)
        if points.count >= 3, span >= 7, let slope = Self.slope(points) {
            let perWeek = (slope * 7 * 10).rounded() / 10
            let current = weights.first.flatMap { m in m.bodyWeight.map { m.unit.convert($0, to: unit) } }
            let plan = sex.flatMap { sex in bodyFats.first?.bodyFatPct.flatMap { bf in current.map { w in
                Aesthetics.bodyPlan(bodyWeight: w, unit: unit, bodyFatPct: bf, sex: sex)
            } } }
            let goal: Goal? = plan.map { plan in
                let range = plan.phase == .leanBulk ? plan.weeklyLow...plan.weeklyHigh : -plan.weeklyHigh...(-plan.weeklyLow)
                return Goal.band(perWeek, range, slack: plan.weeklyLow / 2)
            }
            StatCard(title: "Body weight", value: "\(perWeek > 0 ? "+" : "")\(Format.number(perWeek)) \(unit.rawValue)/wk",
                     detail: plan.map { p in p.phase == .leanBulk
                         ? "plan +\(Format.number(p.weeklyLow))–\(Format.number(p.weeklyHigh))"
                         : "plan −\(Format.number(p.weeklyLow))–\(Format.number(p.weeklyHigh))" } ?? "last 4 weeks",
                     goal: goal)
        } else {
            StatCard(title: "Body weight", value: "—", detail: "weigh in a few times a week")
        }
    }

    /// Least-squares slope of value over days.
    private static func slope(_ points: [(days: Double, value: Double)]) -> Double? {
        let n = Double(points.count)
        let mx = points.map(\.days).reduce(0, +) / n
        let my = points.map(\.value).reduce(0, +) / n
        let sxx = points.reduce(0) { $0 + ($1.days - mx) * ($1.days - mx) }
        guard sxx > 0 else { return nil }
        return points.reduce(0) { $0 + ($1.days - mx) * ($1.value - my) } / sxx
    }
}

/// Hard sets per muscle in the last 7 days against the weekly V-taper targets (★ = priority).
struct MuscleTargetsView: View {
    let counts: [MuscleCount]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sets per muscle · last 7 days vs weekly target").font(.caption).foregroundStyle(.secondary)
            ForEach(Aesthetics.targets, id: \.muscle) { target in
                let sets = counts.first { $0.muscle == target.muscle }?.sets ?? 0
                let goal = Goal.band(sets, Double(target.min)...Double(target.max), slack: 2)
                VStack(spacing: 4) {
                    HStack {
                        Text(Muscle.label(target.muscle) + (target.priority ? " ★" : ""))
                        Spacer()
                        Text("\(Format.number(sets)) / \(target.min)–\(target.max)").monospacedDigit().foregroundStyle(goal.color)
                    }
                    .font(.subheadline)
                    ProgressView(value: min(sets, Double(target.max)), total: Double(target.max)).tint(goal.color)
                }
            }
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    var detail: String?
    var goal: Goal?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold()).minimumScaleFactor(0.6).lineLimit(1).foregroundStyle(goal?.color ?? .primary)
            if let detail { Text(detail).font(.caption2).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(goal.map { $0.color.opacity(0.12) } ?? Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct GrowthRowView: View {
    let row: ExerciseGrowth
    let unit: WeightUnit

    var body: some View {
        let g = row.growth
        let color: Color = g.sessions < 2 || g.change == 0 ? .primary : g.change > 0 ? .green : .red
        let values = row.points.compactMap(\.e1rm)
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.exercise.name).lineLimit(2)
                Text("\(Format.number(g.start)) → \(Format.weight(g.recent, unit))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Chart(Array(values.enumerated()), id: \.offset) { item in
                LineMark(x: .value("Session", item.offset), y: .value("e1RM", item.element))
                    .foregroundStyle(g.change >= 0 ? Color.green : Color.red)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(width: 60, height: 28)
            VStack(alignment: .trailing, spacing: 2) {
                Text(g.sessions > 1 ? "\((g.changePct ?? 0) > 0 ? "+" : "")\(Format.number(g.changePct ?? 0))%" : "—")
                    .bold().monospacedDigit().foregroundStyle(color)
                if g.prs > 0 {
                    Text("\(g.prs) PR\(g.prs == 1 ? "" : "s")").font(.caption2).foregroundStyle(.orange)
                }
            }
            .frame(width: 64, alignment: .trailing)
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct PRItem: Identifiable {
    let date: Date
    let value: Double
    let delta: Double?
    var id: Date { date }
}

struct ExerciseStatsView: View {
    enum Metric: String, CaseIterable, Identifiable {
        case e1rm = "Est. 1RM", top = "Top set", volume = "Volume"
        var id: String { rawValue }
    }

    let exercise: Exercise
    let data: TrainingData
    @State private var metric = Metric.e1rm

    private func value(_ s: SessionPoint) -> Double? {
        switch metric {
        case .e1rm: return s.e1rm
        case .top: return s.top
        case .volume: return s.volume
        }
    }

    private static func timeline(_ series: [E1RMPoint]) -> [PRItem] {
        var best: Double?
        var items: [PRItem] = []
        for p in series where best.map({ p.value > $0 }) ?? true {
            items.append(PRItem(date: p.date, value: p.value, delta: best.map { p.value - $0 }))
            best = p.value
        }
        return items.reversed()
    }

    var body: some View {
        let series = data.e1rmSeries(for: exercise)
        let sessions = data.sessions(for: exercise)
        let points = sessions.compactMap { s in value(s).map { E1RMPoint(date: s.date, value: $0) } }
        let fit = Trend.linearRegression(points.map { (x: $0.date.timeIntervalSince1970 / 86_400, y: $0.value) })
        let g = Advanced.growth(series.map { (day: Double(LocalDate(date: $0.date).dayNumber), value: $0.value) })
        let sets = data.sets(for: exercise)
        let prs = PersonalRecords.repMaxes(sets, unit: data.unit).sorted { $0.key < $1.key }
        let stall = Advanced.plateau(series.suffix(6).map { (day: Double(LocalDate(date: $0.date).dayNumber), value: $0.value) })
        let prTimeline = Self.timeline(series)

        ScrollView {
            VStack(spacing: 16) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    StatCard(title: "Best e1RM", value: g.map { Format.weight($0.best, data.unit) } ?? "—",
                             detail: g.map { "\($0.prs) PR\($0.prs == 1 ? "" : "s") since first session" })
                    StatCard(title: "Growth",
                             value: g.flatMap { $0.sessions > 1 ? "\($0.change >= 0 ? "+" : "")\(Format.weight($0.change, data.unit))" : nil } ?? "—",
                             detail: g.flatMap { g in g.changePct.map { "\($0 >= 0 ? "+" : "")\(Format.number($0))% in \(Int(g.spanDays)) days" } })
                    StatCard(title: "Trend", value: g?.weeklyRate.map { "\($0 >= 0 ? "+" : "")\(Format.number($0)) / wk" } ?? "—",
                             detail: stall.map { "\($0.plateaued ? "Plateau" : "Last 6"): \(Format.number($0.weeklyChange * 100))%/wk" })
                    StatCard(title: "Sessions", value: "\(sessions.count)", detail: Format.volume(Volume.load(sets, unit: data.unit), data.unit))
                }

                GroupBox {
                    Picker("Metric", selection: $metric) {
                        ForEach(Metric.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Chart {
                        ForEach(points) { point in
                            LineMark(x: .value("Date", point.date), y: .value(metric.rawValue, point.value), series: .value("Series", "Value"))
                                .foregroundStyle(.orange)
                            PointMark(x: .value("Date", point.date), y: .value(metric.rawValue, point.value))
                                .foregroundStyle(.orange)
                        }
                        if let fit, let first = points.first, let last = points.last, points.count > 1 {
                            ForEach([first.date, last.date], id: \.self) { date in
                                LineMark(
                                    x: .value("Date", date),
                                    y: .value(metric.rawValue, fit.intercept + fit.slope * date.timeIntervalSince1970 / 86_400),
                                    series: .value("Series", "Trend")
                                )
                                .foregroundStyle(.gray)
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            }
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 220)
                    .padding(.top, 8)
                }

                GroupBox("PR timeline") {
                    if prTimeline.isEmpty {
                        Text("No estimated-max sessions yet.").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(prTimeline.prefix(8)) { item in
                        HStack {
                            Text(item.date, format: .dateTime.month(.abbreviated).day().year()).foregroundStyle(.secondary)
                            Spacer()
                            Text(Format.weight(item.value, data.unit)).monospacedDigit().bold()
                            Text(item.delta.map { "+\(Format.number($0))" } ?? "first")
                                .font(.caption).foregroundStyle(.green).frame(width: 48, alignment: .trailing)
                        }
                        .padding(.vertical, 2)
                    }
                }

                GroupBox("Rep-range records") {
                    ForEach(prs, id: \.key) { reps, weight in
                        HStack {
                            Text("\(reps) rep\(reps == 1 ? "" : "s")")
                            Spacer()
                            Text(Format.weight(weight, data.unit)).monospacedDigit().bold()
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
