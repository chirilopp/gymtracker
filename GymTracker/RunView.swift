import SwiftUI

/// Одно упражнение на экран: свайп влево/вправо переключает упражнения тренировки.
struct RunView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let workoutId: UUID
    @State private var page: Int

    init(workoutId: UUID, startIndex: Int) {
        self.workoutId = workoutId
        _page = State(initialValue: startIndex)
    }

    var body: some View {
        Group {
            if let w = store.workout(workoutId), !w.exercises.isEmpty {
                let count = w.exercises.count
                let cur = min(max(page, 0), count - 1)
                let group = store.exercise(w.exercises[cur].exerciseId)?.group.title ?? ""
                TabView(selection: $page) {
                    ForEach(Array(w.exercises.enumerated()), id: \.element.id) { i, e in
                        ExercisePage(workoutId: workoutId, weId: e.id).tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .navigationTitle("\(cur + 1)/\(count) \(group)")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            if w.started && !w.finished {
                                if w.resumedAt != nil { store.pauseWorkout(w.id) } else { store.resumeWorkout(w.id) }
                            }
                        } label: {
                            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                                Text(!w.started ? "0:00" : fmtDur(w.elapsed(at: ctx.date)) + (w.resumedAt == nil && !w.finished ? " ❚❚" : ""))
                                    .font(.system(size: 17, weight: .semibold)).monospacedDigit()
                                    .foregroundStyle(w.resumedAt == nil && w.started && !w.finished ? Color.gOrange : Color.white)
                            }
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    HStack(spacing: 8) {
                        BigButton("‹ Назад", primary: false) { withAnimation { page = cur - 1 } }.disabled(cur == 0)
                        if cur < count - 1 { BigButton("Дальше ›") { withAnimation { page = cur + 1 } } }
                        else { BigButton("К списку") { dismiss() } }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Color.gBg)
                }
            } else {
                Text("В тренировке нет упражнений.").foregroundStyle(Color.gMuted)
            }
        }
        .background(Color.gBg)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .keyboardDone()
    }
}

private struct Ring<Content: View>: View {
    let color: Color
    let label: String
    var action: (() -> Void)?
    let content: Content

    init(color: Color, label: String, action: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.color = color; self.label = label; self.action = action; self.content = content()
    }
    var body: some View {
        VStack(spacing: 6) {
            Button { action?() } label: {
                content.frame(width: 88, height: 88)
                    .overlay(Circle().stroke(color, lineWidth: 5))
                    .contentShape(Circle())
            }.buttonStyle(.plain).disabled(action == nil)
            Text(label).font(.system(size: 13)).foregroundStyle(Color.gMuted).multilineTextAlignment(.center)
        }
        .frame(width: 104)
    }
}

struct SetRowView: View {
    @Environment(Store.self) private var store
    let workoutId: UUID
    let weId: UUID
    let set: SetEntry
    let label: String
    @State private var wText = ""
    @State private var rText = ""

    var body: some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 16, weight: .bold)).foregroundStyle(set.isWarmup ? Color.gOrange : Color.gMuted).frame(width: 26)
            NumField(title: set.isBodyweight ? "+кг (свой вес)" : "кг", text: $wText)
            Text("×").foregroundStyle(Color.gMuted)
            NumField(title: "повт.", text: $rText, decimal: false)
            Button { store.toggleDone(workoutId, weId, set.id) } label: {
                Image(systemName: "checkmark").font(.system(size: 18, weight: .bold))
                    .foregroundStyle(set.done ? Color.white : Color.gMuted)
                    .frame(width: 46, height: 46).background(set.done ? Color.gGreen : Color.gCard2, in: Circle())
            }.buttonStyle(.plain)
            Menu {
                Button(set.isWarmup ? "Сделать рабочим" : "Разминочный подход") { store.mutateSet(workoutId, weId, set.id) { $0.isWarmup.toggle() } }
                Button(set.isBodyweight ? "Убрать «свой вес»" : "Упражнение с собственным весом") { store.mutateSet(workoutId, weId, set.id) { $0.isBodyweight.toggle() } }
                Button("Удалить подход", role: .destructive) { store.deleteSet(workoutId, weId, set.id) }
            } label: { Image(systemName: "ellipsis").frame(width: 32, height: 40) }
        }
        .onAppear { wText = set.weight > 0 ? fmtW(set.weight) : ""; rText = set.reps > 0 ? String(set.reps) : "" }
        .onChange(of: wText) { _, n in
            let v = parseWeight(n)
            if v != set.weight { store.mutateSet(workoutId, weId, set.id) { $0.weight = v } }
        }
        .onChange(of: rText) { _, n in
            let v = Int(n) ?? 0
            if v != set.reps { store.mutateSet(workoutId, weId, set.id) { $0.reps = v } }
        }
        .onChange(of: set.weight) { _, n in if parseWeight(wText) != n { wText = n > 0 ? fmtW(n) : "" } }
        .onChange(of: set.reps) { _, n in if (Int(rText) ?? 0) != n { rText = n > 0 ? String(n) : "" } }
    }
}

