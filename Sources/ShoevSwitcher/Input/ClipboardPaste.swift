import AppKit
import Carbon.HIToolbox
import Darwin
import OSLog

/// Cmd+V carries no layout-dependent Unicode key (in particular no A/Ф).
/// The two products share a non-blocking lease so they cannot race over pasteboard.
final class ClipboardPaste {
    static let shared = ClipboardPaste()
    private var pending: Timer?
    private let logger = Logger(subsystem: "com.shoev.systems", category: "paste")

    func paste(_ text: String, into element: AXUIElement, marker: Int64,
               validate: () -> Bool, applied: @escaping () -> Bool,
               completion: @escaping (Bool) -> Void = { _ in }) -> Bool {
        var pid: pid_t = 0
        guard pending == nil, !text.isEmpty, text.utf16.count <= 16_384,
              !IsSecureEventInputEnabled(), CGPreflightPostEventAccess(),
              AXUIElementGetPid(element, &pid) == .success,
              pid > 0, pid != getpid(),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let lease = ClipboardLease.acquire(),
              let snapshot = PasteboardSnapshot.capture(.general),
              let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false),
              validate(), !IsSecureEventInputEnabled(),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              NSPasteboard.general.changeCount == snapshot.changeCount else { return false }
        let board = NSPasteboard.general
        board.clearContents()
        guard board.setString(text, forType: .string) else {
            _ = snapshot.restore(board, ifOwned: board.changeCount)
            return false
        }
        let ownedCount = board.changeCount
        // A paste is addressed to the checked process, not whichever window
        // becomes active while the event travels through the WindowServer.
        for event in [down, up] {
            event.flags = .maskCommand
            event.setIntegerValueField(.eventSourceUserData, value: marker)
            event.postToPid(pid)
        }
        // Verification is asynchronous: waiting inside a session tap can block
        // the application's event delivery. Never replay the physical delimiter.
        // Keep the inserted clipboard until acknowledged, otherwise a late paste
        // could insert the OLD clipboard. New user copies always take precedence.
        var checks = 0
        pending = Timer.scheduledTimer(withTimeInterval: 0.025, repeats: true) { [weak self, lease] timer in
            guard let self else { timer.invalidate(); return }
            checks += 1
            if board.changeCount != ownedCount {
                timer.invalidate(); self.pending = nil
                completion(false)
                lease.release()
                return
            }
            if applied() || NSRunningApplication(processIdentifier: pid) == nil {
                let verified = NSRunningApplication(processIdentifier: pid) != nil
                _ = snapshot.restore(board, ifOwned: ownedCount)
                timer.invalidate(); self.pending = nil
                self.logger.info("Paste transaction acknowledged=\(verified)")
                completion(verified)
                lease.release()
            } else {
                // After the initial renderer delay, avoid continuous polling.
                if checks >= 10 { timer.fireDate = Date(timeIntervalSinceNow: 0.25) }
            }
        }
        logger.info("Paste transaction posted")
        return true
    }
}

struct PasteboardSnapshot {
    let changeCount: Int
    let items: [[NSPasteboard.PasteboardType: Data]]

    static func capture(_ board: NSPasteboard) -> PasteboardSnapshot? {
        let count = board.changeCount
        let originals = board.pasteboardItems ?? []
        guard originals.count <= 16 else { return nil }
        var items: [[NSPasteboard.PasteboardType: Data]] = []
        var bytes = 0
        for item in originals {
            guard item.types.count <= 64 else { return nil }
            var values: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                // Do not destroy promised or unreadable representations.
                guard let data = item.data(forType: type) else { return nil }
                bytes += data.count
                guard bytes <= 8 * 1024 * 1024 else { return nil }
                values[type] = data
            }
            items.append(values)
        }
        guard board.changeCount == count else { return nil }
        return PasteboardSnapshot(changeCount: count, items: items)
    }

    @discardableResult
    func restore(_ board: NSPasteboard, ifOwned count: Int) -> Bool {
        guard board.changeCount == count else { return false }
        let copies = items.map { values -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in values { item.setData(data, forType: type) }
            return item
        }
        board.clearContents()
        return copies.isEmpty || board.writeObjects(copies)
    }
}

private final class ClipboardLease {
    private var descriptor: Int32
    private init(_ descriptor: Int32) { self.descriptor = descriptor }

    static func acquire() -> ClipboardLease? {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.shoev.systems", isDirectory: true)
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { return nil }
        let path = directory.appendingPathComponent("clipboard.lock").path
        let fd = open(path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { return nil }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { close(fd); return nil }
        return ClipboardLease(fd)
    }

    func release() {
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN)
        close(descriptor)
        descriptor = -1
    }
    deinit { release() }
}
