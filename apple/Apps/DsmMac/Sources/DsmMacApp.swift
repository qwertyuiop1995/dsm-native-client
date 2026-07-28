import AppKit
import DsmCore
import DsmLocalization
import Foundation
import SwiftUI
import UserNotifications

@MainActor
protocol TransferNotifying: AnyObject {
    func prepareAuthorization()
    func notify(task: ActivityTask, profileName: String)
}

@MainActor
final class NoopTransferNotifier: TransferNotifying {
    func prepareAuthorization() {}
    func notify(task: ActivityTask, profileName: String) {}
}

@MainActor
enum TransferNotifierFactory {
    static func makeDefault() -> any TransferNotifying {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil {
            return NoopTransferNotifier()
        }
        return SystemTransferNotifier.shared
    }
}

@MainActor
final class SystemTransferNotifier: TransferNotifying {
    static let shared = SystemTransferNotifier()

    private let center: UNUserNotificationCenter
    private var isPreparingAuthorization = false

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func prepareAuthorization() {
        guard !Self.isRunningTests, !isPreparingAuthorization else { return }
        isPreparingAuthorization = true
        Task {
            defer { isPreparingAuthorization = false }
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .notDetermined else { return }
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    func notify(task: ActivityTask, profileName: String) {
        guard !Self.isRunningTests,
              task.state == .succeeded || task.state == .failed else {
            return
        }
        Task {
            var settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) == true
                guard granted else { return }
                settings = await center.notificationSettings()
            }
            guard settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional else { return }

            let content = UNMutableNotificationContent()
            content.title = notificationTitle(for: task)
            content.body = notificationBody(for: task, profileName: profileName)
            content.sound = .default
            content.threadIdentifier = "transfer.\(task.kind.rawValue)"
            let request = UNNotificationRequest(
                identifier: "transfer.\(task.id.uuidString).\(task.state.rawValue)",
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
    }

    private func notificationTitle(for task: ActivityTask) -> String {
        let operation: String
        switch task.kind {
        case .download: operation = L10n.string("ui.4673a23061656125")
        case .upload: operation = L10n.string("ui.9e07e3c0532d4976")
        case .copy: operation = L10n.string("ui.63d90d977348ab1f")
        case .move: operation = L10n.string("ui.fc6bb436b8caf08b")
        case .delete: operation = L10n.string("ui.2f9daa828907b93f")
        case .restore: operation = L10n.string("ui.e0534b8a4e46a0cb")
        case .compress: operation = L10n.string("ui.a22879cda61a8da0")
        case .extract: operation = L10n.string("ui.a147ebf3581ab1ee")
        }
        return task.state == .succeeded
            ? L10n.string("operation.completed", operation)
            : L10n.string("operation.not_completed", operation)
    }

    private func notificationBody(for task: ActivityTask, profileName: String) -> String {
        if task.state == .succeeded {
            return L10n.string("ui.3175795e4bb280b2", String(describing: task.displayName), String(describing: profileName))
        }
        let reason = task.failureMessage ?? L10n.string("ui.954110b2ccd1bacb")
        return L10n.string("ui.3721cf05827b270f", String(describing: task.displayName), String(describing: reason))
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // App 在前台活动时，通知全部通过 App 内内置悬浮 Toast 展示，取消系统右上角弹出 Banner 打扰
        [.sound]
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // 自动解除所有附着在窗口上的 Modal Sheet 或弹窗，确保 App 能响应 ⌘Q 和 Dock 菜单退出
        for window in NSApp.windows {
            if let sheet = window.attachedSheet {
                window.endSheet(sheet)
                sheet.orderOut(nil)
            }
        }
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct DsmMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @State private var language = AppLanguageStore.shared

    var body: some Scene {
        WindowGroup(language.string("app.name")) {
            RootView(model: model)
                .environment(language)
                .environment(\.locale, language.locale)
                .task {
                    model.load()
                }
        }
        .defaultSize(width: 1_260, height: 780)
        .windowResizability(.contentMinSize)
    }
}
