import Foundation
import Observation
import UserNotifications
import AudioToolbox
import UIKit

/// Единственный таймер отдыха. Время окончания хранится как Date, поэтому отсчёт не зависит от UI.
/// В фоне сигнал даёт локальное уведомление, запланированное на момент окончания.
@Observable
final class RestTimer {
    enum Status: String { case idle, running, paused, finished }

    var status: Status = .idle
    var totalSec: Double = 0
    var endDate: Date?
    var pausedRemaining: Double = 0

    @ObservationIgnored var soundOn = true
    @ObservationIgnored var vibrationOn = true
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private let center = UNUserNotificationCenter.current()
    @ObservationIgnored private let defaults = UserDefaults.standard
    private static let notifId = "gymtracker.rest"

    init() { restore() }

    func remaining(at now: Date = Date()) -> Double {
        switch status {
        case .running: return max(0, (endDate ?? now).timeIntervalSince(now))
        case .paused: return pausedRemaining
        default: return 0
        }
    }

    /// Запуск. Предыдущий отсчёт и его уведомление останавливаются — одновременно идёт только один таймер.
    func start(seconds: Int) {
        let s = Double(min(max(seconds, 1), 24 * 3600))
        cancelNotification()
        totalSec = s
        endDate = Date().addingTimeInterval(s)
        status = .running
        scheduleNotification()
        startTicker()
        persist()
    }

    func pause() {
        guard status == .running else { return }
        pausedRemaining = remaining()
        cancelNotification()
        stopTicker()
        endDate = nil
        status = .paused
        persist()
    }

    func resume() {
        guard status == .paused else { return }
        endDate = Date().addingTimeInterval(pausedRemaining)
        status = .running
        scheduleNotification()
        startTicker()
        persist()
    }

    /// «Сброс»: останавливает отсчёт, длительность сохраняется.
    func reset() {
        cancelNotification()
        stopTicker()
        endDate = nil
        status = .idle
        persist()
    }

    /// «Завершить» досрочно.
    func stop() {
        reset()
        totalSec = 0
        persist()
    }

    func add15() {
        switch status {
        case .running:
            endDate = (endDate ?? Date()).addingTimeInterval(15)
            totalSec += 15
            cancelNotification(); scheduleNotification()
            persist()
        case .paused:
            pausedRemaining += 15; totalSec += 15; persist()
        case .finished:
            start(seconds: 15)
        case .idle:
            totalSec += 15; persist()
        }
    }

    /// Вызывается при возврате в приложение.
    func sync() {
        if status == .running {
            if let e = endDate, Date() >= e {
                status = .finished
                stopTicker()
                persist()
            } else {
                startTicker()
            }
        }
    }

    // MARK: - внутреннее

    private func startTicker() {
        stopTicker()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func stopTicker() { ticker?.invalidate(); ticker = nil }

    private func tick() {
        guard status == .running, let e = endDate else { stopTicker(); return }
        if Date() >= e { finishInForeground() }
    }

    private func finishInForeground() {
        status = .finished
        stopTicker()
        cancelNotification()          // в активном приложении сигнал подаём сами
        persist()
        if soundOn { AudioServicesPlaySystemSound(1005) }
        if vibrationOn {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func scheduleNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Отдых окончен"
        content.body = "Пора на следующий подход"
        content.sound = soundOn ? .default : nil
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, remaining()), repeats: false)
        center.add(UNNotificationRequest(identifier: Self.notifId, content: content, trigger: trigger))
    }

    private func cancelNotification() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.notifId])
        center.removeDeliveredNotifications(withIdentifiers: [Self.notifId])
    }

    private func persist() {
        defaults.set(status.rawValue, forKey: "rest_status")
        defaults.set(totalSec, forKey: "rest_total")
        defaults.set(endDate?.timeIntervalSince1970 ?? 0, forKey: "rest_end")
        defaults.set(pausedRemaining, forKey: "rest_paused")
    }

    private func restore() {
        totalSec = defaults.double(forKey: "rest_total")
        pausedRemaining = defaults.double(forKey: "rest_paused")
        let end = defaults.double(forKey: "rest_end")
        let saved = Status(rawValue: defaults.string(forKey: "rest_status") ?? "idle") ?? .idle
        switch saved {
        case .running:
            if end > Date().timeIntervalSince1970 {
                endDate = Date(timeIntervalSince1970: end)
                status = .running
                startTicker()
            } else { status = .idle }
        case .paused: status = .paused
        default: status = .idle
        }
    }
}
