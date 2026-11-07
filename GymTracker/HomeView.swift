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
                            DayCell(date: day, list: byDay[c.startOfDay(for: day)] ?? [],
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

                CalendarCard(workouts: all, selected: $selectedDay)

                if let day = selectedDay {
                    let c = ruCalendar
                    let list = all.filter { c.isDate($0.startedAt, inSameDayAs: day) }
                    Text(fmtDate(day, "EEEE, d MMMM").capitalized).font(.system(size: 17, weight: .bold)).frame(maxWidth: .infinity, alignment: .leading)
                    if list.isEmpty { Text("В этот день тренировок нет.").foregroundStyle(Color.gMuted).frame(maxWidth: .infinity, alignment: .leading) }
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
                                    Text("Упражнений: \(t.items.count)").font(.system(size: 12)).foregroundStyle(Color.gRed)
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
