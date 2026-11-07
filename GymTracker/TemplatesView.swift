import SwiftUI

struct TemplatesView: View {
    @Environment(Store.self) private var store
    @State private var creating = false
    @State private var newName = ""
    @State private var deleting: Template?
    @State private var openWorkout: UUID?
    @State private var openTemplate: UUID?

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if store.db.templates.isEmpty {
                    Text("Шаблонов пока нет. Создайте первый, например «Push», «Pull» или «Legs».").foregroundStyle(Color.gMuted).frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(store.db.templates) { t in
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                NavigationLink(value: Route.template(t.id)) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(t.name).font(.system(size: 18, weight: .bold))
                                        Text("Упражнений: \(t.items.count)").font(.system(size: 13)).foregroundStyle(Color.gMuted)
                                    }
                                }.buttonStyle(.plain)
                                Spacer()
                                Button { deleting = t } label: { Image(systemName: "trash").foregroundStyle(Color.gMuted).frame(width: 40, height: 40) }
                            }
                            BigButton("Начать тренировку", primary: false) { openWorkout = store.startWorkout(templateId: t.id) }
                        }
                    }
                }
                BigButton("Новый шаблон") { newName = ""; creating = true }
            }.padding(16)
        }
        .background(Color.gBg)
        .navigationTitle("Шаблоны")
        .navigationDestination(item: $openWorkout) { WorkoutView(workoutId: $0) }
        .navigationDestination(item: $openTemplate) { TemplateEditView(templateId: $0) }
        .alert("Название шаблона", isPresented: $creating) {
            TextField("Например, Full Body A", text: $newName)
            Button("Создать") { if !newName.trimmingCharacters(in: .whitespaces).isEmpty { openTemplate = store.createTemplate(name: newName) } }
            Button("Отмена", role: .cancel) {}
        }
        .alert("Удалить шаблон?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Удалить", role: .destructive) { if let d = deleting { store.deleteTemplate(d.id) }; deleting = nil }
            Button("Отмена", role: .cancel) { deleting = nil }
        } message: { Text("История тренировок не изменится.") }
    }
}

struct TemplateEditView: View {
    @Environment(Store.self) private var store
    let templateId: UUID
    @State private var showPicker = false
    @State private var openWorkout: UUID?
    @State private var name = ""

    var body: some View {
        Group {
            if let t = store.template(templateId) {
                List {
                    Section {
                        TextField("Название", text: $name)
                            .onAppear { name = t.name }
                            .onChange(of: name) { _, n in
                                if !n.trimmingCharacters(in: .whitespaces).isEmpty { store.mutateTemplate(templateId) { $0.name = n } }
                            }
                    }
                    Section {
                        if t.items.isEmpty { Text("В шаблоне пока нет упражнений.").foregroundStyle(Color.gMuted) }
                        ForEach(t.items) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(store.exercise(item.exerciseId)?.name ?? "Удалённое упражнение").font(.system(size: 16, weight: .medium))
                                Stepper("Подходы: \(item.targetSets)", value: Binding(
                                    get: { item.targetSets },
                                    set: { v in store.mutateTemplate(templateId) { tt in if let i = tt.items.firstIndex(where: { $0.id == item.id }) { tt.items[i].targetSets = v } } }
                                ), in: 1...20)
                                Stepper("Повторы: \(item.targetReps)", value: Binding(
                                    get: { item.targetReps },
                                    set: { v in store.mutateTemplate(templateId) { tt in if let i = tt.items.firstIndex(where: { $0.id == item.id }) { tt.items[i].targetReps = v } } }
                                ), in: 1...100)
                            }
                            .listRowBackground(Color.gCard)
                        }
                        .onMove { src, dst in store.mutateTemplate(templateId) { $0.items.move(fromOffsets: src, toOffset: dst) } }
                        .onDelete { offsets in store.mutateTemplate(templateId) { $0.items.remove(atOffsets: offsets) } }
                    } footer: {
                        Text("Вес подставляется автоматически из прошлой тренировки. Порядок меняется кнопкой «Изменить» → перетаскивание.")
                    }
                    Section {
                        Button("+ Добавить упражнения") { showPicker = true }
                        Button("Начать тренировку") { openWorkout = store.startWorkout(templateId: templateId) }
                            .disabled(t.items.isEmpty).foregroundStyle(Color.gRed)
                    }
                }
                .scrollContentBackground(.hidden)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { EditButton() } }
            } else { Text("Шаблон не найден").foregroundStyle(Color.gMuted) }
        }
        .background(Color.gBg)
        .navigationTitle("Шаблон")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openWorkout) { WorkoutView(workoutId: $0) }
        .sheet(isPresented: $showPicker) { ExercisePickerSheet { ids in store.addToTemplate(templateId, exerciseIds: ids) } }
        .keyboardDone()
    }
}

struct HistoryView: View {
    @Environment(Store.self) private var store
    var body: some View {
        let prs = store.prs()
        ScrollView {
            LazyVStack(spacing: 10) {
                if store.finished.isEmpty { Text("Завершённых тренировок пока нет.").foregroundStyle(Color.gMuted).frame(maxWidth: .infinity, alignment: .leading) }
                ForEach(store.finished) { w in
                    NavigationLink(value: Route.workout(w.id)) {
                        Card {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(fmtDateTime(w.startedAt)).font(.system(size: 17, weight: .bold))
                                HStack {
                                    Stat(label: "длительность", value: fmtDur(w.duration))
                                    Stat(label: "подходов", value: String(w.doneSets))
                                    Stat(label: "объём, кг", value: fmtVol(w.volume))
                                }
                                Text(w.exercises.compactMap { store.exercise($0.exerciseId)?.name }.joined(separator: " · "))
                                    .font(.system(size: 13)).foregroundStyle(Color.gMuted).lineLimit(2).multilineTextAlignment(.leading)
                                if let c = prs[w.id]?.count, c > 0 { Text("🏆 Рекордов: \(c)").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.gOrange) }
                                if !w.note.isEmpty { Text(w.note).font(.system(size: 12)).foregroundStyle(Color.gMuted).lineLimit(1) }
                            }
                        }
                    }.buttonStyle(.plain)
                }
            }.padding(16)
        }
        .background(Color.gBg)
        .navigationTitle("Все тренировки")
        .navigationBarTitleDisplayMode(.inline)
    }
}
