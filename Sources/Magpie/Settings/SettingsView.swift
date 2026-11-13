import MagpieKit
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
            case .shortcuts: ShortcutSettings()
            }
        }
        .formStyle(.grouped)
        .fitsContent(max: Metric.settingsMaxHeight)
        .frame(width: 520)
    }
}

/// The Settings tabs. Snapshot mode walks through every case.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general, shortcuts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .shortcuts: "Shortcuts"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .shortcuts: "command"
        }
    }
}

/// Appearance, new collections, Rediscover and the library (S-053).
struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @ObservedObject private var updater = Updater.shared

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
        Section("Rediscover") {
            Toggle("Show today’s count on the Dock icon", isOn: $model.rediscoverDockBadge)
            Text("A small number on Magpie’s icon: old saves waiting in today’s Rediscover.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("Library") {
            LabeledContent("Saved at") {
                HStack {
                    Text(Store.url.deletingLastPathComponent().path).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Store.url]) }
                }
            }
            LabeledContent("Back up") {
                Button("Export Library…") { model.chooseExportFolder() }
            }
        }
        Section("Updates") {
            Toggle("Check for updates automatically",
                   isOn: Binding(get: { updater.automaticallyChecks }, set: { updater.automaticallyChecks = $0 }))
                .disabled(!updater.isAvailable)
            LabeledContent {
                Button("Check Now") { updater.checkForUpdates() }
                    .disabled(!updater.canCheck)
            } label: {
                Text(updater.isAvailable ? "Once a day, from Magpie’s releases on GitHub. Nothing else is sent."
                                         : "Updates are off while Magpie uses a test library.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// The global shortcuts, and a card of the keys used inside Magpie (S-053).
struct ShortcutSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Section("Anywhere on your Mac") {
            Picker("Quick Save", selection: $model.quickSaveShortcut) {
                ForEach(QuickSaveShortcut.allCases) { Text($0.label).tag($0) }
            }
            Toggle("⌃⌥S saves a screenshot to the Inbox", isOn: $model.screenshotShortcutOn)
            Text(model.quickSaveShortcutWorks
                 ? "Quick Save saves Safari’s front tab, or the clipboard. Screenshots ask macOS for Screen Recording the first time."
                 : "Another app is using the Quick Save shortcut. Pick a different one.")
                .font(.caption).foregroundStyle(model.quickSaveShortcutWorks ? .secondary : Color.orange)
        }
        Section("Keys inside Magpie") {
            keys("Sort Inbox", "M move · D done · → skip · ⌫ delete · R rename")
            keys("Rediscover", "K keep · A archive · → skip · ↩ open")
            keys("Gallery, Journal", "arrows move · Space Quick Look · ↩ open · ⌫ delete · T tag")
            keys("Lucky Dip", "⌘R spin · ⌘↩ start or finish · ⌥⌘⌫ not today")
            keys("Anywhere in the window", "⌘F search · ⌘1–⌘7 places · ⌘K collections · ⇧⌘V paste")
        }
    }

    private func keys(_ place: String, _ list: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(place)
            Text(list).font(.callout).foregroundStyle(.secondary)
        }
    }
}
