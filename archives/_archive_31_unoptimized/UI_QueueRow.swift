// =============================
// File: UI_QueueRow.swift  (main row shows Est./Final size + time; SRC/DST in details; consistent v-margins; Cancel support)
// =============================
import SwiftUI
import AVFoundation
import AppKit

struct UI_QueueRow: View {
    @EnvironmentObject var state: AppState

    let item: MediaItem
    let suggested: URL

    // Optional external expansion control (the table decides height)
    var isExpandedExternal: Bool? = nil
    var onToggleExpand: (() -> Void)? = nil

    // Local fallback (used only if external isn't provided)
    @State private var localExpanded: Bool = false

    // UI constants
    private let bullet = " • "
    private let text75 = Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 0.75)
    private let chevronIndent: CGFloat = 20   // 14 (chevron) + 6 gap

    private var isExpanded: Bool { isExpandedExternal ?? localExpanded }

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
        let final = item.finalOutputURL ?? suggested

        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {

                // Header row: chevron + source filename (expands strictly downward)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Button {
                        if let onToggleExpand { onToggleExpand() }
                        else { withAnimation(.easeInOut(duration: 0.22)) { localExpanded.toggle() } }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 14, height: 14, alignment: .center)
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

                // Main-view secondary line: target filename (clickable only when .done)
                UI_RevealLink(
                    title: final.lastPathComponent,
                    url: final,
                    enabled: info.linkEnabled,        // true only for .done
                    inactiveColor: info.color
                )
                .padding(.leading, chevronIndent)

                // Main-view tertiary line: Final/Est size + Render time (use stats-based wall-time)
                if let actualSecs = item.actualEncodeSeconds, actualSecs.isFinite, actualSecs > 0,
                   let finalURL = item.finalOutputURL,
                   let finalBytes = fileSizeBytes(finalURL) {
                    Text("Final Size: \(formatFileSize(finalBytes))\(bullet)Render Time: \(EncodeTimeEstimator.formatTime(actualSecs))")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.leading, chevronIndent)
                } else {
                    let estWall: Double? = EncodeTimeEstimator.estimateSeconds(
                        url: item.url,
                        meta: item.meta,
                        settings: state.settings,
                        runMode: state.settings.runMode
                    )
                    let estBytes: Int64? = {
                        if let (_, _, _, bytes, _, _) = OutputEstimator.estimate(url: item.url, meta: item.meta, settings: state.settings),
                           bytes > 0 {
                            return Int64(bytes)
                        }
                        return nil
                    }()

                    let sizePart = estBytes.map { "Est. Final Size: ~\(formatFileSize($0))" }
                    let timePart: String? = {
                        if let w = estWall, w.isFinite, w > 0 {
                            return "Est. Render Time: \(EncodeTimeEstimator.formatTime(w))"
                        }
                        return nil
                    }()

                    let line = [sizePart, timePart].compactMap { $0 }.joined(separator: bullet)
                    if !line.isEmpty {
                        Text(line)
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .padding(.leading, chevronIndent)
                    }
                }

                // Progress (encoding only) - now with Cancel button and indeterminate support
                if item.status == .encoding {
                    // Reserve the full caption height regardless of ETA availability to prevent table clipping.
                    ZStack(alignment: .trailing) {
                        // Invisible height keeper (ensures ≥ caption2 height + a touch of breathing room)
                        Text("00:00:00")
                            .font(.caption2.monospacedDigit())
                            .opacity(0)
                            .padding(.vertical, 2)

                        HStack(alignment: .center, spacing: 8) {
                            // Progress bar - indeterminate for fake mode or when progress is nil
                            Group {
                                if let p = item.progress {
                                    ProgressView(value: p)
                                } else {
                                    // Indeterminate progress (bouncing bar for remote submissions)
                                    ProgressView()
                                }
                            }
                            .progressViewStyle(.linear)
                            .frame(maxWidth: 200, minHeight: 8)

                            // Cancel button (only show for local encodes, not remote submissions)
                            if item.progressMode != .fake {
                                Button("Cancel") {
                                    state.cancelEncoding(itemID: item.id)
                                }
                                .buttonStyle(.borderless)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .help("Cancel this encoding")
                            }

                            // Right-side countdown or status
                            if let eta = item.etaSeconds, eta.isFinite, eta > 0 {
                                Text(EncodeTimeEstimator.formatTime(eta))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: true, vertical: true) // never compress vertically
                                    .baselineOffset(1)                            // nudge off bar's center line
                            } else if item.progressMode == .fake {
                                // Show status for remote submissions
                                Text(item.statusReason ?? "Submitting…")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: true, vertical: true)
                                    .baselineOffset(1)
                            }
                        }
                    }
                    .frame(height: 20)                       // fixed rowlet height so the table allocates enough space
                    .padding(.leading, chevronIndent)        // align with other main-view lines
                }

                // Details — only SRC/DST (no size/time here anymore)
                if isExpanded {
                    if let srcLine = makeSrcLine(url: item.url, meta: item.meta) {
                        Text("SRC: \(srcLine)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .padding(.leading, chevronIndent)
                            .transition(.opacity)
                    }

                    if let dstLine = makeDstLine(url: item.url, meta: item.meta, settings: state.settings) {
                        Text("DST: \(dstLine)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .padding(.leading, chevronIndent)
                            .transition(.opacity)
                    }

                    if item.status == .blocked, let reason = item.statusReason {
                        Text(reason)
                            .font(.caption)
                            .foregroundColor(text75)
                            .lineLimit(2)
                            .padding(.leading, chevronIndent)
                            .transition(.opacity)
                    }
                }
            }
            .padding(.vertical, 5)   // <- consistent top/bottom margin folded or expanded

            Spacer()

            // Right-side status - updated to show Cancel for encoding
            if item.status == .encoding {
                Button("Cancel") {
                    state.cancelEncoding(itemID: item.id)
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundColor(.orange)
                .help("Cancel encoding")
            } else {
                Text(info.label)
                    .font(.caption)
                    .foregroundColor(info.color)
                    .opacity(item.status == .done ? 0.0 : 1.0)
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([final])
            }
            .disabled(!info.linkEnabled)
        }
    }
}

