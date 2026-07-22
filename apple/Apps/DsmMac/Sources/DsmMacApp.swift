import AppKit
import DsmCore
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
        case .download: operation = "下载"
        case .upload: operation = "上传"
        case .copy: operation = "复制"
        case .move: operation = "移动"
        case .delete: operation = "删除"
        case .restore: operation = "恢复"
        case .compress: operation = "压缩"
        case .extract: operation = "解压"
        }
        return task.state == .succeeded ? "\(operation)完成" : "\(operation)未完成"
    }

    private func notificationBody(for task: ActivityTask, profileName: String) -> String {
        if task.state == .succeeded {
            return "“\(task.displayName)”已在 \(profileName) 完成。"
        }
        let reason = task.failureMessage ?? "连接或权限出现问题"
        return "“\(task.displayName)”未完成：\(reason) 可在传输中心重试。"
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

    var body: some Scene {
        WindowGroup("app.window.title") {
            RootView(model: model)
                .task {
                    model.load()
                }
        }
        .defaultSize(width: 1_260, height: 780)
        .windowResizability(.contentMinSize)
    }
}
