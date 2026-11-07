import Foundation

enum MuscleGroup: String, Codable, CaseIterable, Identifiable, Hashable {
    case chest, back, legs, shoulders, biceps, triceps, forearms, abs, calves, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .chest: return "Грудь"
        case .back: return "Спина"
        case .legs: return "Ноги"
        case .shoulders: return "Плечи"
        case .biceps: return "Бицепс"
        case .triceps: return "Трицепс"
        case .forearms: return "Предплечья"
        case .abs: return "Пресс"
        case .calves: return "Икры"
        case .other: return "Другие упражнения"
        }
    }
}

struct Exercise: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var group: MuscleGroup
    var isCustom = false
    var archived = false
    /// Свой отдых после подхода, сек. 0 — общий.
    var restSec = 0
}

struct SetEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var weight: Double = 0
    var reps: Int = 0
    var isWarmup = false
    var isBodyweight = false
    var done = false
}

struct WorkoutExercise: Codable, Identifiable, Hashable {
    var id = UUID()
    var exerciseId: UUID
    var note = ""
    var sets: [SetEntry] = []
}

struct Workout: Codable, Identifiable, Hashable {
    var id = UUID()
    var title = ""
    var startedAt = Date()
    var endedAt: Date?
    var finished = false
    /// false — тренировка выбрана, но секундомер ещё не запущен.
    var started = true
    var accumulated: TimeInterval = 0
    var resumedAt: Date?
    var duration: TimeInterval = 0
    var note = ""
    var exercises: [WorkoutExercise] = []
}

struct TemplateItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var exerciseId: UUID
    var targetSets = 3
    var targetReps = 8
}

struct Template: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var items: [TemplateItem] = []
}

struct AppSettings: Codable, Hashable {
    var vibration = true
    var sound = true
    var autoRest = true
    var lastRestSec = 120
}

struct Database: Codable {
    var version = 1
    var exercises: [Exercise] = []
    var templates: [Template] = []
    var workouts: [Workout] = []
    var settings = AppSettings()
    var seeded = false

    init() {}

    // Устойчивое чтение: недостающие поля (в более старых копиях) заполняются значениями по умолчанию.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        exercises = try c.decodeIfPresent([Exercise].self, forKey: .exercises) ?? []
        templates = try c.decodeIfPresent([Template].self, forKey: .templates) ?? []
        workouts = try c.decodeIfPresent([Workout].self, forKey: .workouts) ?? []
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        seeded = try c.decodeIfPresent(Bool.self, forKey: .seeded) ?? false
    }
}

// MARK: - Расчёты

extension SetEntry {
    var volume: Double { done && !isWarmup ? weight * Double(reps) : 0 }
}

/// Оценка одноповторного максимума (формула Эпли). Это расчёт, а не фактический вес.
func epley1RM(_ w: Double, _ reps: Int) -> Double {
    if reps <= 0 || w <= 0 { return 0 }
    return reps == 1 ? w : w * (1 + Double(reps) / 30.0)
}

extension WorkoutExercise {
    var completion: Int { sets.isEmpty ? 0 : sets.filter { $0.done }.count * 100 / sets.count }
    var volume: Double { sets.reduce(0) { $0 + $1.volume } }
    var scheme: String {
        let s = sets.filter { !$0.isWarmup }
        guard let f = s.first else { return "нет подходов" }
        if s.allSatisfy({ $0.reps == f.reps && $0.weight == f.weight }) {
            return "\(s.count)x\(f.reps)" + (f.weight > 0 ? "x\(fmtW(f.weight)) кг" : "")
        }
        return s.map { "\(fmtW($0.weight))×\($0.reps)" }.joined(separator: ", ")
    }
}

extension Workout {
    var isPlanned: Bool { !finished && !started }
    var volume: Double { exercises.reduce(0) { $0 + $1.volume } }
    var doneSets: Int { exercises.reduce(0) { $0 + $1.sets.filter { $0.done }.count } }
    var totalSets: Int { exercises.reduce(0) { $0 + $1.sets.count } }
    var undoneSets: Int { totalSets - doneSets }
    var doneExercises: Int { exercises.filter { $0.sets.contains { $0.done } }.count }
    var completion: Int { totalSets == 0 ? 0 : doneSets * 100 / totalSets }
    var workingSets: Int { exercises.reduce(0) { $0 + $1.sets.filter { $0.done && !$0.isWarmup }.count } }

    func elapsed(at now: Date) -> TimeInterval {
        if finished { return duration }
        return accumulated + (resumedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }
}

// MARK: - Встроенные упражнения

enum Seed {
    static let list: [(MuscleGroup, String)] = [
        (.chest, "Жим штанги лёжа"), (.chest, "Жим на наклонной скамье"), (.chest, "Жим гантелей лёжа"),
        (.chest, "Жим гантелей на наклонной скамье"), (.chest, "Разведения гантелей"), (.chest, "Сведения в кроссовере"),
        (.chest, "Жим в тренажёре"), (.chest, "Отжимания на брусьях"), (.chest, "Отжимания от пола"),
        (.back, "Становая тяга"), (.back, "Подтягивания"), (.back, "Тяга верхнего блока"),
        (.back, "Тяга штанги в наклоне"), (.back, "Тяга гантели одной рукой"), (.back, "Тяга нижнего блока"),
        (.back, "Тяга Т-грифа"), (.back, "Гиперэкстензия"), (.back, "Шраги со штангой"), (.back, "Шраги с гантелями"),
        (.legs, "Приседания со штангой"), (.legs, "Фронтальные приседания"), (.legs, "Жим ногами"),
        (.legs, "Выпады с гантелями"), (.legs, "Болгарские приседания"), (.legs, "Румынская тяга"),
        (.legs, "Разгибания ног в тренажёре"), (.legs, "Сгибания ног в тренажёре"), (.legs, "Ягодичный мостик"),
        (.shoulders, "Жим над головой"), (.shoulders, "Жим гантелей сидя"), (.shoulders, "Подъёмы гантелей в стороны"),
        (.shoulders, "Подъёмы гантелей перед собой"), (.shoulders, "Разведения гантелей в наклоне"),
        (.shoulders, "Тяга штанги к подбородку"), (.shoulders, "Жим Арнольда"),
        (.biceps, "Сгибания рук со штангой"), (.biceps, "Сгибания рук с гантелями"), (.biceps, "Молотки"),
        (.biceps, "Сгибания на скамье Скотта"), (.biceps, "Концентрированные сгибания"),
        (.triceps, "Французский жим"), (.triceps, "Разгибания рук на блоке"), (.triceps, "Жим узким хватом"),
        (.triceps, "Разгибания руки с гантелью из-за головы"), (.triceps, "Отжимания на брусьях (трицепс)"),
        (.forearms, "Сгибания запястий"), (.forearms, "Разгибания запястий"), (.forearms, "Фермерская прогулка"),
        (.abs, "Скручивания"), (.abs, "Подъём ног в висе"), (.abs, "Планка"), (.abs, "Скручивания на блоке"),
        (.abs, "Велосипед"), (.abs, "Ролик для пресса"),
        (.calves, "Подъёмы на икры стоя"), (.calves, "Подъёмы на икры сидя"), (.calves, "Подъёмы на икры в жиме ногами"),
        (.other, "Кардио (беговая дорожка)"), (.other, "Кардио (велотренажёр)"), (.other, "Гребной тренажёр")
    ]
    static func exercises() -> [Exercise] { list.map { Exercise(name: $0.1, group: $0.0) } }
}
