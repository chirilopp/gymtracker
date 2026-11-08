import SwiftUI

private var ruCalendar: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.firstWeekday = 2
    c.locale = ruLocale
    return c
}

/// Календарь: в дни тренировок показываются процент выполнения и название.
struct CalendarCard: View {
    @Environment(Store.self) private var store
    let workouts: [Workout]
    @Binding var selected: Date?
    @State private var month = Date()

    private var monthStart: Date {
        let c = ruCalendar
        return c.date(from: c.dateComponents([.year, .month], from: month)) ?? month
    }

    private var cells: [Date?] {
        let c = ruCalendar
        let start = monthStart
        let days = c.range(of: .day, in: .month, for: start)?.count ?? 30
        let weekday = c.component(.weekday, from: start)
        let offset = (weekday - c.firstWeekday + 7) % 7
        var out: [Date?] = Array(repeating: nil, count: offset)
        for d in 0..<days { out.append(c.date(byAdding: .day, value: d, to: start)) }
        while out.count % 7 != 0 { out.append(nil) }
        return out
    }

    var body: some View {
        let c = ruCalendar
        let byDay = Dictionary(grouping: workouts) { c.startOfDay(for: $0.startedAt) }
        Card {
            VStack(spacing: 6) {
                HStack {
                    Button { month = c.date(byAdding: .month, value: -1, to: month) ?? month } label: { Image(systemName: "chevron.left").frame(width: 44, height: 36) }
                    Spacer()
                    Text(fmtDate(monthStart, "LLLL yyyy").capitalized).font(.system(size: 18, weight: .bold))
                    Spacer()
                    Button { month = c.date(byAdding: .month, value: 1, to: month) ?? month } label: { Image(systemName: "chevron.right").frame(width: 44, height: 36) }
                }
                HStack(spacing: 0) {
                    ForEach(["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"], id: \.self) {
                        Text($0).font(.system(size: 12)).foregroundStyle(Color.gMuted).frame(maxWidth: .infinity)
                    }
                }
                let grid = cells
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                    ForEach(0..<grid.count, id: \.self) { i in
                        if let day = grid[i] {
                            let dayList = byDay[c.startOfDay(for: day)] ?? []
                            let todayStart = c.startOfDay(for: Date())
                            let plannedHere = (dayList.isEmpty && c.startOfDay(for: day) >= todayStart)
                                ? store.db.templates.filter { $0.days.contains(weekdayMonFirst(day)) } : []
                            DayCell(date: day, list: dayList, planned: plannedHere,
                                    isToday: c.isDateInToday(day),
                                    isSelected: selected.map { c.isDate($0, inSameDayAs: day) } ?? false) { selected = day }
                        } else {
                            Color.clear.frame(height: 80)
                        }
                    }
                }
            }
        }
    }
}

private struct DayCell: View {
    @Environment(Store.self) private var store
    let date: Date
    let list: [Workout]
    let planned: [Template]
    let isToday: Bool
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Text("\(ruCalendar.component(.day, from: date))")
                    .font(.system(size: 14, weight: isToday ? .bold : .regular))
                    .frame(width: 26, height: 26)
                    .background(isToday ? Color.gRed : Color.clear, in: Circle())
                if let w = list.first {
                    let pct = w.completion
                    Text(w.isPlanned ? "план" : "\(pct)%")
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(w.isPlanned ? Color.gCard2 : (pct >= 90 ? Color.gGreen : (pct >= 50 ? Color(red: 0.72, green: 0.47, blue: 0.12) : Color.gRedDark)), in: Capsule())
                    Text(store.label(w) + (list.count > 1 ? " +\(list.count - 1)" : ""))
                        .font(.system(size: 9)).foregroundStyle(Color.gMuted)
                        .multilineTextAlignment(.center).lineLimit(2)
                } else if let t = planned.first {
                    Text("план")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(Color.gRed)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .overlay(Capsule().stroke(Color.gRed, lineWidth: 1))
                    Text(t.name + (planned.count > 1 ? " +\(planned.count - 1)" : ""))
                        .font(.system(size: 9)).foregroundStyle(Color.gMuted)
                        .multilineTextAlignment(.center).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 80)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSelected ? Color.gRed : Color.clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct PlannedEntry: Identifiable {
    let id = UUID()
    let date: Date
    let template: Template
    let workout: Workout?
}

struct HomeView: View {
    @Environment(Store.self) private var store
    @State private var selectedDay: Date? = Date()
    @State private var openWorkout: UUID?

