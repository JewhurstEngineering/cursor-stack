import Foundation

@MainActor
final class Debouncer {
    private var workItem: DispatchWorkItem?
    var delay: TimeInterval

    init(delay: TimeInterval) {
        self.delay = delay
    }

    func run(_ block: @escaping () -> Void) {
        workItem?.cancel()
        let item = DispatchWorkItem(block: block)
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    func cancel() {
        workItem?.cancel()
        workItem = nil
    }
}
