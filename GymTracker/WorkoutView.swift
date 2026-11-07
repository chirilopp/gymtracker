import SwiftUI

/// Обзор тренировки: процент, список упражнений с планом, кнопки начала/завершения.
struct WorkoutView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let workoutId: UUID

    @State private var goRun = false
    @State private var runIndex = 0
    @State private var copied: UUID?
    @State private var showPicker = false
    @State private var showFinish = false
    @State private var showDelete = false
    @State private var showReset = false
    @State private var showDuration = false
    @State private var showTemplate = false
    @State private var minutesText = ""
    @State private var templateName = ""
    @State private var removing: UUID?
    @State private var noteText = ""

    var body: some View {
        Group {
            if let w = store.workout(workoutId) { content(w) }
            else { Text("Загрузка…").foregroundStyle(Color.gMuted) }
        }
        .background(Color.gBg)
        .toolbar(.hidden, for: .tabBar)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $goRun) { RunView(workoutId: workoutId, startIndex: runIndex) }
        .navigationDestination(item: $copied) { WorkoutView(workoutId: $0) }
        .sheet(isPresented: $showPicker) {
            ExercisePickerSheet { ids in store.addExercises(to: workoutId, ids: ids) }
        }
        .keyboardDone()
    }

    @ViewBuilder
    private func content(_ w: Workout) -> some View {
        let planned = w.isPlanned
        let running = !w.finished && !planned && w.resumedAt != nil
        let prev = store.finished.first { $0.id != w.id && $0.startedAt < w.startedAt }
        let prs = store.prs()[w.id] ?? []
        let number = w.finished ? store.finished.filter { $0.startedAt <= w.startedAt }.count : store.finished.count + 1

        ScrollView {
            VStack(spacing: 10) {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 14) {
                            ProgressRing(percent: w.completion, diameter: 72)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(number) тренировка").font(.system(size: 14)).foregroundStyle(Color.gMuted)
                                Text(store.label(w)).font(.system(size: 22, weight: .bold))
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                if w.finished { Text("~ \(Int(w.duration / 60)) мин").font(.system(size: 16)) }
                                else if planned { Text("не начата").font(.system(size: 16)) }
                                else {
                                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                                        Text(fmtDur(w.elapsed(at: ctx.date))).font(.system(size: 26, weight: .black)).monospacedDigit()
                                            .foregroundStyle(running ? Color.white : Color.gOrange)
                                    }
                                    Text(running ? "идёт" : "пауза").font(.system(size: 12)).foregroundStyle(Color.gMuted)
                                }
                            }
                        }
                        HStack {
                            Stat(label: "подходов", value: "\(w.doneSets)/\(w.totalSets)")
                            Stat(label: "упражнений", value: "\(w.doneExercises)/\(w.exercises.count)")
                            Stat(label: "объём, кг", value: fmtVol(w.volume))
                        }
                        if let prev, !planned {
                            let dv = w.volume - prev.volume
                            Text("К прошлой тренировке (\(fmtShort(prev.startedAt))): объём \(dv >= 0 ? "+" : "−")\(fmtVol(abs(dv))) кг")
                                .font(.system(size: 13)).foregroundStyle(dv >= 0 ? Color.gGreen : Color.gOrange)
                        }
                        if w.finished && !prs.isEmpty {
                            Text("🏆 Личные рекорды").font(.system(size: 15, weight: .bold)).foregroundStyle(Color.gOrange)
                            ForEach(prs) { Text("\($0.name): \(fmtW($0.weight)) кг × \($0.reps)").font(.system(size: 14)) }
                        }
                        if !w.finished && !planned {
                            HStack(spacing: 8) {
                                if running { BigButton("Пауза", primary: false) { store.pauseWorkout(w.id) } }
                                else { BigButton("Продолжить отсчёт") { store.resumeWorkout(w.id) } }
                                NavigationLink(value: Route.timer) {
                                    Text("Таймер отдыха").font(.system(size: 17, weight: .bold)).foregroundStyle(Color.white)
                                        .frame(maxWidth: .infinity, minHeight: 54).background(Color.gCard2, in: RoundedRectangle(cornerRadius: 14))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }

                if !w.finished && store.rest.status != .idle {
                    NavigationLink(value: Route.timer) {
                        Card {
                            TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                                Text(restText(ctx.date)).font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(store.rest.status == .finished ? Color.gGreen : Color.gRed)
                            }
                        }
                    }.buttonStyle(.plain)
                }

                if w.exercises.isEmpty { Text("Упражнений пока нет. Добавьте первое кнопкой ниже.").foregroundStyle(Color.gMuted) }
                ForEach(Array(w.exercises.enumerated()), id: \.element.id) { idx, e in
                    let ex = store.exercise(e.exerciseId)
                    Card {
                        HStack {
                            Button { runIndex = idx; goRun = true } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(ex?.name ?? "Упражнение").font(.system(size: 18, weight: .bold)).multilineTextAlignment(.leading)
                                        Text(e.scheme + ((ex?.restSec ?? 0) > 0 ? " · отдых \(fmtDur(Double(ex!.restSec)))" : ""))
                                            .font(.system(size: 15)).foregroundStyle(Color.gMuted)
                                    }
                                    Spacer()
                                    Text("\(e.completion)%").font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(e.completion >= 100 ? Color.gGreen : (e.completion > 0 ? Color.gOrange : Color.gMuted))
                                }
                                .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Menu {
                                Button("Выше") { store.moveExercise(w.id, from: idx, by: -1) }.disabled(idx == 0)
                                Button("Ниже") { store.moveExercise(w.id, from: idx, by: 1) }.disabled(idx == w.exercises.count - 1)
                                Button("Убрать из тренировки", role: .destructive) { removing = e.id }
                            } label: { Image(systemName: "ellipsis").frame(width: 36, height: 36) }
                        }
                    }
                }

                VStack(spacing: 8) {
                    BigButton("+ Добавить упражнение", primary: false) { showPicker = true }
                    if planned {
                        BigButton("Начать тренировку", height: 64) { store.beginWorkout(w.id); runIndex = 0; goRun = true }
                            .disabled(w.exercises.isEmpty)
                    } else if !w.finished {
                        BigButton("Продолжить тренировку", height: 64) {
                            runIndex = max(0, w.exercises.firstIndex { $0.completion < 100 } ?? 0); goRun = true
                        }.disabled(w.exercises.isEmpty)
                        BigButton("Завершить тренировку", primary: false) { showFinish = true }
                    } else {
                        BigButton("Копировать тренировку") { copied = store.copyWorkout(w.id) }
                        BigButton("Сохранить как шаблон", primary: false) { templateName = store.label(w); showTemplate = true }
                        BigButton("Изменить длительность", primary: false) { minutesText = String(Int(w.duration / 60)); showDuration = true }
                    }
                    if !planned && w.doneSets > 0 { BigButton("Сбросить прогресс", primary: false) { showReset = true } }
                    BigButton(w.finished ? "Удалить из истории" : "Отменить тренировку", primary: false) { showDelete = true }
                }

                TextField("Заметка к тренировке", text: $noteText, axis: .vertical)
                    .padding(12).background(Color.gCard, in: RoundedRectangle(cornerRadius: 12))
                    .onAppear { noteText = w.note }
                    .onChange(of: noteText) { _, n in store.setWorkoutNote(w.id, n) }
            }
            .padding(16)
        }
        .navigationTitle(w.finished ? "Тренировка" : "Текущая тренировка")
        .alert("Завершить тренировку?", isPresented: $showFinish) {
            Button("Завершить", role: .destructive) { store.finishWorkout(w.id) }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Выполнено подходов: \(w.doneSets)." + (w.undoneSets > 0 ? " Неотмеченных: \(w.undoneSets) — они не попадут в статистику." : ""))
        }
        .alert("Сбросить прогресс?", isPresented: $showReset) {
            Button("Сбросить", role: .destructive) { store.resetProgress(w.id) }
            Button("Отмена", role: .cancel) {}
        } message: { Text("Все подходы станут невыполненными. Веса и повторения останутся.") }
        .alert(w.finished ? "Удалить тренировку?" : "Отменить тренировку?", isPresented: $showDelete) {
            Button("Удалить", role: .destructive) { store.deleteWorkout(w.id); dismiss() }
            Button("Назад", role: .cancel) {}
        } message: { Text("Все записанные подходы этой тренировки будут удалены без возможности восстановления.") }
        .alert("Убрать упражнение?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Убрать", role: .destructive) { if let r = removing { store.removeExercise(w.id, r) }; removing = nil }
            Button("Отмена", role: .cancel) { removing = nil }
        } message: { Text("Подходы этого упражнения в этой тренировке будут удалены.") }
        .alert("Длительность, минут", isPresented: $showDuration) {
            TextField("минут", text: $minutesText).keyboardType(.numberPad)
            Button("Сохранить") { if let m = Int(minutesText) { store.setDuration(w.id, minutes: m) } }
            Button("Отмена", role: .cancel) {}
        }
        .alert("Название шаблона", isPresented: $showTemplate) {
            TextField("Название", text: $templateName)
            Button("Сохранить") { if !templateName.trimmingCharacters(in: .whitespaces).isEmpty { store.saveAsTemplate(from: w, name: templateName) } }
            Button("Отмена", role: .cancel) {}
        }
    }

    private func restText(_ now: Date) -> String {
        switch store.rest.status {
        case .running: return "Отдых: " + fmtDur(store.rest.remaining(at: now) + 0.999)
        case .paused: return "Отдых на паузе: " + fmtDur(store.rest.pausedRemaining + 0.999)
        default: return "Отдых окончен — пора на подход!"
        }
    }
}
