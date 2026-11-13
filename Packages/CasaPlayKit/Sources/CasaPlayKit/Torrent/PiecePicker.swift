// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Chooses which piece to fetch next. While streaming, the order is:
//   1. pieces the player is waiting for right now (the read position)
//   2. the start and end of the file, where MP4/MOV keep their index ("moov")
//   3. read-ahead after the playback position, nearest first
//   4. the rest of the selected file, rarest first among peers
// Pieces that take too long are offered to another source ("endgame").

import Foundation

struct PiecePicker {
    let metainfo: TorrentMetainfo
    private(set) var wanted: Set<Int> = []
    private(set) var focus: Int?
    private var urgent: Set<Int> = []
    private var edges: [Int] = []
    private var inFlight: [Int: Date] = [:]
    var availability: [Int]
    var readAhead: Int64
    var stallTimeout: TimeInterval = 12

    init(metainfo: TorrentMetainfo, readAhead: Int64) {
        self.metainfo = metainfo
        self.readAhead = readAhead
        self.availability = Array(repeating: 0, count: metainfo.pieceCount)
    }

    mutating func select(file: TorrentFile) {
        guard let range = metainfo.pieces(of: file) else { wanted = []; return }
        wanted = Set(range)
        // Headers and trailers: first two and last two pieces of the file.
        edges = Array(Set([range.lowerBound, min(range.lowerBound + 1, range.upperBound),
                           max(range.upperBound - 1, range.lowerBound), range.upperBound])).sorted()
        focus = range.lowerBound
    }

    /// The player is reading at this torrent offset.
    mutating func setFocus(offset: Int64) {
        guard let range = metainfo.pieces(covering: offset..<(offset + 1)) else { return }
        focus = range.lowerBound
    }

    mutating func markUrgent(_ pieces: ClosedRange<Int>) { urgent.formUnion(pieces) }

    mutating func done(_ piece: Int) {
        inFlight[piece] = nil
        urgent.remove(piece)
    }

    mutating func release(_ piece: Int) { inFlight[piece] = nil }

    /// Next piece for a source that can supply `canSupply`. `have` is the verified set.
    mutating func next(have: [Bool], canSupply: (Int) -> Bool, now: Date = Date()) -> Int? {
        func free(_ i: Int) -> Bool {
            guard !have[i], wanted.contains(i), canSupply(i) else { return false }
            if let started = inFlight[i] { return now.timeIntervalSince(started) > stallTimeout }
            return true
        }
        let start = focus ?? wanted.min() ?? 0
        var candidates: [Int] = urgent.sorted { abs($0 - start) < abs($1 - start) }.filter(free)
        if candidates.isEmpty { candidates = edges.filter(free) }
        if candidates.isEmpty {
            let window = Int(readAhead / Int64(metainfo.pieceLength)) + 1
            candidates = (start..<min(start + window, metainfo.pieceCount)).filter(free)
        }
        if candidates.isEmpty {
            candidates = wanted.filter(free).sorted { a, b in
                // Rarest first among peers; then nearest after the playback position.
                if availability[a] != availability[b], availability[a] > 0, availability[b] > 0 {
                    return availability[a] < availability[b]
                }
                let da = a >= start ? a - start : a + metainfo.pieceCount
                let db = b >= start ? b - start : b + metainfo.pieceCount
                return da < db
            }
        }
        guard let pick = candidates.first else { return nil }
        inFlight[pick] = now
        return pick
    }

    func isComplete(have: [Bool]) -> Bool { wanted.allSatisfy { have[$0] } }
}