struct ExercisePage: View {
    @Environment(Store.self) private var store
    let workoutId: UUID
    let weId: UUID
    @State private var weightText = ""
    @State private var repsText = ""
    @State private var noteText = ""
    @State private var customRest = false
    @State private var cm = ""
    @State private var cs = ""

    private let presets: [(String, Int)] = [("30с", 30), ("1:00", 60), ("1:30", 90), ("2:00", 120), ("3:00", 180), ("4:00", 240), ("5:00", 300)]

    var body: some View {
        if let w = store.workout(workoutId), let e = w.exercises.first(where: { $0.id == weId }) {
            page(w, e)
        } else { Color.clear }
    }

    private func load(_ ref: SetEntry?) {
        weightText = (ref?.weight ?? 0) > 0 ? fmtW(ref!.weight) : ""
        repsText = (ref?.reps ?? 0) > 0 ? String(ref!.reps) : ""
    }

    @ViewBuilder
    private func page(_ w: Workout, _ e: WorkoutExercise) -> some View {
        let ex = store.exercise(e.exerciseId)
        let next = e.sets.first { !$0.done }
        let ref = next ?? e.sets.last
        let refKey = "\(ref?.id.uuidString ?? "")\(ref?.done ?? false)"
        let doneCount = e.sets.filter { $0.done }.count
        let prevWork = store.previousSets(exerciseId: e.exerciseId, before: w.startedAt, excluding: w.id).filter { !$0.isWarmup }
        let history = store.finished.filter { $0.id != w.id }.compactMap { fw -> (Workout, [SetEntry])? in
            let s = fw.exercises.filter { $0.exerciseId == e.exerciseId }.flatMap { $0.sets }.filter { $0.done }
            return s.isEmpty ? nil : (fw, s)
        }.prefix(10)
        let restSet = ex?.restSec ?? 0
        let exRest = restSet > 0 ? restSet : store.db.settings.lastRestSec

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(ex?.name ?? "Упражнение").font(.system(size: 26, weight: .bold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("План: \(e.scheme)").font(.system(size: 15))
                    Text(prevWork.isEmpty ? "Прошлых результатов нет — введите вес." :
                            "В прошлый раз: " + prevWork.map { "\(fmtW($0.weight))×\($0.reps)" }.joined(separator: ", "))
                        .font(.system(size: 15)).foregroundStyle(Color.gMuted)
                }

                HStack {
                    Ring(color: Color.gRed, label: "Повторений требуется") {
                        Text((next?.reps ?? 0) > 0 ? String(next!.reps) : "—").font(.system(size: 30, weight: .bold))
                    }
                    Spacer()
                    Ring(color: ringColor(), label: store.rest.status == .idle ? "Отдых: старт" : "Отдых: сброс", action: {
                        // одно нажатие: идёт таймер — сбросить, иначе запустить отдых этого упражнения
                        if store.rest.status == .idle { store.startRest(seconds: exRest) } else { store.rest.reset() }
                    }) {
                        TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
                            switch store.rest.status {
                            case .idle: Text(fmtDur(Double(exRest))).font(.system(size: 22, weight: .bold))
                            case .running: Text(fmtDur(store.rest.remaining(at: ctx.date) + 0.999)).font(.system(size: 22, weight: .bold)).monospacedDigit()
                            case .paused: Text("❚❚").font(.system(size: 22)).foregroundStyle(Color.gOrange)
                            case .finished: Text("GO!").font(.system(size: 24, weight: .black)).foregroundStyle(Color.gGreen)
                            }
                        }
                    }
                    Spacer()
                    Ring(color: (!e.sets.isEmpty && doneCount == e.sets.count) ? Color.gGreen : Color.gRedDark, label: "Подходов выполнено") {
                        Text("\(doneCount)/\(e.sets.count)").font(.system(size: 26, weight: .bold))
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Отдых после подхода: " + fmtDur(Double(exRest)) + (restSet == 0 ? " (общий)" : ""))
                        .font(.system(size: 13)).foregroundStyle(Color.gMuted)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(presets, id: \.1) { p in
                                Chip(title: p.0, selected: restSet == p.1) { store.setExerciseRest(e.exerciseId, sec: p.1) }
                            }
                            Chip(title: "Своё", selected: restSet > 0 && !presets.contains { $0.1 == restSet }) {
                                cm = String(exRest / 60); cs = String(exRest % 60); customRest = true
                            }
                        }
                    }
                }

