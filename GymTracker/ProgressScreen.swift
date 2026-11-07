import SwiftUI
import Charts

private enum Period: String, CaseIterable, Identifiable {
    case d30 = "30 дн.", d90 = "90 дн.", y1 = "Год", all = "Всё время"
    var id: String { rawValue }
    var days: Int? { switch self { case .d30: return 30; case .d90: return 90; case .y1: return 365; case .all: return nil } }
}

/// Графики строятся только из реально сохранённых данных.
struct ProgressScreen: View {
    @Environment(Store.self) private var store
    let initial: UUID?
    @State private var selectedId: UUID?
    @State private var period: Period = .all

    private func usedExercises() -> [(UUID, String)] {
        var names: [UUID: String] = [:]
        for w in store.finished {
            for e in w.exercises where e.sets.contains(where: { $0.done }) {
                names[e.exerciseId] = store.exercise(e.exerciseId)?.name ?? "Упражнение"
            }
        }
        return names.map { ($0.key, $0.value) }.sorted { $0.1 < $1.1 }
    }

    var body: some View {
        let used = usedExercises()
        let eff = used.contains { $0.0 == (selectedId ?? initial) } ? (selectedId ?? initial) : used.first?.0
        let effName = used.first { $0.0 == eff }?.1 ?? ""
        let cutoff: Date? = period.days.flatMap { Calendar.current.date(byAdding: .day, value: -$0, to: Date()) }
        let points = eff.map { store.exerciseHistory($0).filter { p in cutoff.map { p.date >= $0 } ?? true } } ?? []
        let fin = store.finished
        let now = Date()
        let week = fin.filter { $0.startedAt >= now.addingTimeInterval(-7 * 86400) }.count
        let month = fin.filter { $0.startedAt >= now.addingTimeInterval(-30 * 86400) }.count
        let avg = fin.isEmpty ? 0 : fin.reduce(0) { $0 + $1.duration } / Double(fin.count)

        ScrollView {
            VStack(spacing: 12) {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Общая статистика").font(.system(size: 17, weight: .bold))
                        HStack {
                            Stat(label: "за 7 дней", value: String(week)); Stat(label: "за 30 дней", value: String(month)); Stat(label: "всего", value: String(fin.count))
                        }
                        HStack {
                            Stat(label: "средняя длит.", value: "\(Int(avg / 60)) мин")
                            Stat(label: "подходов", value: String(fin.reduce(0) { $0 + $1.workingSets }))
                            Stat(label: "объём, кг", value: fmtVol(fin.reduce(0) { $0 + $1.volume }))
                        }
                    }
                }

                if used.isEmpty {
                    Text("Графики появятся после первой завершённой тренировки с выполненными подходами.").foregroundStyle(Color.gMuted).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Menu {
                        ForEach(used, id: \.0) { u in Button(u.1) { selectedId = u.0 } }
                    } label: {
                        Text("Упражнение: \(effName)").font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity, minHeight: 50).background(Color.gCard2, in: RoundedRectangle(cornerRadius: 14))
                    }
                    HStack(spacing: 6) {
                        ForEach(Period.allCases) { p in Chip(title: p.rawValue, selected: period == p) { period = p } }
                        Spacer(minLength: 0)
                    }

                    if points.isEmpty {
                        Text("За выбранный период нет данных по этому упражнению.").foregroundStyle(Color.gMuted).frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        let last = points[points.count - 1]
                        let best = points.max { ($0.bestWeight, $0.bestReps) < ($1.bestWeight, $1.bestReps) }!
                        let bestE = points.map { $0.e1rm }.max() ?? 0
                        Card {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Рекорды за период").font(.system(size: 17, weight: .bold))
                                Text("Лучший поднятый вес: \(fmtW(best.bestWeight)) кг × \(best.bestReps) (\(fmtShort(best.date)))").font(.system(size: 16, weight: .semibold))
                                if bestE > 0 {
                                    Text("Оценка 1ПМ: ≈ \(fmtW((bestE * 10).rounded() / 10)) кг").font(.system(size: 15)).foregroundStyle(Color.gOrange)
                                    Text("Это расчёт по формуле Эпли, а не фактически поднятый вес.").font(.system(size: 12)).foregroundStyle(Color.gMuted)
                                }
                                if points.count > 1 {
                                    let d = last.bestWeight - points[points.count - 2].bestWeight
                                    Text("Последняя тренировка: \(fmtW(last.bestWeight)) кг (\(d >= 0 ? "+" : "−")\(fmtW(abs(d))) к предыдущей)").font(.system(size: 14)).foregroundStyle(Color.gMuted)
                                } else {
                                    Text("Последняя тренировка: \(fmtW(last.bestWeight)) кг").font(.system(size: 14)).foregroundStyle(Color.gMuted)
                                }
                            }
                        }
                        chartCard("Рабочий вес (лучший подход), кг") {
                            Chart(points) { p in
                                LineMark(x: .value("Дата", p.date), y: .value("кг", p.bestWeight)).foregroundStyle(Color.gRed)
                                PointMark(x: .value("Дата", p.date), y: .value("кг", p.bestWeight)).foregroundStyle(Color.gRed)
                            }
                        }
                        chartCard("Повторения (всего за тренировку)") {
                            Chart(points) { p in
                                LineMark(x: .value("Дата", p.date), y: .value("повт.", p.totalReps)).foregroundStyle(Color.gRed)
                                PointMark(x: .value("Дата", p.date), y: .value("повт.", p.totalReps)).foregroundStyle(Color.gRed)
                            }
                        }
                        chartCard("Тренировочный объём, кг") {
                            Chart(points) { p in
                                BarMark(x: .value("Дата", p.date, unit: .day), y: .value("кг", p.volume)).foregroundStyle(Color.gRed)
                            }
                        }
                    }

                    SectionTitle("Личные рекорды по упражнениям").padding(.top, 6)
                    let bests = store.bestRecords()
                    if bests.isEmpty { Text("Рекордов с весом пока нет.").foregroundStyle(Color.gMuted).frame(maxWidth: .infinity, alignment: .leading) }
                    ForEach(bests) { b in
                        Card {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(b.name).font(.system(size: 16, weight: .semibold))
                                Text("\(fmtW(b.weight)) кг × \(b.reps) · \(fmtShort(b.date))").font(.system(size: 13)).foregroundStyle(Color.gMuted)
                            }
                        }
                    }
                }
            }.padding(16)
        }
        .background(Color.gBg)
        .navigationTitle("Прогресс")
    }

    @ViewBuilder
    private func chartCard<C: View>(_ title: String, @ViewBuilder _ chart: () -> C) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.system(size: 16, weight: .bold))
                chart().frame(height: 180)
            }
        }
    }
}
