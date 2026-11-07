import SwiftUI
import UIKit

extension Color {
    static let gBg = Color(red: 0.055, green: 0.055, blue: 0.055)
    static let gCard = Color(white: 0.10)
    static let gCard2 = Color(white: 0.165)
    static let gRed = Color(red: 0.898, green: 0.224, blue: 0.208)
    static let gRedDark = Color(red: 0.557, green: 0.106, blue: 0.106)
    static let gMuted = Color(white: 0.62)
    static let gGreen = Color(red: 0.18, green: 0.62, blue: 0.31)
    static let gOrange = Color(red: 1.0, green: 0.65, blue: 0.15)
}

// MARK: - форматирование

let ruLocale = Locale(identifier: "ru_RU")

func fmtDur(_ t: TimeInterval) -> String {
    let s = Int(max(0, t)); let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
}
func fmtW(_ w: Double) -> String { w == w.rounded() ? String(Int(w)) : String(format: "%.1f", w) }
func fmtVol(_ v: Double) -> String {
    let f = NumberFormatter(); f.numberStyle = .decimal; f.groupingSeparator = " "; f.maximumFractionDigits = 0
    return f.string(from: NSNumber(value: v)) ?? String(Int(v))
}
func fmtDate(_ d: Date, _ pattern: String) -> String {
    let f = DateFormatter(); f.locale = ruLocale; f.dateFormat = pattern; return f.string(from: d)
}
func fmtDateTime(_ d: Date) -> String { fmtDate(d, "d MMM yyyy, HH:mm") }
func fmtShort(_ d: Date) -> String { fmtDate(d, "dd.MM") }
func parseWeight(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }

// MARK: - компоненты

struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder _ content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.gCard, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct BigButton: View {
    let title: String
    var primary = true
    var height: CGFloat = 54
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    init(_ title: String, primary: Bool = true, height: CGFloat = 54, action: @escaping () -> Void) {
        self.title = title; self.primary = primary; self.height = height; self.action = action
    }
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: height)
                .background(primary ? Color.gRed : Color.gCard2, in: RoundedRectangle(cornerRadius: 14))
                .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
    }
}

struct Chip: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .foregroundStyle(Color.white)
                .background(selected ? Color.gRed : Color.gCard2, in: Capsule())
        }.buttonStyle(.plain)
    }
}

struct ProgressRing: View {
    let percent: Int
    var diameter: CGFloat = 64
    var body: some View {
        ZStack {
            Circle().stroke(Color.gCard2, lineWidth: 6)
            Circle().trim(from: 0, to: CGFloat(min(max(percent, 0), 100)) / 100)
                .stroke(percent >= 100 ? Color.gGreen : Color.gRed, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(percent)%").font(.system(size: diameter / 4.4, weight: .bold))
        }
        .frame(width: diameter, height: diameter)
    }
}

struct Stat: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 20, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.system(size: 12)).foregroundStyle(Color.gMuted).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Поле ввода числа (вес или повторения).
struct NumField: View {
    let title: String
    @Binding var text: String
    var decimal = true
    var body: some View {
        VStack(spacing: 2) {
            Text(title).font(.system(size: 11)).foregroundStyle(Color.gMuted).lineLimit(1)
            TextField("0", text: $text)
                .keyboardType(decimal ? .decimalPad : .numberPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 20, weight: .semibold))
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Color.gCard2, in: RoundedRectangle(cornerRadius: 12))
        .onChange(of: text) { _, new in
            let filtered = decimal ? new.filter { $0.isNumber || $0 == "." || $0 == "," } : new.filter { $0.isNumber }
            let cut = String(filtered.prefix(6))
            if cut != new { text = cut }
        }
    }
}

extension View {
    /// Кнопка «Готово» над цифровой клавиатурой.
    func keyboardDone() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Готово") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
    }
}

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.system(size: 20, weight: .bold)).frame(maxWidth: .infinity, alignment: .leading) }
}

// MARK: - навигация

enum Route: Hashable {
    case workout(UUID)
    case run(UUID, Int)
    case exercise(UUID)
    case templates
    case template(UUID)
    case history
    case timer
    case progress(UUID?)
}

struct RouteView: View {
    let route: Route
    var body: some View {
        switch route {
        case .workout(let id): WorkoutView(workoutId: id)
        case .run(let id, let idx): RunView(workoutId: id, startIndex: idx)
        case .exercise(let id): ExerciseDetailView(exerciseId: id)
        case .templates: TemplatesView()
        case .template(let id): TemplateEditView(templateId: id)
        case .history: HistoryView()
        case .timer: TimerView()
        case .progress(let id): ProgressScreen(initial: id)
        }
    }
}
