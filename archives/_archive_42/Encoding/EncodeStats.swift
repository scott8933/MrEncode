import Foundation

// MARK: - Bucketing helpers (resolution / fps / crf, plus optional HDR/SDR suffix)
enum Buckets {
    static func resBucket(_ w: Int, _ h: Int) -> String {
        let long = max(w, h)
        switch long {
        case ..<1280:       return "subHD"   // ≤720p
        case 1280..<1921:   return "1080p"
        case 1921..<4097:   return "4K"
        case 4097..<8193:   return "8K"
        default:            return "gt8K"
        }
    }
    static func fpsBucket(_ fps: Double) -> Int {
        let targets = [23.976, 24, 25, 29.97, 30, 50, 59.94, 60]
        let best = targets.min { abs($0 - fps) < abs($1 - fps) } ?? 30
        return Int(round(best))
    }
    static func crfBucket(_ crf: Int) -> Int {
        let step = 3
        return Int(round(Double(crf) / Double(step))) * step
    }
    static func hdrSuffix(_ isHDR: Bool?) -> String {
        guard let isHDR else { return "" }
        return isHDR ? "|hdr" : "|sdr"
    }
}

// MARK: - Data Models

struct EncodeSample: Codable {
    let ts: Date
    let runMode: String            // "local" / "remote" (or others later)
    let resBucket: String          // e.g., "1080p", "4K"
    let fpsBucket: Int             // 24/25/30/60 …
    let crfBucket: Int
    let outW: Int
    let outH: Int
    let fps: Double
    let durationSec: Double
    let wallTimeSec: Double
    let mpPerSec: Double           // effective throughput in MP/s
}

struct BucketStats: Codable {
    // Encode-time model
    var emaMPps: Double            // exponential moving average of MP/s
    var count: Int
    var lastTS: Date

    // File-size model (normalized to CRF 18)
    var emaBpppf18: Double?
    var bpppfCount: Int = 0
}

struct EncodeStatsPayload: Codable {
    var version: Int = 1
    var buckets: [String: BucketStats] = [:]   // key = composite bucket id
    var overallEMA: Double? = nil              // global fallback MP/s
    var overallCount: Int = 0
    var lastWrite: Date = .init()
}

// MARK: - Store

final class EncodeStatsStore {
    static let shared = EncodeStatsStore()

    // Smoothing factor for EMA (higher -> more weight to recent runs)
    private let alpha = 0.5
    private let queue = DispatchQueue(label: "mrhevc.encodestats", qos: .utility)

    private var payload = EncodeStatsPayload()

    private init() { load() }

    // MARK: Persistence

    private var statsURL: URL {
        let fm = FileManager.default
        let base = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = (base ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent("MrHEVC", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("EncodeStats.json")
    }

    private func load() {
        let url = statsURL
        guard let data = try? Data(contentsOf: url) else { return }
        if let decoded = try? JSONDecoder().decode(EncodeStatsPayload.self, from: data) {
            payload = decoded
        }
    }

    private func save() {
        payload.lastWrite = Date()
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: statsURL, options: .atomic)
        }
    }

    // MARK: Keys

    static func makeKey(runMode: String, res: String, fps: Int, crf: Int, isHDR: Bool? = nil) -> String {
        "\(runMode)|\(res)|fps\(fps)|crf\(crf)\(Buckets.hdrSuffix(isHDR))"
    }

    // MARK: Public: encode-time (MP/s)

    func record(sample: EncodeSample) {
        queue.async {
            let key = Self.makeKey(runMode: sample.runMode,
                                   res: sample.resBucket,
                                   fps: sample.fpsBucket,
                                   crf: sample.crfBucket)

            if var s = self.payload.buckets[key] {
                s.emaMPps = self.alpha * sample.mpPerSec + (1 - self.alpha) * s.emaMPps
                s.count += 1
                s.lastTS = Date()
                self.payload.buckets[key] = s
            } else {
                self.payload.buckets[key] = BucketStats(
                    emaMPps: sample.mpPerSec,
                    count: 1,
                    lastTS: Date(),
                    emaBpppf18: nil,
                    bpppfCount: 0
                )
            }

            if let ema = self.payload.overallEMA {
                self.payload.overallEMA = self.alpha * sample.mpPerSec + (1 - self.alpha) * ema
            } else {
                self.payload.overallEMA = sample.mpPerSec
            }
            self.payload.overallCount += 1
            self.save()
        }
    }

    func averageMPps(runMode: String, outW: Int, outH: Int, fps: Double, crf: Int) -> Double? {
        let key = Self.makeKey(runMode: runMode,
                               res: Buckets.resBucket(outW, outH),
                               fps: Buckets.fpsBucket(fps),
                               crf: Buckets.crfBucket(crf))
        return queue.sync {
            if let s = payload.buckets[key] { return s.emaMPps }
            return payload.overallEMA
        }
    }

    // MARK: Public: size model (bpppf@CRF18)

    func recordBpppf18(runMode: String,
                       outW: Int, outH: Int,
                       fps: Double,
                       crf: Int,
                       isHDR: Bool,
                       bpppf18: Double) {
        let key = Self.makeKey(runMode: runMode,
                               res: Buckets.resBucket(outW, outH),
                               fps: Buckets.fpsBucket(fps),
                               crf: Buckets.crfBucket(crf),
                               isHDR: isHDR)

        queue.async {
            var s = self.payload.buckets[key] ?? BucketStats(
                emaMPps: self.payload.overallEMA ?? 15,
                count: 0,
                lastTS: Date(),
                emaBpppf18: nil,
                bpppfCount: 0
            )
            if let old = s.emaBpppf18 {
                s.emaBpppf18 = self.alpha * bpppf18 + (1 - self.alpha) * old
            } else {
                s.emaBpppf18 = bpppf18
            }
            s.bpppfCount += 1
            s.lastTS = Date()
            self.payload.buckets[key] = s
            self.save()
        }
    }

    func averageBpppf18(runMode: String,
                        outW: Int, outH: Int,
                        fps: Double,
                        crf: Int,
                        isHDR: Bool) -> Double? {
        let key = Self.makeKey(runMode: runMode,
                               res: Buckets.resBucket(outW, outH),
                               fps: Buckets.fpsBucket(fps),
                               crf: Buckets.crfBucket(crf),
                               isHDR: isHDR)
        return queue.sync { payload.buckets[key]?.emaBpppf18 }
    }

    // MARK: Convenience

    static func makeSample(runMode: String,
                           outW: Int, outH: Int,
                           fps: Double,
                           durationSec: Double,
                           wallTimeSec: Double,
                           crf: Int) -> EncodeSample {
        let mpTotal = Double(outW * outH) * fps * durationSec / 1_000_000.0
        let mpPerSec = (mpTotal > 0 && wallTimeSec > 0) ? (mpTotal / wallTimeSec) : 0
        return EncodeSample(
            ts: Date(),
            runMode: runMode,
            resBucket: Buckets.resBucket(outW, outH),
            fpsBucket: Buckets.fpsBucket(fps),
            crfBucket: Buckets.crfBucket(crf),
            outW: outW, outH: outH,
            fps: fps,
            durationSec: durationSec,
            wallTimeSec: wallTimeSec,
            mpPerSec: mpPerSec
        )
    }
}
