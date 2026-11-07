import SwiftUI

struct ExerciseForm: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @State var name: String
    @State var group: MuscleGroup
    let onSave: (String, MuscleGroup) -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("Название", text: $name)
                Picker("Мышечная группа", selection: $group) {
                    ForEach(MuscleGroup.allCases) { Text($0.title).tag($0) }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        if !name.trimmingCharacters(in: .whitespaces).isEmpty { onSave(name, group); dismiss() }
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// Библиотека упражнений. В режиме выбора (pickMode) тап отмечает упражнения, внизу — кнопка «Добавить».
struct ExercisesView: View {
    @Environment(Store.self) private var store
    let pickMode: Bool
    let onPick: ([UUID]) -> Void

    @State private var query = ""
    @State private var group: MuscleGroup?
    @State private var selected = Set<UUID>()
    @State private var showAdd = false
    @State private var editing: Exercise?
    @State private var deleting: Exercise?

    private var filtered: [Exercise] {
        store.exercises.filter { (group == nil || $0.group == group) && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }
    }

    var body: some View {
        let list = filtered
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Chip(title: "Все", selected: group == nil) { group = nil }
                    ForEach(MuscleGroup.allCases) { g in Chip(title: g.title, selected: group == g) { group = g } }
                }.padding(.horizontal, 16).padding(.vertical, 8)
            }
            List {
                if list.isEmpty { Text("Ничего не найдено.").foregroundStyle(Color.gMuted).listRowBackground(Color.clear) }
                ForEach(MuscleGroup.allCases) { g in
                    let items = list.filter { $0.group == g }
                    if !items.isEmpty {
                        Section {
                            ForEach(items) { e in row(e) }
                        } header: {
                            Text(g.title.uppercased()).font(.system(size: 12, weight: .bold)).foregroundStyle(Color.gRed)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            if pickMode {
                BigButton(selected.isEmpty ? "Выберите упражнения" : "Добавить выбранные (\(selected.count))") {
                    onPick(Array(selected))
                }
                .disabled(selected.isEmpty).padding(16)
            }
        }
        .background(Color.gBg)
        .searchable(text: $query, prompt: "Поиск по названию")
        .navigationTitle(pickMode ? "Выбор упражнений" : "Упражнения")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) {
            ExerciseForm(title: "Новое упражнение", name: "", group: group ?? .other) { n, g in store.addExercise(name: n, group: g) }
        }
        .sheet(item: $editing) { e in
            ExerciseForm(title: "Редактировать", name: e.name, group: e.group) { n, g in store.editExercise(e.id, name: n, group: g) }
        }
        .alert("Удалить упражнение?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Удалить", role: .destructive) { if let d = deleting { store.deleteExercise(d.id) }; deleting = nil }
            Button("Отмена", role: .cancel) { deleting = nil }
        } message: { Text("Упражнение исчезнет из библиотеки. Уже записанные тренировки с ним сохранятся в истории.") }
    }

    @ViewBuilder
    private func row(_ e: Exercise) -> some View {
        Group {
            if pickMode {
                Button {
                    if selected.contains(e.id) { selected.remove(e.id) } else { selected.insert(e.id) }
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(e.name).font(.system(size: 16, weight: .medium))
                            if e.isCustom { Text("своё").font(.system(size: 11)).foregroundStyle(Color.gMuted) }
                        }
                        Spacer()
                        Image(systemName: selected.contains(e.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected.contains(e.id) ? Color.gRed : Color.gMuted).font(.system(size: 22))
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
            } else {
                NavigationLink(value: Route.exercise(e.id)) {
                    VStack(alignment: .leading) {
                        Text(e.name).font(.system(size: 16, weight: .medium))
                        if e.isCustom { Text("своё").font(.system(size: 11)).foregroundStyle(Color.gMuted) }
                    }
                }
                .swipeActions(edge: .trailing) {
                    if e.isCustom { Button("Удалить", role: .destructive) { deleting = e } }
                    Button("Изменить") { editing = e }.tint(Color.gCard2)
                }
            }
        }
        .listRowBackground(Color.gCard)
    }
}

struct ExercisePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: ([UUID]) -> Void
    var body: some View {
        NavigationStack {
            ExercisesView(pickMode: true) { ids in onPick(ids); dismiss() }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
        }
    }
}

struct ExerciseDetailView: View {
    @Environment(Store.self) private var store
    let exerciseId: UUID

    var body: some View {
        let ex = store.exercise(exerciseId)
        let record = store.bestRecords().first { $0.id == exerciseId }
        let history = store.finished.compactMap { w -> (Workout, [SetEntry])? in
            let s = w.exercises.filter { $0.exerciseId == exerciseId }.flatMap { $0.sets }
            return s.isEmpty ? nil : (w, s)
        }
        ScrollView {
            VStack(spacing: 10) {
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(ex?.group.title ?? "").foregroundStyle(Color.gMuted)
                        if let r = record {
                            Text("Лучший вес: \(fmtW(r.weight)) кг × \(r.reps)").font(.system(size: 20, weight: .bold))
                            Text(fmtDateTime(r.date)).font(.system(size: 12)).foregroundStyle(Color.gMuted)
                        } else { Text("Выполненных подходов с весом пока нет.").foregroundStyle(Color.gMuted) }
                        NavigationLink(value: Route.progress(exerciseId)) {
                            Text("График прогресса").font(.system(size: 17, weight: .bold)).foregroundStyle(Color.white)
                                .frame(maxWidth: .infinity, minHeight: 50).background(Color.gCard2, in: RoundedRectangle(cornerRadius: 14))
                        }.buttonStyle(.plain).padding(.top, 6)
                    }
                }
                SectionTitle("История подходов")
                if history.isEmpty { Text("Это упражнение ещё не выполнялось.").foregroundStyle(Color.gMuted).frame(maxWidth: .infinity, alignment: .leading) }
                ForEach(history, id: \.0.id) { w, sets in
                    NavigationLink(value: Route.workout(w.id)) {
                        Card {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(fmtDateTime(w.startedAt)).font(.system(size: 12)).foregroundStyle(Color.gMuted)
                                Text(sets.map { ($0.isWarmup ? "р " : "") + "\(fmtW($0.weight))×\($0.reps)" + ($0.done ? "" : " (не вып.)") }.joined(separator: "  ·  "))
                                    .font(.system(size: 15))
                            }
                        }
                    }.buttonStyle(.plain)
                }
            }.padding(16)
        }
        .background(Color.gBg)
        .navigationTitle(ex?.name ?? "Упражнение")
        .navigationBarTitleDisplayMode(.inline)
    }
}
