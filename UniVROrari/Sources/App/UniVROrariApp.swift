import SwiftUI

@main
struct UniVROrariApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .task {
                    await model.bootstrap()
                }
        }
    }
}
