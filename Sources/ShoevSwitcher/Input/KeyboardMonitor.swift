import Carbon.HIToolbox
import CoreGraphics
import Foundation
import os

protocol KeyboardMonitorDelegate: AnyObject {
    func keyboardMonitorDidResetInput(_ monitor: KeyboardMonitor)
    func keyboardMonitor(_ monitor: KeyboardMonitor, keyDown event: CGEvent, text: String, keyCode: CGKeyCode) -> Bool
    func keyboardMonitor(_ monitor: KeyboardMonitor, flagsChanged event: CGEvent, keyCode: CGKeyCode)
}

final class KeyboardMonitor {
    weak var delegate: KeyboardMonitorDelegate?
    var mouseMovedHandler: ((CGPoint) -> Void)?
    var inputActivityHandler: (() -> Void)?

    private let logger = Logger(subsystem: "com.shoev.switcher", category: "KeyboardMonitor")
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var healthTimer: Timer?
    private var keyDownCountSinceTerminator = 0

    /// The event tap itself is the source of truth. On recent macOS versions the
    /// TCC preflight calls can lag behind the switches shown in System Settings.
    var hasRequiredPermissions: Bool {
        eventTap != nil
    }

    @discardableResult
    func requestRequiredPermissions() -> Bool {
        let canListen = CGPreflightListenEventAccess() || CGRequestListenEventAccess()
        let canPost = CGPreflightPostEventAccess() || CGRequestPostEventAccess()
        return canListen && canPost
    }

    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }
        let events: [CGEventType] = [
            .keyDown,
            .flagsChanged,
            .mouseMoved,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown
        ]
        let mask = events.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: keyboardEventCallback,
            userInfo: pointer
        ) else {
            logger.error(
                "Unable to create keyboard event tap. listen=\(CGPreflightListenEventAccess(), privacy: .public) post=\(CGPreflightPostEventAccess(), privacy: .public)"
            )
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        startHealthTimer()
        logger.info("Keyboard event tap started")
        return true
    }

    func stop() {
        healthTimer?.invalidate()
        healthTimer = nil
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        runLoopSource = nil
        eventTap = nil
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        if event.getIntegerValueField(.eventSourceUserData) == EventInjector.syntheticEventMarker {
            return Unmanaged.passUnretained(event)
        }

        if IsSecureEventInputEnabled() {
            delegate?.keyboardMonitorDidResetInput(self)
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            let location = event.location
            DispatchQueue.main.async { [weak self] in self?.mouseMovedHandler?(location) }
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            let location = event.location
            DispatchQueue.main.async { [weak self] in
                self?.mouseMovedHandler?(location)
                self?.inputActivityHandler?()
            }
            delegate?.keyboardMonitorDidResetInput(self)
        case .flagsChanged:
            DispatchQueue.main.async { [weak self] in self?.inputActivityHandler?() }
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            delegate?.keyboardMonitor(self, flagsChanged: event, keyCode: keyCode)
        case .keyDown:
            DispatchQueue.main.async { [weak self] in self?.inputActivityHandler?() }
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            let text = Self.unicodeString(from: event)
            keyDownCountSinceTerminator += 1
            if text == " " || text == "\n" || text == "\t" {
                logger.info("Terminator observed after \(self.keyDownCountSinceTerminator, privacy: .public) key-down events")
                keyDownCountSinceTerminator = 0
            }
            let suppress = delegate?.keyboardMonitor(
                self,
                keyDown: event,
                text: text,
                keyCode: keyCode
            ) ?? false
            if suppress { return nil }
        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }

    private func startHealthTimer() {
        healthTimer?.invalidate()
        healthTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let eventTap = self.eventTap,
                  !CGEvent.tapIsEnabled(tap: eventTap) else { return }
            self.logger.warning("Keyboard event tap was disabled; enabling it again")
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }

    private static func unicodeString(from event: CGEvent) -> String {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: buffer.count, actualStringLength: &length, unicodeString: &buffer)
        guard length > 0 else { return "" }
        return String(utf16CodeUnits: buffer, count: length)
    }
}

private let keyboardEventCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    return monitor.handle(type: type, event: event)
}
