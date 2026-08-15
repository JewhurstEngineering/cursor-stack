import AppKit
import Foundation

@MainActor
final class HotKeyManager {
    var onNextTab: (() -> Void)?
    var onPreviousTab: (() -> Void)?
    var onNumberedTab: ((Int) -> Void)?

    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    func update(settings: AppSettings) {
        self.settings = settings
    }

    func start() {
        stop()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handle(event) == true {
                return nil
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            _ = self?.handle(event)
        }
    }

    func stop() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        localMonitor = nil
        globalMonitor = nil
    }

    private func handle(_ event: NSEvent) -> Bool {
        if matches(event, settings.nextTabHotKey) {
            onNextTab?()
            return true
        }
        if matches(event, settings.previousTabHotKey) {
            onPreviousTab?()
            return true
        }
        for number in 1...9 {
            if matches(event, .numberedTab(number)) {
                onNumberedTab?(number)
                return true
            }
        }
        return false
    }

    private func matches(_ event: NSEvent, _ spec: HotKeySpec) -> Bool {
        guard event.keyCode == spec.keyCode else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasControl = flags.contains(.control)
        let hasOption = flags.contains(.option)
        let hasShift = flags.contains(.shift)
        let hasCommand = flags.contains(.command)
        return hasControl == spec.control
            && hasOption == spec.option
            && hasShift == spec.shift
            && hasCommand == spec.command
    }
}
