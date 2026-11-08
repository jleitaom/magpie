import SwiftUI

/// The Settings window (Command-Comma). One tab per topic, at most about
/// six. Each tab is a grouped Form that sizes to its content, so the
/// window grows to fit and shows no scroll bar it does not need.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.settingsTab) {
            ForEach(SettingsTab.allCases) { tab in
                page(tab)
                    .tabItem { Label(tab.title, systemImage: tab.symbol) }
                    .tag(tab)
            }
        }
        .noInitialFocus()
    }

    @ViewBuilder
    private func page(_ tab: SettingsTab) -> some View {
        Form {
            switch tab {
            case .general: GeneralSettings()
            }
        }
        .formStyle(.grouped)
        .fitsContent()
        .frame(width: 520)
    }
}

/// The Settings tabs. Snapshot mode walks through every case.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        }
    }
}

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Section("Appearance") {
            Picker("Theme", selection: $model.appearance) {
                ForEach(AppearanceChoice.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Text("Magpie is designed dark. Switch any time with View → Appearance, or ⌃⌘T.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("Quick Save") {
            Picker("Shortcut", selection: $model.quickSaveShortcut) {
                ForEach(QuickSaveShortcut.allCases) { Text($0.label).tag($0) }
            }
            Text(model.quickSaveShortcutWorks
                 ? "Press it anywhere to save Safari’s front tab, or the clipboard."
                 : "Another app is using this shortcut. Pick a different one.")
                .font(.caption).foregroundStyle(model.quickSaveShortcutWorks ? .secondary : Color.orange)
        }
        Section("Screenshots") {
            Toggle("⌃⌥S saves part of the screen to the Inbox", isOn: $model.screenshotShortcutOn)
            Text("Its text is read on your Mac so search finds it. macOS asks for Screen Recording permission the first time.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("Library") {
            LabeledContent("Saved at", value: Store.url.deletingLastPathComponent().path)
        }
    }
}
