import SwiftUI
import UniformTypeIdentifiers

struct DataDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText, .plainText] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct SettingsView: View {
    @Environment(Store.self) private var store
    @State private var doc = DataDocument(data: Data())
    @State private var docType: UTType = .json
    @State private var docName = "gymtracker"
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var confirmImport = false
    @State private var confirmDelete = false

    private var stamp: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyyMMdd-HHmm"; return f.string(from: Date())
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Сигнал окончания отдыха").font(.system(size: 17, weight: .bold))
                        Toggle("Звук", isOn: Binding(get: { store.db.settings.sound }, set: { store.db.settings.sound = $0; store.save() }))
                        Toggle("Вибрация", isOn: Binding(get: { store.db.settings.vibration }, set: { store.db.settings.vibration = $0; store.save() }))
                        Text("Когда приложение закрыто или экран выключен, сигнал подаёт системное уведомление (звук — обычный звук уведомлений). Беззвучный режим на боковом переключателе отключает звук, но не вибрацию. Изменение действует со следующего запуска таймера.")
                            .font(.system(size: 12)).foregroundStyle(Color.gMuted)
                    }
                }
                Card {
                    Toggle(isOn: Binding(get: { store.db.settings.autoRest }, set: { store.db.settings.autoRest = $0; store.save() })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Автозапуск отдыха").font(.system(size: 17, weight: .bold))
                            Text("Запускать таймер после записи подхода (общий отдых: \(store.db.settings.lastRestSec) с)").font(.system(size: 13)).foregroundStyle(Color.gMuted)
                        }
                    }
                }
                NavigationLink(value: Route.templates) { link("Шаблоны тренировок") }.buttonStyle(.plain)
                NavigationLink(value: Route.history) { link("Список всех тренировок") }.buttonStyle(.plain)

                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Данные и резервные копии").font(.system(size: 17, weight: .bold))
                        Text("Все данные хранятся только на телефоне. После переустановки приложения восстановите их из файла копии.").font(.system(size: 13)).foregroundStyle(Color.gMuted)
                        BigButton("Экспорт резервной копии (JSON)", primary: false) {
                            doc = DataDocument(data: store.exportBackup()); docType = .json; docName = "gymtracker-backup-\(stamp)"; showExporter = true
                        }
                        BigButton("Импорт резервной копии", primary: false) { confirmImport = true }
                        BigButton("Экспорт истории в CSV", primary: false) {
                            doc = DataDocument(data: Data(store.csv().utf8)); docType = .commaSeparatedText; docName = "gymtracker-history-\(stamp)"; showExporter = true
                        }
                        BigButton("Удалить все данные", primary: false) { confirmDelete = true }
                    }
                }
                Text("GymTracker 1.0 · работает без интернета и регистрации").font(.system(size: 12)).foregroundStyle(Color.gMuted)
            }.padding(16)
        }
        .background(Color.gBg)
        .navigationTitle("Ещё")
        .fileExporter(isPresented: $showExporter, document: doc, contentType: docType, defaultFilename: docName) { result in
            if case .success = result { store.say("Файл сохранён") }
            if case .failure = result { store.say("Не удалось сохранить файл") }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json, .plainText, .data]) { result in
            if case .success(let url) = result {
                let ok = url.startAccessingSecurityScopedResource()
                defer { if ok { url.stopAccessingSecurityScopedResource() } }
                if let d = try? Data(contentsOf: url) { store.importBackup(d) } else { store.say("Не удалось открыть файл") }
            }
        }
        .alert("Импорт резервной копии", isPresented: $confirmImport) {
            Button("Выбрать файл", role: .destructive) { showImporter = true }
            Button("Отмена", role: .cancel) {}
        } message: { Text("Текущие данные приложения будут ЗАМЕНЕНЫ данными из выбранного файла. Рекомендуем сначала сделать экспорт.") }
        .alert("Удалить все данные?", isPresented: $confirmDelete) {
            Button("Удалить всё", role: .destructive) { store.deleteAllData() }
            Button("Отмена", role: .cancel) {}
        } message: { Text("Будут безвозвратно удалены история тренировок, шаблоны и свои упражнения. Это действие нельзя отменить.") }
    }

    private func link(_ title: String) -> some View {
        Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 54).background(Color.gCard2, in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Полный экран таймера отдыха: пресеты, своё время, пауза, +15 с, сброс.
struct TimerView: View {
    @Environment(Store.self) private var store
    @State private var minText = ""
    @State private var secText = ""
    private let presets: [(String, Int)] = [("30 с", 30), ("1:00", 60), ("1:30", 90), ("2:00", 120), ("3:00", 180), ("4:00", 240), ("5:00", 300)]

    var body: some View {
        let rest = store.rest
        ScrollView {
            VStack(spacing: 14) {
                Card {
                    VStack(spacing: 4) {
                        Text(title(rest.status)).font(.system(size: 14, weight: .bold)).foregroundStyle(rest.status == .finished ? Color.gGreen : Color.gRed)
                        TimelineView(.periodic(from: .now, by: 0.1)) { ctx in
                            let remaining = remainingFor(rest, ctx.date)
                            VStack(spacing: 8) {
                                Text(fmtDur(remaining)).font(.system(size: 80, weight: .black)).monospacedDigit()
                                    .foregroundStyle(rest.status == .finished ? Color.gGreen : Color.white).minimumScaleFactor(0.6)
                                if rest.totalSec > 0 && (rest.status == .running || rest.status == .paused) {
                                    ProgressView(value: min(max(remaining / rest.totalSec, 0), 1)).tint(Color.gRed)
                                }
                            }
                        }
                    }.frame(maxWidth: .infinity)
                }

                switch rest.status {
                case .idle:
                    BigButton("Старт", height: 64) { store.startRest(seconds: max(1, Int(rest.totalSec > 0 ? rest.totalSec : Double(store.db.settings.lastRestSec)))) }
                case .running:
                    HStack(spacing: 8) { BigButton("Пауза") { rest.pause() }; BigButton("+15 секунд", primary: false) { rest.add15() } }
                case .paused:
                    HStack(spacing: 8) { BigButton("Продолжить") { rest.resume() }; BigButton("+15 секунд", primary: false) { rest.add15() } }
                case .finished:
                    HStack(spacing: 8) { BigButton("Повторить") { store.startRest(seconds: max(15, Int(rest.totalSec))) }; BigButton("Закрыть", primary: false) { rest.stop() } }
                }
                if rest.status == .running || rest.status == .paused {
                    HStack(spacing: 8) { BigButton("Сброс", primary: false) { rest.reset() }; BigButton("Завершить отдых", primary: false) { rest.stop() } }
                }

                SectionTitle("Быстрый запуск")
                let rows = stride(from: 0, to: presets.count, by: 4).map { Array(presets[$0..<min($0 + 4, presets.count)]) }
                ForEach(0..<rows.count, id: \.self) { r in
                    HStack(spacing: 8) {
                        ForEach(rows[r], id: \.1) { p in BigButton(p.0, primary: false) { store.startRest(seconds: p.1) } }
                        if rows[r].count < 4 { ForEach(0..<(4 - rows[r].count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity, minHeight: 1) } }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Своё время").font(.system(size: 17, weight: .bold))
                        HStack(spacing: 8) { NumField(title: "мин", text: $minText, decimal: false); NumField(title: "сек", text: $secText, decimal: false) }
                        let total = (Int(minText) ?? 0) * 60 + (Int(secText) ?? 0)
                        BigButton("Запустить") { store.startRest(seconds: total) }.disabled(total <= 0)
                    }
                }
                Text("Время отдыха для каждого упражнения задаётся на экране упражнения.").font(.system(size: 13)).foregroundStyle(Color.gMuted)
            }.padding(16)
        }
        .background(Color.gBg)
        .navigationTitle("Таймер отдыха")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDone()
    }

    private func remainingFor(_ rest: RestTimer, _ now: Date) -> TimeInterval {
        switch rest.status {
        case .idle: return rest.totalSec > 0 ? rest.totalSec : Double(store.db.settings.lastRestSec)
        case .finished: return 0
        case .running: return rest.remaining(at: now) + 0.999
        case .paused: return rest.pausedRemaining
        }
    }
    private func title(_ s: RestTimer.Status) -> String {
        switch s { case .idle: return "ГОТОВ"; case .running: return "ОТДЫХ"; case .paused: return "ПАУЗА"; case .finished: return "ОТДЫХ ОКОНЧЕН" }
    }
}
