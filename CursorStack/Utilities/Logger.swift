import Foundation
import os

enum CSLog {
    static let subsystem = "dev.jamesware.CursorStack"

    static let general = Logger(subsystem: subsystem, category: "general")
    static let ax = Logger(subsystem: subsystem, category: "accessibility")
    static let group = Logger(subsystem: subsystem, category: "group")
    static let attention = Logger(subsystem: subsystem, category: "attention")
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