    var body: some View {
        let all = store.finished + (store.active.map { [$0] } ?? [])
        ScrollView {
            VStack(spacing: 12) {
                HStack(spacing: 0) {
                    Text("Gym").font(.system(size: 30, weight: .black))
                    Text("Tracker").font(.system(size: 30, weight: .black)).foregroundStyle(Color.gRed)
                    Spacer()
                }

                if let a = store.active { activeBanner(a) }

                SectionTitle("Следующие тренировки")
                let plan = weekPlan(all: all)
                if plan.isEmpty {
                    Text("Назначьте дни недели шаблонам: Ещё → Шаблоны → выберите шаблон → «Дни тренировок». Тренировки на этой неделе появятся здесь.")
                        .font(.system(size: 13)).foregroundStyle(Color.gMuted).frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(plan) { p in
                    Button {
                        if let w = p.workout { openWorkout = w.id } else { openWorkout = store.startWorkout(templateId: p.template.id) }
                    } label: {
                        Card {
                            HStack(spacing: 14) {
                                ProgressRing(percent: p.workout?.completion ?? 0, diameter: 56)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(fmtDate(p.date, "EEE, d MMMM").capitalized).font(.system(size: 14)).foregroundStyle(Color.gMuted)
                                    Text(p.template.name).font(.system(size: 20, weight: .bold))
                                }
                                Spacer()
                                if ruCalendar.isDateInToday(p.date) { Circle().fill(Color.gRed).frame(width: 12, height: 12) }
                            }
                        }
                    }.buttonStyle(.plain)
                }

                CalendarCard(workouts: all, selected: $selectedDay)

                if let day = selectedDay {
                    let c = ruCalendar
                    let list = all.filter { c.isDate($0.startedAt, inSameDayAs: day) }
                    Text(fmtDate(day, "EEEE, d MMMM").capitalized).font(.system(size: 17, weight: .bold)).frame(maxWidth: .infinity, alignment: .leading)
                    let todayStart = c.startOfDay(for: Date())
                    let dayStart = c.startOfDay(for: day)
                    let plannedOnDay = store.db.templates.filter { t in
                        dayStart >= todayStart && t.days.contains(weekdayMonFirst(day)) && !list.contains { w in w.title == t.name }
                    }
                    if list.isEmpty && plannedOnDay.isEmpty { Text("В этот день тренировок нет.").foregroundStyle(Color.gMuted).frame(maxWidth: .infinity, alignment: .leading) }
                    ForEach(plannedOnDay) { t in
                        Button { if dayStart == todayStart { openWorkout = store.startWorkout(templateId: t.id) } } label: {
                            Card {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(t.name).font(.system(size: 18, weight: .bold))
                                        Text(dayStart == todayStart ? "Запланирована на сегодня — нажмите, чтобы начать" : "Запланирована")
                                            .font(.system(size: 13)).foregroundStyle(Color.gMuted)
                                    }
                                    Spacer()
                                    if dayStart == todayStart { Image(systemName: "chevron.right").foregroundStyle(Color.gRed) }
                                }
                            }
                        }.buttonStyle(.plain)
                    }
                    ForEach(list) { w in
                        NavigationLink(value: Route.workout(w.id)) {
                            Card {
                                HStack(spacing: 12) {
                                    ProgressRing(percent: w.completion, diameter: 56)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(store.label(w)).font(.system(size: 18, weight: .bold))
                                        Text((w.finished ? "~ \(Int(w.duration / 60)) мин · " : "") + "подходов \(w.doneSets) · объём \(fmtVol(w.volume)) кг")
                                            .font(.system(size: 13)).foregroundStyle(Color.gMuted)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(Color.gRed)
                                }
                            }
                        }.buttonStyle(.plain)
                    }
                }

                SectionTitle("Выбрать тренировку").padding(.top, 6)
                if store.db.templates.isEmpty {
                    Text("Шаблонов пока нет. Создайте тренировку (например «Грудь/бицепс»), добавьте упражнения, подходы и повторы — она появится здесь.")
                        .font(.system(size: 13)).foregroundStyle(Color.gMuted).frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(store.db.templates) { t in
                    Button { openWorkout = store.startWorkout(templateId: t.id) } label: {
                        Card {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(t.name).font(.system(size: 18, weight: .bold))
                                    Text("Упражнений: \(t.items.count) · \(daysLabel(t.days))").font(.system(size: 12)).foregroundStyle(Color.gRed)
                                    Text(t.items.compactMap { store.exercise($0.exerciseId)?.name }.joined(separator: " · "))
                                        .font(.system(size: 12)).foregroundStyle(Color.gMuted).lineLimit(2).multilineTextAlignment(.leading)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(Color.gRed)
                            }
                        }
                    }.buttonStyle(.plain)
                }
                HStack(spacing: 8) {
                    BigButton("Пустая тренировка", primary: false) { openWorkout = store.startWorkout(templateId: nil) }
                    NavigationLink(value: Route.templates) {
                        Text("Шаблоны").font(.system(size: 17, weight: .bold)).foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity, minHeight: 54).background(Color.gCard2, in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain)
                }

                NavigationLink(value: Route.timer) {
                    Card {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Таймер отдыха").font(.system(size: 18, weight: .bold))
                                TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                                    Text(restSummary(ctx.date)).foregroundStyle(Color.gMuted)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Color.gRed)
                        }
                    }
                }.buttonStyle(.plain)
            }
            .padding(16)
        }
        .background(Color.gBg)
        .navigationBarHidden(true)
        .navigationDestination(item: $openWorkout) { WorkoutView(workoutId: $0) }
    }

    /// Тренировки текущей недели (Пн–Вс) по назначенным дням шаблонов.
    private func weekPlan(all: [Workout]) -> [PlannedEntry] {
        let c = ruCalendar
        let today = c.startOfDay(for: Date())
        guard let monday = c.date(byAdding: .day, value: -(weekdayMonFirst(today) - 1), to: today) else { return [] }
        var out: [PlannedEntry] = []
        for d in 0..<7 {
            guard let date = c.date(byAdding: .day, value: d, to: monday) else { continue }
            for t in store.db.templates where t.days.contains(weekdayMonFirst(date)) {
                let w = all.first { c.isDate($0.startedAt, inSameDayAs: date) && $0.title == t.name }
                out.append(PlannedEntry(date: date, template: t, workout: w))
            }
        }
        return out
    }

    private func restSummary(_ now: Date) -> String {
        switch store.rest.status {
        case .running: return "Осталось " + fmtDur(store.rest.remaining(at: now) + 0.999)
        case .paused: return "Пауза · " + fmtDur(store.rest.pausedRemaining + 0.999)
        case .finished: return "Отдых окончен"
        case .idle: return "Нажмите, чтобы запустить"
        }
    }

    @ViewBuilder
    private func activeBanner(_ a: Workout) -> some View {
        NavigationLink(value: Route.workout(a.id)) {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text(a.isPlanned ? "ВЫБРАНА · ЕЩЁ НЕ НАЧАТА" : (a.resumedAt == nil ? "НА ПАУЗЕ" : "ТРЕНИРОВКА ИДЁТ"))
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(Color.gRed)
                    HStack(spacing: 14) {
                        ProgressRing(percent: a.completion, diameter: 64)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.label(a)).font(.system(size: 20, weight: .bold))
                            Text("подходов \(a.doneSets)/\(a.totalSets)").font(.system(size: 13)).foregroundStyle(Color.gMuted)
                        }
                        Spacer()
                        if !a.isPlanned {
                            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                                Text(fmtDur(a.elapsed(at: ctx.date))).font(.system(size: 26, weight: .black)).monospacedDigit()
                            }
                        }
                    }
                    Text(a.isPlanned ? "Открыть тренировку" : "Продолжить тренировку")
                        .font(.system(size: 17, weight: .bold)).foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity, minHeight: 50).background(Color.gRed, in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }.buttonStyle(.plain)
    }
}
