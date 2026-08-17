import SwiftUI
import UniformTypeIdentifiers

struct WindowOrderDropDelegate: DropDelegate {
    let targetWindowID: UUID
    let groupID: UUID
    let app: ApplicationController
    @Binding var draggedWindowID: UUID?
    @Binding var targetedWindowID: UUID?

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.text])
    }

    func dropEntered(info: DropInfo) {
        targetedWindowID = targetWindowID
        guard let draggedWindowID,
              draggedWindowID != targetWindowID,
              let sourceGroup = app.groupManager.group(containing: draggedWindowID),
              sourceGroup.id == groupID,
              let group = app.groupManager.groups.first(where: { $0.id == groupID }),
              let targetIndex = group.windows.firstIndex(where: { $0.id == targetWindowID })
        else { return }

        app.groupManager.reorder(
            in: groupID,
            moving: draggedWindowID,
            to: targetIndex
        )
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if targetedWindowID == targetWindowID {
            targetedWindowID = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        let wasReorderedLocally = draggedWindowID.flatMap {
            app.groupManager.group(containing: $0)?.id
        } == groupID
        draggedWindowID = nil
        targetedWindowID = nil
        guard !wasReorderedLocally else { return true }

        let providers = info.itemProviders(for: [UTType.text])
        return app.handleTabDrop(
            providers: providers,
            onto: targetWindowID,
            in: groupID
        )
    }
}
