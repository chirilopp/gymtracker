import Foundation
import Observation

/// Хранилище всех данных приложения. Данные лежат в одном JSON-файле (Documents/gymtracker.json),
/// запись атомарная; файл содержит номер версии формата для будущих миграций.
@Observable
final class Store {
    var db = Database()
    var toast: String?
    let rest = RestTimer()

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let url: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("gymtracker.json")
    }()
    static let formatVersion = 1

    init() {
        if let data = try? Data(contentsOf: url) {
            let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
            if let loaded = try? dec.decode(Database.self, from: data) { db = loaded }
            else {
                // Файл повреждён — сохраняем копию, чтобы ничего не потерять.
                try? FileManager.default.copyItem(at: url, to: url.deletingLastPathComponent().appendingPathComponent("gymtracker-corrupt-\(Int(Date().timeIntervalSince1970)).json"))
            }
        }
        if !db.seeded {
            db.exercises += Seed.exercises()
            db.seeded = true
            writeNow()
        }
        syncRestSettings()
    }

    // MARK: - сохранение

    func save() {
        syncRestSettings()
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if !Task.isCancelled { self?.writeNow() }
        }
    }

    func writeNow() {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        db.version = Store.formatVersion
        if let data = try? enc.encode(db) { try? data.write(to: url, options: .atomic) }
    }

    private func syncRestSettings() {
        rest.soundOn = db.settings.sound
        rest.vibrationOn = db.settings.vibration
    }

    func say(_ s: String) { toast = s }

    // MARK: - выборки

    var exercises: [Exercise] { db.exercises.filter { !$0.archived }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }
    var finished: [Workout] { db.workouts.filter { $0.finished }.sorted { $0.startedAt > $1.startedAt } }
    var active: Workout? { db.workouts.filter { !$0.finished }.max { $0.startedAt < $1.startedAt } }

    func exercise(_ id: UUID) -> Exercise? { db.exercises.first { $0.id == id } }
    func workout(_ id: UUID) -> Workout? { db.workouts.first { $0.id == id } }
    func template(_ id: UUID) -> Template? { db.templates.first { $0.id == id } }

    func label(_ w: Workout) -> String {
        if !w.title.isEmpty { return w.title }
        var counts: [MuscleGroup: Int] = [:]
        for e in w.exercises { if let g = exercise(e.exerciseId)?.group { counts[g, default: 0] += 1 } }
        let top = counts.sorted { $0.value > $1.value }.prefix(2).map { $0.key.title.lowercased() }
        return top.isEmpty ? "тренировка" : top.joined(separator: "/")
    }

    /// Подходы упражнения из последней предыдущей тренировки (для автозаполнения).
    func previousSets(exerciseId: UUID, before: Date, excluding: UUID? = nil) -> [SetEntry] {
        for w in finished where w.startedAt < before && w.id != excluding {
            let s = w.exercises.filter { $0.exerciseId == exerciseId }.flatMap { $0.sets }.filter { $0.done }
            if !s.isEmpty { return s }
        }
        return []
    }

    // MARK: - упражнения

    func addExercise(name: String, group: MuscleGroup) {
        db.exercises.append(Exercise(name: name.trimmingCharacters(in: .whitespaces), group: group, isCustom: true)); save()
    }
    func editExercise(_ id: UUID, name: String, group: MuscleGroup) {
        guard let i = db.exercises.firstIndex(where: { $0.id == id }) else { return }
        db.exercises[i].name = name.trimmingCharacters(in: .whitespaces); db.exercises[i].group = group; save()
    }
    /// «Мягкое» удаление: история тренировок с упражнением сохраняется.
    func deleteExercise(_ id: UUID) {
        guard let i = db.exercises.firstIndex(where: { $0.id == id }), db.exercises[i].isCustom else { return }
        db.exercises[i].archived = true; save()
    }
    func setExerciseRest(_ id: UUID, sec: Int) {
        guard let i = db.exercises.firstIndex(where: { $0.id == id }) else { return }
        db.exercises[i].restSec = min(max(sec, 0), 3600); save()
    }

    // MARK: - шаблоны

    @discardableResult
    func createTemplate(name: String) -> UUID {
        let t = Template(name: name.trimmingCharacters(in: .whitespaces)); db.templates.append(t); save(); return t.id
    }
    func mutateTemplate(_ id: UUID, _ f: (inout Template) -> Void) {
        guard let i = db.templates.firstIndex(where: { $0.id == id }) else { return }
        f(&db.templates[i]); save()
    }
    func deleteTemplate(_ id: UUID) { db.templates.removeAll { $0.id == id }; save() }
    func addToTemplate(_ id: UUID, exerciseIds: [UUID]) {
        mutateTemplate(id) { t in exerciseIds.forEach { t.items.append(TemplateItem(exerciseId: $0)) } }
    }
    func saveAsTemplate(from w: Workout, name: String) {
        var t = Template(name: name.trimmingCharacters(in: .whitespaces))
        for e in w.exercises {
            let work = e.sets.filter { !$0.isWarmup }
            t.items.append(TemplateItem(exerciseId: e.exerciseId, targetSets: max(work.count, 1),
                                        targetReps: (work.first?.reps ?? 0) > 0 ? work[0].reps : 8))
        }
        db.templates.append(t); save(); say("Шаблон «\(t.name)» сохранён")
    }

    // MARK: - тренировки

    func mutateWorkout(_ id: UUID, _ f: (inout Workout) -> Void) {
        guard let i = db.workouts.firstIndex(where: { $0.id == id }) else { return }
        f(&db.workouts[i]); save()
    }

    private func buildExercise(_ exerciseId: UUID, startedAt: Date, excluding: UUID?, targetSets: Int?, targetReps: Int?) -> WorkoutExercise {
        let prev = previousSets(exerciseId: exerciseId, before: startedAt, excluding: excluding)
        let prevWork = prev.filter { !$0.isWarmup }
        var sets: [SetEntry] = []
        if let n = targetSets {
            for i in 0..<n {
                let ref = i < prevWork.count ? prevWork[i] : prevWork.last
                sets.append(SetEntry(weight: ref?.weight ?? 0, reps: targetReps ?? 8, isBodyweight: ref?.isBodyweight ?? false))
            }
        } else if prev.isEmpty {
            sets = (0..<3).map { _ in SetEntry(reps: 8) }
        } else {
            sets = prev.map { SetEntry(weight: $0.weight, reps: $0.reps, isWarmup: $0.isWarmup, isBodyweight: $0.isBodyweight) }
        }
        return WorkoutExercise(exerciseId: exerciseId, sets: sets)
    }

    /// Выбор тренировки (шаблона): создаётся запланированная тренировка, секундомер запускается по «Начать».
    @discardableResult
    func startWorkout(templateId: UUID?) -> UUID {
        if let a = active {
            if a.started { say("Сначала завершите текущую тренировку"); return a.id }
            db.workouts.removeAll { $0.id == a.id }      // выбрана, но не начата — заменяем
        }
        var w = Workout(started: false)
        if let tid = templateId, let t = template(tid) {
            w.title = t.name
            w.exercises = t.items.map { buildExercise($0.exerciseId, startedAt: w.startedAt, excluding: nil, targetSets: $0.targetSets, targetReps: $0.targetReps) }
        }
        db.workouts.append(w); save()
        return w.id
    }

    func beginWorkout(_ id: UUID) {
        mutateWorkout(id) { w in
            if !w.started && !w.finished { let n = Date(); w.started = true; w.startedAt = n; w.resumedAt = n }
        }
    }
    func pauseWorkout(_ id: UUID) {
        mutateWorkout(id) { w in
            if let r = w.resumedAt { w.accumulated += max(0, Date().timeIntervalSince(r)); w.resumedAt = nil }
        }
    }
    func resumeWorkout(_ id: UUID) { mutateWorkout(id) { w in if w.resumedAt == nil && w.started && !w.finished { w.resumedAt = Date() } } }

    func finishWorkout(_ id: UUID) {
        mutateWorkout(id) { w in
            let now = Date()
            let total = w.elapsed(at: now)
            w.finished = true; w.endedAt = now; w.duration = total; w.accumulated = total; w.resumedAt = nil
        }
        rest.stop()
    }
    func setDuration(_ id: UUID, minutes: Int) { mutateWorkout(id) { $0.duration = TimeInterval(minutes * 60); $0.accumulated = $0.duration } }
    func deleteWorkout(_ id: UUID) {
        if let w = workout(id), !w.finished { rest.stop() }
        db.workouts.removeAll { $0.id == id }; save()
    }
    func setWorkoutNote(_ id: UUID, _ s: String) { mutateWorkout(id) { $0.note = s } }
    func resetProgress(_ id: UUID) {
        mutateWorkout(id) { w in
            for i in w.exercises.indices { for j in w.exercises[i].sets.indices { w.exercises[i].sets[j].done = false } }
        }
        rest.stop()
    }

    @discardableResult
    func copyWorkout(_ id: UUID) -> UUID? {
        guard let src = workout(id) else { return nil }
        if active != nil { say("Сначала завершите текущую тренировку"); return nil }
        var w = Workout(started: false)
        w.title = src.title
        w.exercises = src.exercises.map { e in
            WorkoutExercise(exerciseId: e.exerciseId, note: e.note,
                            sets: e.sets.map { SetEntry(weight: $0.weight, reps: $0.reps, isWarmup: $0.isWarmup, isBodyweight: $0.isBodyweight) })
        }
        db.workouts.append(w); save()
        return w.id
    }

    func addExercises(to wid: UUID, ids: [UUID]) {
        guard let w = workout(wid) else { return }
        let built = ids.map { buildExercise($0, startedAt: w.startedAt, excluding: wid, targetSets: nil, targetReps: nil) }
        mutateWorkout(wid) { $0.exercises += built }
    }
    func removeExercise(_ wid: UUID, _ weId: UUID) { mutateWorkout(wid) { $0.exercises.removeAll { $0.id == weId } } }
    func moveExercise(_ wid: UUID, from: Int, by delta: Int) {
        mutateWorkout(wid) { w in
            let to = from + delta
            guard w.exercises.indices.contains(from), w.exercises.indices.contains(to) else { return }
            w.exercises.swapAt(from, to)
        }
    }
    func setExerciseNote(_ wid: UUID, _ weId: UUID, _ s: String) {
        mutateWorkout(wid) { w in if let j = w.exercises.firstIndex(where: { $0.id == weId }) { w.exercises[j].note = s } }
    }

    // MARK: - подходы

    func mutateSet(_ wid: UUID, _ weId: UUID, _ sid: UUID, _ f: (inout SetEntry) -> Void) {
        mutateWorkout(wid) { w in
            guard let j = w.exercises.firstIndex(where: { $0.id == weId }),
                  let k = w.exercises[j].sets.firstIndex(where: { $0.id == sid }) else { return }
            f(&w.exercises[j].sets[k])
        }
    }
    func addSet(_ wid: UUID, _ weId: UUID, warmup: Bool) {
        mutateWorkout(wid) { w in
            guard let j = w.exercises.firstIndex(where: { $0.id == weId }) else { return }
            let sets = w.exercises[j].sets
            let last = sets.last { $0.isWarmup == warmup } ?? sets.last
            w.exercises[j].sets.append(SetEntry(weight: last?.weight ?? 0, reps: last?.reps ?? 0, isWarmup: warmup, isBodyweight: last?.isBodyweight ?? false))
        }
    }
    func deleteSet(_ wid: UUID, _ weId: UUID, _ sid: UUID) {
        mutateWorkout(wid) { w in
            if let j = w.exercises.firstIndex(where: { $0.id == weId }) { w.exercises[j].sets.removeAll { $0.id == sid } }
        }
    }

    func startRest(seconds: Int) {
        db.settings.lastRestSec = seconds
        save()
        rest.start(seconds: seconds)
    }
    func restSeconds(for exerciseId: UUID) -> Int {
        let r = exercise(exerciseId)?.restSec ?? 0
        return r > 0 ? r : db.settings.lastRestSec
    }

    func toggleDone(_ wid: UUID, _ weId: UUID, _ sid: UUID) {
        guard let w = workout(wid), let e = w.exercises.first(where: { $0.id == weId }),
              let s = e.sets.first(where: { $0.id == sid }) else { return }
        mutateSet(wid, weId, sid) { $0.done.toggle() }
        if !s.done && !w.finished && db.settings.autoRest { startRest(seconds: restSeconds(for: e.exerciseId)) }
    }

    /// Кнопка «+»: записывает подход в первый невыполненный запланированный (или новый).
    func recordSet(_ wid: UUID, _ weId: UUID, weight: Double, reps: Int) {
        guard reps > 0 else { say("Введите число повторений"); return }
        guard let w = workout(wid), let e = w.exercises.first(where: { $0.id == weId }) else { return }
        mutateWorkout(wid) { w in
            if !w.finished && !w.started { let n = Date(); w.started = true; w.startedAt = n; w.resumedAt = n }
            guard let j = w.exercises.firstIndex(where: { $0.id == weId }) else { return }
            if let k = w.exercises[j].sets.firstIndex(where: { !$0.done }) {
                w.exercises[j].sets[k].weight = weight; w.exercises[j].sets[k].reps = reps; w.exercises[j].sets[k].done = true
            } else {
                w.exercises[j].sets.append(SetEntry(weight: weight, reps: reps, isBodyweight: w.exercises[j].sets.last?.isBodyweight ?? false, done: true))
            }
        }
        if !w.finished && db.settings.autoRest { startRest(seconds: restSeconds(for: e.exerciseId)) }
    }

    // MARK: - резервная копия

    func exportBackup() -> Data {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        var copy = db; copy.version = Store.formatVersion
        return (try? enc.encode(copy)) ?? Data()
    }

    func importBackup(_ data: Data) {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        do {
            var loaded = try dec.decode(Database.self, from: data)
            guard loaded.version <= Store.formatVersion else { say("Копия создана более новой версией приложения"); return }
            if loaded.exercises.isEmpty && loaded.workouts.isEmpty && loaded.templates.isEmpty { say("Файл не похож на копию GymTracker"); return }
            loaded.seeded = true
            rest.stop()
            db = loaded; writeNow()
            say("Данные восстановлены из копии")
        } catch {
            say("Не удалось прочитать файл копии")
        }
    }

    func deleteAllData() {
        rest.stop()
        var fresh = Database(); fresh.exercises = Seed.exercises(); fresh.seeded = true
        db = fresh; writeNow()
        say("Все данные удалены")
    }

    func csv() -> String {
        func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX"); df.dateFormat = "yyyy-MM-dd HH:mm"
        var out = "date,workout_id,duration_min,exercise,muscle_group,set_no,type,weight_kg,reps,bodyweight,done,volume_kg\n"
        for w in finished.reversed() {
            for e in w.exercises {
                let ex = exercise(e.exerciseId)
                for (i, s) in e.sets.enumerated() {
                    out += [df.string(from: w.startedAt), w.id.uuidString, String(Int(w.duration / 60)), q(ex?.name ?? ""),
                            ex?.group.title ?? "", String(i + 1), s.isWarmup ? "warmup" : "working", fmtW(s.weight),
                            String(s.reps), String(s.isBodyweight), String(s.done), String(format: "%.1f", s.volume)].joined(separator: ",") + "\n"
                }
            }
        }
        return out
    }
}

