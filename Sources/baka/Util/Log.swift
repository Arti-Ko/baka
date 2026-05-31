import Foundation
import os

/// Lightweight category-based logging built on `os.Logger`.
/// Centralizes the subsystem so every log line is filterable in Console.app.
enum Log {
    private static let subsystem = "com.baka.app"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let wallpaper = Logger(subsystem: subsystem, category: "wallpaper")
    static let power = Logger(subsystem: subsystem, category: "power")
    static let screens = Logger(subsystem: subsystem, category: "screens")
    static let library = Logger(subsystem: subsystem, category: "library")
    static let workshop = Logger(subsystem: subsystem, category: "workshop")
}