                HStack(spacing: 8) {
                    NumField(title: "Килограммы", text: $weightText)
                    NumField(title: "Повторы", text: $repsText, decimal: false)
                    Button {
                        store.recordSet(workoutId, weId, weight: parseWeight(weightText), reps: Int(repsText) ?? 0)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        Text("+").font(.system(size: 36, weight: .bold)).foregroundStyle(Color.white)
                            .frame(width: 64, height: 64).background(Color.gRed, in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain)
                }
                Text("«+» записывает подход как выполненный и запускает отдых.").font(.system(size: 12)).foregroundStyle(Color.gMuted)

                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Подходы в этой тренировке").font(.system(size: 17, weight: .bold))
                        let labels = setLabels(e.sets)
                        ForEach(Array(e.sets.enumerated()), id: \.element.id) { i, s in
                            SetRowView(workoutId: workoutId, weId: weId, set: s, label: labels[i])
                        }
                        HStack(spacing: 16) {
                            Button("+ Подход") { store.addSet(workoutId, weId, warmup: false) }.font(.system(size: 15, weight: .bold))
                            Button("+ Разминка") { store.addSet(workoutId, weId, warmup: true) }.font(.system(size: 15)).foregroundStyle(Color.gOrange)
                        }
                        TextField("Комментарий к упражнению", text: $noteText, axis: .vertical)
                            .padding(12).background(Color.gCard2, in: RoundedRectangle(cornerRadius: 12))
                            .onChange(of: noteText) { _, n in store.setExerciseNote(workoutId, weId, n) }
                    }
                }

                SectionTitle("История")
                if history.isEmpty { Text("Это упражнение раньше не выполнялось.").foregroundStyle(Color.gMuted) }
                ForEach(Array(history), id: \.0.id) { fw, s in
                    Card {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fmtDate(fw.startedAt, "EEE, dd.MM.yyyy").capitalized).font(.system(size: 16, weight: .semibold))
                            Text(s.map { ($0.isWarmup ? "р " : "") + "\(fmtW($0.weight))×\($0.reps)" }.joined(separator: "  ·  "))
                                .font(.system(size: 15)).foregroundStyle(Color.gMuted)
                        }
                    }
                }
                Spacer(minLength: 20)
            }
            .padding(.horizontal, 16)
        }
        .onAppear { load(ref); noteText = e.note }
        .onChange(of: refKey) { _, _ in load(ref) }
        .alert("Отдых для этого упражнения", isPresented: $customRest) {
            TextField("мин", text: $cm).keyboardType(.numberPad)
            TextField("сек", text: $cs).keyboardType(.numberPad)
            Button("Сохранить") {
                let total = (Int(cm) ?? 0) * 60 + (Int(cs) ?? 0)
                if total > 0 { store.setExerciseRest(e.exerciseId, sec: total) }
            }
            Button("Общий") { store.setExerciseRest(e.exerciseId, sec: 0) }
            Button("Отмена", role: .cancel) {}
        }
    }

    private func ringColor() -> Color {
        switch store.rest.status {
        case .idle: return Color.gRedDark
        case .finished: return Color.gGreen
        default: return Color.gOrange
        }
    }

    private func setLabels(_ sets: [SetEntry]) -> [String] {
        var n = 0
        return sets.map { s in if s.isWarmup { return "Р" }; n += 1; return String(n) }
    }
}
