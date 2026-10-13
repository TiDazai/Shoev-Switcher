import ApplicationServices
import Foundation

enum TextSelectionTransport: Equatable {
    case range
    case markers
}

/// Coordinates inside a bounded paragraph are translated back to document
/// positions. Marker bytes are opaque: only the editor converts its markers.
struct AccessibilityTextSelection {
    let access: AccessibilityAccess
    var deadline: TimeInterval = .infinity
    static let maximumContextLength = 16_384

    func markerIndex(_ marker: CFTypeRef, in element: AXUIElement) -> Int? {
        guard ProcessInfo.processInfo.systemUptime < deadline,
              CFGetTypeID(marker) == AXTextMarkerGetTypeID(),
              let value = access.parameter(element, kAXIndexForTextMarkerParameterizedAttribute as String, marker),
              CFGetTypeID(value) == CFNumberGetTypeID(), let number = value as? NSNumber else { return nil }
        let index = number.intValue
        guard index >= 0, number == NSNumber(value: index) else { return nil }
        return index
    }

    func markerRange(_ raw: CFTypeRef, in element: AXUIElement) -> CFRange? {
        guard CFGetTypeID(raw) == AXTextMarkerRangeGetTypeID() else { return nil }
        let markers = raw as! AXTextMarkerRange
        let start = AXTextMarkerRangeCopyStartMarker(markers)
        let end = AXTextMarkerRangeCopyEndMarker(markers)
        guard let first = markerIndex(start, in: element), let last = markerIndex(end, in: element),
              last >= first else { return nil }
        return CFRange(location: first, length: last - first)
    }

    func markers(for range: CFRange, in element: AXUIElement) -> AXTextMarkerRange? {
        guard range.location >= 0, range.length >= 0, range.length <= Int.max - range.location,
              let start = access.parameter(element, kAXTextMarkerForIndexParameterizedAttribute as String, NSNumber(value: range.location)),
              let end = access.parameter(element, kAXTextMarkerForIndexParameterizedAttribute as String, NSNumber(value: range.location + range.length)),
              markerIndex(start, in: element) == range.location,
              markerIndex(end, in: element) == range.location + range.length else { return nil }
        return AXTextMarkerRangeCreate(kCFAllocatorDefault, start as! AXTextMarker, end as! AXTextMarker)
    }

    func readMarkerContext(in element: AXUIElement) -> CaretContext? {
        guard ProcessInfo.processInfo.systemUptime < deadline,
              let selected = access.copy(element, kAXSelectedTextMarkerRangeAttribute as String),
              let selection = markerRange(selected, in: element),
              selection.length <= Self.maximumContextLength else { return nil }
        let selectedMarkers = selected as! AXTextMarkerRange
        let caret = AXTextMarkerRangeCopyStartMarker(selectedMarkers)
        // Do not request an entire long document on every keystroke. A paragraph
        // stays stable across word replacement, unlike a soft-wrapped line.
        guard ProcessInfo.processInfo.systemUptime < deadline else { return nil }
        var scope = access.parameter(element, kAXParagraphTextMarkerRangeForTextMarkerParameterizedAttribute as String, caret)
        if scope == nil, let first = access.copy(element, kAXStartTextMarkerAttribute as String),
           let last = access.copy(element, kAXEndTextMarkerAttribute as String),
           let firstIndex = markerIndex(first, in: element), let lastIndex = markerIndex(last, in: element),
           lastIndex >= firstIndex, lastIndex - firstIndex <= Self.maximumContextLength {
            scope = AXTextMarkerRangeCreate(kCFAllocatorDefault, first as! AXTextMarker, last as! AXTextMarker)
        }
        guard let scope, let bounds = markerRange(scope, in: element),
              bounds.length <= Self.maximumContextLength,
              selection.location >= bounds.location,
              selection.location - bounds.location <= bounds.length,
              selection.length <= bounds.length - (selection.location - bounds.location),
              ProcessInfo.processInfo.systemUptime < deadline,
              let text = access.parameter(element, kAXStringForTextMarkerRangeParameterizedAttribute as String, scope) as? String,
              text.utf16.count == bounds.length,
              var context = VerifiedCaretContextReader.context(element: element, text: text,
                  range: CFRange(location: selection.location - bounds.location, length: selection.length)) else { return nil }
        context.textOffset = bounds.location
        context.selectionTransport = .markers
        return context
    }

    func canSet(_ context: TextReplacementContext) -> Bool {
        access.writable(context.element, context.selectionTransport == .markers
            ? kAXSelectedTextMarkerRangeAttribute as String : kAXSelectedTextRangeAttribute)
    }

    func set(_ range: CFRange, in context: TextReplacementContext) -> Bool {
        guard range.location >= 0, range.length >= 0,
              range.location <= context.text.utf16.count,
              range.length <= context.text.utf16.count - range.location,
              context.textOffset >= 0, range.location <= Int.max - context.textOffset else { return false }
        if context.selectionTransport == .markers {
            guard let value = markers(for: CFRange(location: context.textOffset + range.location, length: range.length), in: context.element) else { return false }
            return access.set(context.element, kAXSelectedTextMarkerRangeAttribute as String, value) == .success
        }
        var nativeRange = range
        guard let value = AXValueCreate(.cfRange, &nativeRange) else { return false }
        return access.set(context.element, kAXSelectedTextRangeAttribute, value) == .success
    }
}
