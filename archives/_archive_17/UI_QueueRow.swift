import SwiftUI
import AVFoundation
import AppKit

struct UI_QueueRow: View {
    @EnvironmentObject var state: AppState

    let item: MediaItem
    let suggested: URL

    // UI constants
    private let dataSeperator = " | "
    private let bullet = " • "
    private let text75 = Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 0.75)

    // Cached tech line + dedupe sig
    @State private var baseTechLine: String? = nil
    @State private var lastSig: String? = nil

    // NEW: collapsible details
    @State private var isExpanded: Bool = false   // default collapsed; set true if you prefer expanded by default

    private var info: (label: String, linkEnabled: Bool, color: Color) {
        switch item.status {
        case .queued:   return ("Queued",    false, .secondary)
        case .encoding: return ("Encoding…", false, .orange)
        case .done:     return ("Rendered",  true,  .secondary)
        case .error:    return ("Error",     false, .red)
        case .blocked:  return ("Blocked",   false, .gray)
        }
    }

    var body: some View {
        // Prefer the actual written file; otherwise fall back to the suggestion
        let final = item.finalOutputURL ?? suggested

        // Compose the display tech line on the fly: base parts + NCLC (Label [codes])
        let displayTech: String? = {
            var parts: [String] = []
            if let base = baseTechLine, !base.isEmpty { parts.append(base) }
            if let nclcDisp = nclcDisplayNow(meta: item.meta) { parts.append(nclcDisp) }
            return parts.isEmpty ? nil : parts.joined(separator: dataSeperator)
        }()

        // Output preview line via OutputEstimator (bullets, size at end, no CRF)
        let outputLine: String? = OutputEstimator.previewLine(
            url: item.url,
            meta: item.meta,
            settings: state.settings,
            nclcLabel: nclcDisplayNow(meta: item.meta),
            bullet: bullet
        )

        // Actual output line (once rendered)
        let actualOutputLine: String? = {
            if item.status == .done, let finalURL = item.finalOutputURL {
                return buildActualOutputLine(finalURL: finalURL,
                                             nclcLabel: nclcDisplayNow(meta: item.meta),
                                             bullet: bullet)
            }
            return nil
        }()

        HStack(alignment: .firstTextBaseline, spacing: 8) {

            VStack(alignment: .leading, spacing: 6) {

                // Row header: disclosure + filename
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) { isExpanded.toggle() }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 14, height: 14, alignment: .center) // stable hit target
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(isExpanded ? "Hide details" : "Show details")

                    Text(item.url.lastPathComponent)
                        .foregroundColor(text75)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(item.url.path)
                }

                // Status / Reveal line (always visible)
                UI_RevealLink(
                    title: "\(info.label): \(final.lastPathComponent)",
                    url: final,
                    enabled: info.linkEnabled,
                    inactiveColor: info.color
                )

                // Details — only when expanded
                if isExpanded {

                    // Tech line (W×H | fps | duration | size | bitrate | Label [p, t, m])
                    if let tech = displayTech {
                        Text(tech)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    // Output line: show actual after render; otherwise show estimate
                    if let actual = actualOutputLine {
                        Text(actual)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else if let out = outputLine {
                        Text(out)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    // Encode time: show ACTUAL if done; else show ESTIMATE (Local only)
                    if let actual = item.actualEncodeSeconds, actual.isFinite, actual > 0 {
                        Text("Encode: \(EncodeTimeEstimator.formatTime(actual))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else if item.status != .done,
                              let secs = EncodeTimeEstimator.estimateSeconds(
                                url: item.url,
                                meta: item.meta,
                                settings: state.settings,
                                runMode: state.settings.runMode
                              ), secs.isFinite, secs > 0 {
                        Text("Encode (est.): \(EncodeTimeEstimator.formatTime(secs))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    if item.status == .blocked, let reason = item.statusReason {
                        Text(reason)
                            .font(.caption)
                            .foregroundColor(text75)
                            .lineLimit(2)
                    }
                }
            }

            Spacer()

            // Right status tag stays visible even when collapsed
            Text(info.label)
                .font(.caption)
                .foregroundColor(info.color)
                .opacity(item.status == .done ? 0.0 : 1.0)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([final])
            }
            .disabled(!info.linkEnabled)
        }
        // Recompute heavy base line whenever input URL or meta fields change.
        .task(id: signature(url: item.url, meta: item.meta)) {
            await computeBaseTechLine(for: item.url, meta: item.meta)
        }
    }
}

// MARK: - Row helpers (fileprivate)

fileprivate extension UI_QueueRow {
    func signature(url: URL, meta: MediaMetadata) -> String {
        [
            url.path,
            meta.colorPrimaries ?? "-",
            meta.transferFunction ?? "-",
            meta.ycbcrMatrix ?? "-",
            meta.nominalFPS.map { String(format: "%.3f", $0) } ?? "-",
            meta.durationSeconds.map { String(format: "%.3f", $0) } ?? "-"
        ].joined(separator: "|")
    }

    func computeBaseTechLine(for url: URL, meta: MediaMetadata) async {
        let sig = signature(url: url, meta: meta)
        if lastSig == sig, baseTechLine != nil { return }
        lastSig = sig

        let built: String = await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: self.buildBaseTechLine(url: url, meta: meta))
            }
        }
        baseTechLine = built
    }

    func buildBaseTechLine(url: URL, meta: MediaMetadata) -> String {
        var parts: [String] = []

        let asset = AVAsset(url: url)
        if let vTrack = asset.tracks(withMediaType: .video).first {
            let size = vTrack.naturalSize.applying(vTrack.preferredTransform)
            let w = Int(abs(size.width).rounded())
            let h = Int(abs(size.height).rounded())
            if w > 0, h > 0 { parts.append("\(w)×\(h)") }

            let fps = meta.nominalFPS ?? (vTrack.nominalFrameRate > 0 ? Double(vTrack.nominalFrameRate) : nil)
            if let fps { parts.append(formatFPS(fps)) }
        }

        let seconds = meta.durationSeconds ?? CMTimeGetSeconds(asset.duration)
        if seconds.isFinite, seconds > 0 {
            parts.append(formatDuration(seconds))
        }

        if let bytes = fileSizeBytes(url) {
            parts.append(formatFileSize(bytes))
            if seconds > 0 {
                let bps = (Double(bytes) * 8.0) / seconds
                parts.append(formatBitrate(bps))
            }
        }

        return parts.joined(separator: dataSeperator)
    }

    func fileSizeBytes(_ url: URL) -> Int64? {
        do {
            let rv = try url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
            if let t = rv.totalFileAllocatedSize { return Int64(t) }
            if let a = rv.fileAllocatedSize { return Int64(a) }
            if let s = rv.fileSize { return Int64(s) }
        } catch { }
        return nil
    }

    func formatDuration(_ secs: Double) -> String {
        if secs < 1.0 { return String(format: "%.2f s", secs) }
        let total = Int(round(secs))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = (total % 60)
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    func formatFPS(_ v: Double) -> String {
        let intv = Int(round(v))
        if abs(v - Double(intv)) < 0.005 { return "\(intv) fps" }
        return String(format: "%.2f fps", v)
    }

    func formatFileSize(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_000_000_000.0
        if gb >= 1.0 { return String(format: "%.2f GB", gb) }
        let mb = Double(bytes) / 1_000_000.0
        if mb >= 100 { return String(format: "%.0f MB", mb) }
        if mb >= 10  { return String(format: "%.1f MB", mb) }
        return String(format: "%.2f MB", mb)
    }

    func formatBitrate(_ bps: Double) -> String {
        let mbps = bps / 1_000_000.0
        if mbps >= 1000.0 { return String(format: "%.1f Gbps", mbps / 1000.0) }
        if mbps >= 100.0  { return String(format: "%.0f Mbps", mbps) }
        return String(format: "%.1f Mbps", mbps)
    }

    // NCLC label and mapping
    func nclcDisplayNow(meta: MediaMetadata) -> String? {
        guard
            let pRaw = meta.colorPrimaries?.trimmingCharacters(in: .whitespacesAndNewlines), !pRaw.isEmpty,
            let tRaw = meta.transferFunction?.trimmingCharacters(in: .whitespacesAndNewlines), !tRaw.isEmpty,
            let mRaw = meta.ycbcrMatrix?.trimmingCharacters(in: .whitespacesAndNewlines), !mRaw.isEmpty
        else { return nil }

        guard
            let pCode = intOrMapped(pRaw, kind: .primaries),
            let tCode = intOrMapped(tRaw, kind: .transfer),
            let mCode = intOrMapped(mRaw, kind: .matrix)
        else { return nil }

        if let label = consolidatedLabel(for: pCode, tCode, mCode) {
            return "\(label) [\(pCode), \(tCode), \(mCode)]"
        }

        let pName = codeToName(pCode, kind: .primaries) ?? "P\(pCode)"
        let tName = codeToName(tCode, kind: .transfer)  ?? "T\(tCode)"
        let mName = codeToName(mCode, kind: .matrix)    ?? "M\(mCode)"
        return "\(pName)/\(tName)/\(mName) [\(pCode), \(tCode), \(mCode)]"
    }

    func consolidatedLabel(for p: Int, _ t: Int, _ m: Int) -> String? {
        switch (p, t, m) {
        case (1, 1, 1):   return "Rec.709"
        case (1, 13, 1):  return "Rec.709 (sRGB TF)"
        case (12, 1, 1):  return "Display P3"
        case (12, 13, 1): return "Display P3 (sRGB TF)"
        case (9, 16, 9):  return "BT.2020 PQ (HDR10)"
        case (9, 18, 9):  return "BT.2020 HLG"
        case (9, 1, 9):   return "BT.2020 (709 TF)"
        case (6, 1, 6):   return "BT.601 NTSC"
        case (5, 1, 5):   return "BT.601 PAL"
        default:          return nil
        }
    }

    enum NCLCKind { case primaries, transfer, matrix }

    func intOrMapped(_ raw: String, kind: NCLCKind) -> Int? {
        if let n = Int(raw) { return n }
        let s = raw.lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ".", with: "")

        switch kind {
        case .primaries:
            if s.contains("bt709") { return 1 }
            if s.contains("bt2020") { return 9 }
            if s.contains("p3d65") || s.contains("displayp3") || s == "p3" { return 12 }
            if s.contains("bt470bg") || s.contains("pal") { return 5 }
            if s.contains("smpte170m") || s.contains("bt601") || s.contains("ntsc") { return 6 }
        case .transfer:
            if s.contains("bt709") { return 1 }
            if s.contains("iec6196621") || s.contains("srgb") { return 13 }
            if s.contains("smpte2084") || s.contains("st2084") || s.contains("pq") || s.contains("bt2100pq") { return 16 }
            if s.contains("aribstdb67") || s.contains("hlg") || s.contains("bt2100hlg") { return 18 }
            if s.contains("gamma22") || s == "g22" { return 4 }
            if s.contains("gamma28") || s == "g28" { return 5 }
        case .matrix:
            if s.contains("bt709") { return 1 }
            if s.contains("bt2020nc") || s.contains("2020nc") { return 9 }
            if s.contains("bt2020") || s == "2020" { return 9 }
            if s.contains("bt470bg") || s.contains("pal") { return 5 }
            if s.contains("smpte170m") || s.contains("bt601") || s.contains("601") || s.contains("ntsc") { return 6 }
        }
        return nil
    }

    func codeToName(_ code: Int, kind: NCLCKind) -> String? {
        switch (kind, code) {
        case (.primaries, 1):  return "BT.709"
        case (.primaries, 5):  return "BT.470BG"
        case (.primaries, 6):  return "SMPTE 170M"
        case (.primaries, 9):  return "BT.2020"
        case (.primaries, 12): return "P3 D65"
        case (.transfer, 1):   return "BT.709"
        case (.transfer, 4):   return "Gamma 2.2"
        case (.transfer, 5):   return "Gamma 2.8"
        case (.transfer, 13):  return "sRGB"
        case (.transfer, 16):  return "PQ"
        case (.transfer, 18):  return "HLG"
        case (.matrix, 1):     return "BT.709"
        case (.matrix, 5):     return "BT.470BG"
        case (.matrix, 6):     return "BT.601"
        case (.matrix, 9):     return "BT.2020"
        default: return nil
        }
    }

    func buildActualOutputLine(finalURL: URL,
                               nclcLabel: String?,
                               bullet: String = " • ") -> String? {
        let asset = AVAsset(url: finalURL)
        guard let vTrack = asset.tracks(withMediaType: .video).first else { return nil }

        let size = vTrack.naturalSize.applying(vTrack.preferredTransform)
        let outW = Int(abs(size.width).rounded())
        let outH = Int(abs(size.height).rounded())
        guard outW > 0, outH > 0 else { return nil }

        let secs = CMTimeGetSeconds(asset.duration)
        guard secs.isFinite, secs > 0 else { return nil }

        let bytes = fileSizeBytes(finalURL) ?? 0
        let total_bps = secs > 0 ? (Double(bytes) * 8.0 / secs) : 0

        let dimsStr = "\(outW)×\(outH)"
        let bitrateStr = formatBitrate(total_bps)
        let sizeStr = formatFileSize(Int64(bytes))

        let parts = ["Output: \(dimsStr)",
                     nclcLabel ?? "",
                     bitrateStr,
                     sizeStr].filter { !$0.isEmpty }
        return parts.joined(separator: bullet)
    }
}
