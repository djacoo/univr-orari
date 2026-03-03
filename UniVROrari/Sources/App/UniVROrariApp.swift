import SwiftUI
import CoreSpotlight
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    var model: AppModel? {
        didSet {
            if let action = pendingAction {
                model?.pendingShortcutAction = action
                pendingAction = nil
            }
        }
    }
    private var pendingAction: ShortcutAction?

    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let action: ShortcutAction
        switch shortcutItem.type {
        case "it.univr.orari.timetable": action = .openTimetable
        case "it.univr.orari.freeroom":  action = .findFreeRoom
        default:
            completionHandler(false)
            return
        }
        if let model { model.pendingShortcutAction = action } else { pendingAction = action }
        completionHandler(true)
    }
}

@main
struct UniVROrariApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .task { await model.bootstrap() }
                .onAppear { appDelegate.model = model }
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    guard
                        let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String
                    else { return }
                    let parts = id.split(separator: ":", maxSplits: 2)
                    guard parts.count == 3,
                          let date = DateHelpers.apiDateFormatter.date(from: String(parts[2]))
                    else { return }
                    Task { @MainActor in model.navigateToWeekContaining(date) }
                }
        }
    }
}
