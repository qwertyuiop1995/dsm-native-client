import DsmLocalization
import SwiftUI

@main
struct DsmMobileApp: App {
    @State private var model = MobileAppModel()
    @State private var language = AppLanguageStore.shared

    var body: some Scene {
        WindowGroup {
            MobileRootView(model: model)
                .environment(language)
                .environment(\.locale, language.locale)
        }
    }
}