// MARK: - Row helpers (fileprivate)

fileprivate extension UI_QueueRow {
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
        return "\(pName)/\(tName)/\(mCode) [\(pCode), \(tCode), \(mCode)]"
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

    // MARK: - SRC/DST builders

    func makeSrcLine(url: URL, meta: MediaMetadata) -> String? {
        let asset = AVAsset(url: url)
        let secs = CMTimeGetSeconds(asset.duration)
        var w = 0, h = 0, fps: Double = 0

        if let v = asset.tracks(withMediaType: .video).first {
            let size = v.naturalSize.applying(v.preferredTransform)
            w = Int(abs(size.width).rounded())
            h = Int(abs(size.height).rounded())
            fps = Double(v.nominalFrameRate)
        }

        var parts: [String] = []
        if w > 0, h > 0 { parts.append("\(w)×\(h)") }
        if fps > 0 { parts.append("@ \(formatFPS(fps))") }
        if secs.isFinite, secs > 0 { parts.append(formatDuration(secs)) }
        if let n = nclcDisplayNow(meta: meta) { parts.append(n) }

        if secs.isFinite, secs > 0, let bytes = fileSizeBytes(url) {
            let bps = (Double(bytes) * 8.0) / secs
            parts.append(formatBitrate(bps))
            parts.append(formatFileSize(bytes))
        } else if let bytes = fileSizeBytes(url) {
            parts.append(formatFileSize(bytes))
        }

        return parts.isEmpty ? nil : parts.joined(separator: bullet)
    }

    func makeDstLine(url: URL, meta: MediaMetadata, settings: Settings) -> String? {
        let asset = AVAsset(url: url)
        var srcW = 0, srcH = 0
        var srcFPS: Double? = nil
        if let v = asset.tracks(withMediaType: .video).first {
            let size = v.naturalSize.applying(v.preferredTransform)
            srcW = Int(abs(size.width).rounded())
            srcH = Int(abs(size.height).rounded())
            let fr = Double(v.nominalFrameRate)
            if fr > 0 { srcFPS = fr }
        }

        let (dw, dh) = scaledEven(w: srcW, h: srcH, settings: settings)

        var parts: [String] = []
        if dw > 0, dh > 0 { parts.append("\(dw)×\(dh)") }

        // FPS: pass-through idea — prefer metadata fps, else fallback to probed fps
        if let mfps = meta.nominalFPS, mfps > 0 {
            parts.append("@ \(formatFPS(mfps))")
        } else if let f = srcFPS {
            parts.append("@ \(formatFPS(f))")
        }

        if let tag = predictedNCLCLabel(meta: meta, settings: settings) {
            parts.append(tag)
        }

        if let (_, _, total_bps, estBytes, _, _) = OutputEstimator.estimate(url: url, meta: meta, settings: settings) {
            if total_bps.isFinite, total_bps > 0 { parts.append("~" + formatBitrate(total_bps)) }
            if estBytes > 0 { parts.append("~" + formatFileSize(Int64(estBytes))) }
        }

        return parts.isEmpty ? nil : parts.joined(separator: bullet)
    }

    func scaledEven(w: Int, h: Int, settings: Settings) -> (Int, Int) {
        func even(_ v: Int) -> Int { v & ~1 }
        guard w > 0, h > 0 else { return (w, h) }
        switch settings.scale {
        case .oneToOne:
            return (even(w), even(h))
        case .half:
            return (even(Int(Double(w) * 0.5)),  even(Int(Double(h) * 0.5)))
        case .quarter:
            return (even(Int(Double(w) * 0.25)), even(Int(Double(h) * 0.25)))
        default:
            return (even(w), even(h))
        }
    }

    func predictedNCLCLabel(meta: MediaMetadata, settings: Settings) -> String? {
        let choice = settings.nclcTag.trimmingCharacters(in: .whitespacesAndNewlines)
        if choice.lowercased() == "no change" || choice.isEmpty {
            return nclcDisplayNow(meta: meta) // pass-through if present
        }
        return choice
    }
}
