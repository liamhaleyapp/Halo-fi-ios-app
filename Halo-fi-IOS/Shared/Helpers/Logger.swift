//
//  Logger.swift
//  Halo-fi-IOS
//
//  Centralized logging utility.
//  Replaces scattered print statements with consistent formatting.
//

import Foundation

enum Logger {

    // MARK: - Configuration

    /// Logging is enabled in DEBUG and TESTFLIGHT builds, disabled in App Store.
    #if DEBUG || TESTFLIGHT
    private static let isEnabled = true
    #else
    private static let isEnabled = false
    #endif

    // MARK: - Log Levels

    /// Informational log (blue circle emoji).
    /// Use for general flow information.
    static func info(_ message: String, file: String = #file) {
        log("🔵", message, file: file)
    }

    /// Success log (green checkmark emoji).
    /// Use when an operation completes successfully.
    static func success(_ message: String, file: String = #file) {
        log("✅", message, file: file)
    }

    /// Warning log (yellow warning emoji).
    /// Use for non-critical issues that should be noted.
    static func warning(_ message: String, file: String = #file) {
        log("⚠️", message, file: file)
    }

    /// Error log (red X emoji).
    /// Use for errors and failures.
    static func error(_ message: String, file: String = #file) {
        log("❌", message, file: file)
    }

    /// Debug log (purple circle emoji).
    /// Use for detailed debugging information.
    static func debug(_ message: String, file: String = #file) {
        log("🟣", message, file: file)
    }

    /// Sensitive log — DEBUG builds ONLY (compiled out of TestFlight and
    /// App Store). Use for anything containing user content: voice
    /// transcripts, agent responses, raw request/response bodies, or
    /// financial data. Keeps real conversations off the device console for
    /// TestFlight testers (F048). The message is autoclosed so it isn't
    /// even built outside DEBUG.
    static func sensitive(_ message: @autoclosure () -> String, file: String = #file) {
        #if DEBUG
        log("🔒", message(), file: file)
        #endif
    }

    // MARK: - Network Logging

    /// Log a network request.
    static func networkRequest(
        endpoint: String,
        method: String,
        hasToken: Bool = false,
        file: String = #file
    ) {
        guard isEnabled else { return }

        let fileName = extractFileName(from: file)
        var output = "🔵 \(fileName): Creating \(method) request"
        output += "\n   Endpoint: \(endpoint)"
        if hasToken {
            output += "\n   Token: ✅"
        }
        print(output)
    }

    /// Log a network response.
    static func networkResponse(
        statusCode: Int,
        dataSize: Int,
        file: String = #file
    ) {
        guard isEnabled else { return }

        let fileName = extractFileName(from: file)
        let emoji = (200..<300).contains(statusCode) ? "✅" : "❌"
        var output = "\(emoji) \(fileName): Response received"
        output += "\n   Status: \(statusCode)"
        output += "\n   Size: \(dataSize) bytes"
        print(output)
    }

    // MARK: - Private Helpers

    private static func log(_ emoji: String, _ message: String, file: String) {
        guard isEnabled else { return }

        let fileName = extractFileName(from: file)
        print("\(emoji) \(fileName): \(message)")
    }

    private static func extractFileName(from path: String) -> String {
        let url = URL(fileURLWithPath: path)
        return url.deletingPathExtension().lastPathComponent
    }
}

// MARK: - Convenience Extensions

extension Logger {

    /// Log an error with its localized description.
    static func error(_ error: Error, context: String? = nil, file: String = #file) {
        var message = error.localizedDescription
        if let context = context {
            message = "\(context): \(message)"
        }
        self.error(message, file: file)
    }

    /// Log the start of an async operation.
    static func startOperation(_ name: String, file: String = #file) {
        info("\(name)...", file: file)
    }

    /// Log the completion of an async operation.
    static func endOperation(_ name: String, success: Bool = true, file: String = #file) {
        if success {
            self.success("\(name) completed", file: file)
        } else {
            self.error("\(name) failed", file: file)
        }
    }
}