// MARK: - статистика

struct ExercisePoint: Identifiable {
    let id: UUID; let date: Date
    let bestWeight: Double; let bestReps: Int; let totalReps: Int; let volume: Double; let e1rm: Double
}
struct PRInfo: Identifiable { let id = UUID(); let name: String; let weight: Double; let reps: Int }
struct BestRecord: Identifiable { let id: UUID; let name: String; let weight: Double; let reps: Int; let date: Date }

extension Store {
    func exerciseHistory(_ exerciseId: UUID) -> [ExercisePoint] {
        finished.reversed().compactMap { w in
            let sets = w.exercises.filter { $0.exerciseId == exerciseId }.flatMap { $0.sets }.filter { $0.done && !$0.isWarmup }
            guard let best = sets.max(by: { ($0.weight, $0.reps) < ($1.weight, $1.reps) }) else { return nil }
            return ExercisePoint(id: w.id, date: w.startedAt, bestWeight: best.weight, bestReps: best.reps,
                                 totalReps: sets.reduce(0) { $0 + $1.reps }, volume: sets.reduce(0) { $0 + $1.weight * Double($1.reps) },
                                 e1rm: sets.map { epley1RM($0.weight, $0.reps) }.max() ?? 0)
        }
    }

    /// Рекорды, установленные на тренировке (вес выше любого предыдущего результата).
    func prs() -> [UUID: [PRInfo]] {
        var best: [UUID: Double] = [:]
        var out: [UUID: [PRInfo]] = [:]
        for w in finished.reversed() {
            for (exId, list) in Dictionary(grouping: w.exercises, by: { $0.exerciseId }) {
                let sets = list.flatMap { $0.sets }.filter { $0.done && !$0.isWarmup && $0.weight > 0 }
                guard let top = sets.max(by: { ($0.weight, $0.reps) < ($1.weight, $1.reps) }) else { continue }
                if let prev = best[exId], top.weight > prev {
                    out[w.id, default: []].append(PRInfo(name: exercise(exId)?.name ?? "Упражнение", weight: top.weight, reps: top.reps))
                }
                if best[exId] == nil || top.weight > best[exId]! { best[exId] = top.weight }
            }
        }
        return out
    }

    func bestRecords() -> [BestRecord] {
        var map: [UUID: BestRecord] = [:]
        for w in finished.reversed() {
            for e in w.exercises {
                for s in e.sets where s.done && !s.isWarmup && s.weight > 0 {
                    if let cur = map[e.exerciseId], !(s.weight > cur.weight || (s.weight == cur.weight && s.reps > cur.reps)) { continue }
                    map[e.exerciseId] = BestRecord(id: e.exerciseId, name: exercise(e.exerciseId)?.name ?? "Упражнение", weight: s.weight, reps: s.reps, date: w.startedAt)
                }
            }
        }
        return map.values.sorted { $0.name < $1.name }
    }
}
