import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// A block dragged inside Magpie (declared in Info.plist). The window's drop target doesn't
    /// accept it, so a card dropped on empty space is never saved as a new note.
    static let magpieBlock = UTType(exportedAs: "com.jleitaom.magpie.block")
}

extension UTType {
    /// A pinned pile's tab dragged along the top bar (declared in Info.plist). Its own type, so
    /// a tab dropped on the window is never saved as a note.
    static let magpiePile = UTType(exportedAs: "com.jleitaom.magpie.pile")
}

/// Moves the dragged pile's tab into the place of the tab under the pointer.
struct PinDrop: DropDelegate {
    let target: UUID
    let model: AppModel
    @Binding var dragging: UUID?
    @Binding var hovered: UUID?

    func validateDrop(info: DropInfo) -> Bool { dragging != nil && dragging != target }

    func dropEntered(info: DropInfo) { hovered = target }

    func dropExited(info: DropInfo) { if hovered == target { hovered = nil } }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            dragging = nil
            hovered = nil
        }
        guard let moving = dragging else { return false }
        return model.movePin(moving, onto: target)
    }
}

extension View {
    /// Drag this block onto another to put it in that place (S-066). Used by Gallery cards and Journal rows.
    func reorderable(_ block: Block, shown: [Block], model: AppModel, dragging: Binding<UUID?>, target: Binding<UUID?>) -> some View {
        let uid = block.uid
        return onDrag {
            dragging.wrappedValue = uid
            let provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: UTType.magpieBlock.identifier, visibility: .ownProcess) { done in
                done(Data(uid.uuidString.utf8), nil)
                return nil
            }
            return provider
        }
        .onDrop(of: [.magpieBlock], delegate: ReorderDrop(target: block.uid, shown: shown, model: model,
                                                          dragging: dragging, hovered: target))
    }
}

/// Moves the dragged block into the place of the one under the pointer.
struct ReorderDrop: DropDelegate {
    let target: UUID
    let shown: [Block]
    let model: AppModel
    @Binding var dragging: UUID?
    @Binding var hovered: UUID?

    func validateDrop(info: DropInfo) -> Bool { dragging != nil && dragging != target }

    func dropEntered(info: DropInfo) { hovered = target }

    func dropExited(info: DropInfo) { if hovered == target { hovered = nil } }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            dragging = nil
            hovered = nil
        }
        guard let moving = dragging, moving != target else { return false }
        model.reorder(moving, onto: target, shown: shown, in: model.scope)
        return true
    }
}
