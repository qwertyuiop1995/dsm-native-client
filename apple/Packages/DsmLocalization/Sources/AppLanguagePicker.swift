import SwiftUI

public struct AppLanguagePicker: View {
    @Bindable private var store: AppLanguageStore

    public init(store: AppLanguageStore = .shared) {
        self.store = store
    }

    public var body: some View {
        Picker(store.string("settings.language.title"), selection: $store.selection) {
            Text(store.string("language.follow_system"))
                .tag(AppLanguageSelection.system)
            Text(store.string("language.english"))
                .tag(AppLanguageSelection.english)
            Text(store.string("language.simplified_chinese"))
                .tag(AppLanguageSelection.simplifiedChinese)
        }
        .accessibilityLabel(store.string("settings.language.title"))
    }
}
