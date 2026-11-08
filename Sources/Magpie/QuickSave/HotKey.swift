import Carbon.HIToolbox

/// A system-wide keyboard shortcut (Carbon `RegisterEventHotKey`, so it needs no permission).
/// Registered on init, unregistered on deinit. The same approach as Gutter's.
final class HotKey {
    private let id: UInt32
    private let action: () -> Void
    // Only touched on the main thread; `nonisolated(unsafe)` lets the nonisolated deinit release them.
    nonisolated(unsafe) private var hotKeyRef: EventHotKeyRef?
    nonisolated(unsafe) private var handlerRef: EventHandlerRef?

    /// Fails when the shortcut can't be registered, e.g. another app holds it exclusively.
    init?(id: UInt32, keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.id = id
        self.action = action

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var pressed = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            // Carbon delivers hot key events on the main thread.
            return MainActor.assumeIsolated {
                let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
                guard pressed.id == hotKey.id else { return OSStatus(eventNotHandledErr) }
                hotKey.action()
                return noErr
            }
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)

        let hotKeyID = EventHotKeyID(signature: OSType(0x4D47_5049), id: id) // "MGPI"
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(),
                                         OptionBits(kEventHotKeyExclusive), &hotKeyRef)
        guard status == noErr else {
            NSLog("Magpie: couldn't register the Quick Save shortcut (\(status))")
            return nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}

/// The Quick Save shortcut choices (Settings → General).
enum QuickSaveShortcut: String, CaseIterable, Identifiable {
    case controlOptionSpace, controlOptionM, optionCommandSpace, off

    var id: String { rawValue }

    var label: String {
        switch self {
        case .controlOptionSpace: "⌃⌥Space"
        case .controlOptionM: "⌃⌥M"
        case .optionCommandSpace: "⌥⌘Space"
        case .off: "Off"
        }
    }

    /// Carbon key code and modifiers, or nil for Off.
    var carbon: (keyCode: UInt32, modifiers: UInt32)? {
        switch self {
        case .controlOptionSpace: (UInt32(kVK_Space), UInt32(controlKey | optionKey))
        case .controlOptionM: (UInt32(kVK_ANSI_M), UInt32(controlKey | optionKey))
        case .optionCommandSpace: (UInt32(kVK_Space), UInt32(optionKey | cmdKey))
        case .off: nil
        }
    }
}
