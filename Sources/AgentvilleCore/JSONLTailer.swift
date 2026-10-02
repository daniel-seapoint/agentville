import Foundation

/// Follows an append-only JSONL file, returning only complete lines added since the last read.
public final class JSONLTailer {
    public let url: URL
    private var offset: UInt64
    private var carry = Data()
    private var skipPartialFirstLine: Bool

    /// - Parameter tailBytes: when set, start this many bytes before the current end of file
    ///   instead of at the beginning. The line that the start position lands in is discarded.
    public init(url: URL, tailBytes: UInt64? = nil) {
        self.url = url
        let size = Self.fileSize(url) ?? 0
        if let tailBytes, size > tailBytes {
            offset = size - tailBytes
            skipPartialFirstLine = true
        } else {
            offset = 0
            skipPartialFirstLine = false
        }
    }

    public func readNewLines() -> [Data] {
        guard let size = Self.fileSize(url) else { return [] }
        if size < offset {
            // File was truncated or replaced; start over.
            offset = 0
            carry.removeAll()
            skipPartialFirstLine = false
        }
        guard size > offset, let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: offset)) != nil,
              let chunk = try? handle.readToEnd(), !chunk.isEmpty else { return [] }
        offset += UInt64(chunk.count)
        carry.append(chunk)

        var lines: [Data] = []
        var start = carry.startIndex
        while let newline = carry[start...].firstIndex(of: 0x0A) {
            if skipPartialFirstLine {
                skipPartialFirstLine = false
            } else if newline > start {
                lines.append(carry.subdata(in: start..<newline))
            }
            start = carry.index(after: newline)
        }
        carry = carry.subdata(in: start..<carry.endIndex)
        return lines
    }

    static func fileSize(_ url: URL) -> UInt64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber else { return nil }
        return size.uint64Value
    }

    static func modificationDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}

func parseJSONObject(_ data: Data) -> [String: Any]? {
    (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}
