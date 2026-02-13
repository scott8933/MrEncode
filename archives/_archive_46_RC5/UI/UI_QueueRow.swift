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
    
    // NEW: control the “Queued” checkbox + row deletion from parent
    var isQueuedExternal: Bool? = nil
    var onToggleQueued: ((Bool) -> Void)? = nil
    var onDelete: (() -> Void)? = nil


    // Local fallback (used only if external isn't provided)
    @State private var localExpanded: Bool = false

    // UI constants
    private let bullet = " • "
    private let text75 = Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 0.75)
    private let chevronIndent: CGFloat = 46   // 14 (chevron) + 6 gap

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
    
    // NEW: local fallback for the queued checkbox (previews / if parent doesn’t wire it)
    @State private var localQueued: Bool = false
    private var isQueuedBinding: Binding<Bool> {
        if let ext = isQueuedExternal {
            return Binding(
                get: { ext },
                set: { newVal in onToggleQueued?(newVal) }
            )
        } else {
            return $localQueued
        }
    }

    
    //------------------------------------
    // TODO WE ONLY NEED ONE OF THESE
    //
    // Minimal in-file status label/color (replace with your exact mapping if you had one)
    private var status: (label: String, color: Color) {
        switch item.status {
        case .blocked:
            return ("Blocked", .orange)
        case .encoding:
            return ("Encoding", .blue)
        case .done:
            return ("Done", .green)
        default:
            // e.g. .queued, .idle, .pending — use your preferred label/color
            return ("Queued", .secondary)
        }
    }

    // Minimal status label/color so we don't depend on UIQueueRowInfo
    private var statusInfo: (label: String, color: Color) {
        switch item.status {
        case .encoding:
            return ("Encoding", .blue)
        case .blocked:
            return ("Blocked", .orange)
        case .done:
            return ("Done", .green)
        default:
            return ("Queued", .secondary)
        }
    }
    //
    //
    //------------------------------------
    
    

    var body: some View {
        let final = item.finalOutputURL ?? suggested

        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {

                // Header row: checkbox (Queued) + chevron + source filename
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    // “Queued” checkbox (independent of List selection)
                    Toggle("", isOn: isQueuedBinding)
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .offset(y: 1.5)
                        .help("Include this item when encoding (Queued)")

                    // Chevron (expand/collapse) — forced plain symbol so it can’t turn into a circle
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            if let onToggleExpand { onToggleExpand() }
                            else { localExpanded.toggle() }
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .symbolVariant(.none)
                            .symbolRenderingMode(.monochrome)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 16, height: 16, alignment: .center)
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
                .contentShape(Rectangle()) // make the whole header clickable
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        if let onToggleExpand { onToggleExpand() }
                        else { localExpanded.toggle() }
                    }
                }

                // Main-view secondary line: target filename (clickable for queued items)
                CustomDestinationLink(
                    item: item,
                    suggestedURL: suggested,
                    settings: state.settings
                )
                .padding(.leading, chevronIndent)
                
                // Processing indicator
                if item.isProcessingMetadata {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.6)
                            .controlSize(.mini)
                        Text("Reading metadata...")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, chevronIndent)
                }
                
                // Main-view tertiary line: Final/Est size + Render time - ONLY ESTIMATES
                if let actualSecs = item.actualEncodeSeconds, actualSecs.isFinite, actualSecs > 0,
                   let finalURL = item.finalOutputURL,
                   let finalBytes = fileSizeBytes(finalURL) {
                    Text("Final Size: \(formatFileSize(finalBytes)) • Render Time: \(EncodeTimeEstimator.formatTime(actualSecs))")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.leading, chevronIndent)
                } else {
                    // Show estimates using OutputEstimator directly (not cached data)
                    if item.isProcessingMetadata {
                        Text("Calculating estimates...")
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .padding(.leading, chevronIndent)
                    } else {
                        // Build estimate summary directly
                        let estSummary = buildEstimateSummary(url: item.url, meta: item.meta, settings: state.settings)
                        Text(estSummary)
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .padding(.leading, chevronIndent)
                    }
                }

                // Progress (encoding only) — single Cancel lives at far right (outside), ETA shown here
                if item.status == .encoding {
                    // Reserve the full caption height regardless of ETA availability to prevent table clipping.
                    ZStack(alignment: .trailing) {
                        // Invisible height keeper (ensures ≥ caption2 height + a touch of breathing room)
                        Text("00:00:00")
                            .font(.caption2.monospacedDigit())
                            .opacity(0)
                            .padding(.vertical, 2)

                        HStack(alignment: .center, spacing: 8) {
                            // Progress bar - determinate if we have progress, otherwise indeterminate
                            Group {
                                if let p = item.progress {
                                    ProgressView(value: p)
                                } else {
                                    ProgressView()
                                }
                            }
                            .progressViewStyle(.linear)
                            .frame(maxWidth: 200, minHeight: 8)

                            // Per-item ETA (replaces any mid-row Cancel)
                            if let eta = perItemETA(item: item, settings: state.settings) {
                                Text("ETA: \(eta)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundColor(.secondary)
                                    .frame(minWidth: 72, alignment: .leading)
                            }
                        }
                    }
                    .frame(height: 20)                       // fixed rowlet height so the table allocates enough space
                    .padding(.leading, chevronIndent)        // align with other main-view lines
                }

                // Details – SRC/DST with full technical specifications
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

                    if let dstLine = makeDstTechnicalSpecs(url: item.url, meta: item.meta, settings: state.settings) {
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
            .padding(.vertical, 5)   // consistent top/bottom margin folded or expanded

            Spacer()

            // Right-side actions / status — ONLY place with Cancel while encoding
            HStack(spacing: 10) {
                if item.status == .encoding {
                    Button {
                        // Per-item cancel not implemented in AppState; fall back to global cancel.
                        state.cancelAllEncoding()
                    } label: {
                        Text("Cancel")
                            .font(.callout).bold()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .keyboardShortcut(.cancelAction)
                    .help("Cancel current encodes")
                } else {
                    Text(status.label)
                        .font(.caption)
                        .foregroundColor(status.color)
                        .opacity(item.status == .done ? 0.0 : 1.0)

                    Button {
                        onDelete?()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.monochrome)
                            .foregroundColor(.secondary)
                            .imageScale(.medium)
                    }
                    .buttonStyle(.plain)
                    .help("Remove from queue")
                    .disabled(item.status == .encoding)
                }
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
    func perItemETA(item: MediaItem, settings: Settings) -> String? {
        // Ask the shared estimator for a total-seconds estimate for THIS item
        guard let total = EncodeTimeEstimator.estimateSeconds(
            url: item.url,
            meta: item.meta,
            settings: settings,
            runMode: settings.runMode
        ), total.isFinite, total > 0 else {
            return nil
        }

        // If we have progress, scale remaining by (1 - p). Otherwise use full total.
        let remaining: Double
        if let p = item.progress, p.isFinite, p >= 0, p <= 1 {
            remaining = max(0, total * (1 - p))
        } else {
            remaining = total
        }

        // Render as hh:mm:ss using the same formatter the rest of the app uses
        return EncodeTimeEstimator.formatTime(remaining)
    }
}


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
        // Always include units for clarity
        if secs < 1.0 {
            return String(format: "%.2f sec", secs)
        }
        if secs < 60.0 {
            return String(format: "%.1f sec", secs)
        }
        let total = Int(round(secs))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = (total % 60)
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
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

    // Build estimate summary for main view (size + render time only)
        func buildEstimateSummary(url: URL, meta: MediaMetadata, settings: Settings) -> String {
            var parts: [String] = []
            
            // Size estimate
            if let estimate = OutputEstimator.estimate(url: url, meta: meta, settings: settings) {
                let (_, _, _, estBytes, _, _) = estimate
                if estBytes > 0 {
                    let mb = estBytes / 1_000_000.0
                    if mb >= 1000 {
                        parts.append("Est. Size: \(String(format: "%.1f GB", mb / 1000.0))")
                    } else {
                        parts.append("Est. Size: \(String(format: "%.1f MB", mb))")
                    }
                }
            }
            
            // Render time estimate
            if let wallTime = EncodeTimeEstimator.estimateSeconds(
                url: url,
                meta: meta,
                settings: settings,
                runMode: settings.runMode
            ), wallTime.isFinite, wallTime > 0 {
                parts.append("Est. Render Time: \(EncodeTimeEstimator.formatTime(wallTime))")
            }
            
            return parts.isEmpty ? "Calculating..." : parts.joined(separator: bullet)
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
        // Always build fresh comprehensive source info to ensure we have all data
        let asset = AVAsset(url: url)
        var w = 0, h = 0, fps: Double = 0
        var duration: Double = 0

        // Get dimensions and basic properties from AVFoundation
        if let v = asset.tracks(withMediaType: .video).first {
            let size = v.naturalSize.applying(v.preferredTransform)
            w = Int(abs(size.width).rounded())
            h = Int(abs(size.height).rounded())
            fps = Double(v.nominalFrameRate)
        }
        
        let avDuration = CMTimeGetSeconds(asset.duration)
        if avDuration.isFinite && avDuration > 0 {
            duration = avDuration
        }

        // Prefer ExifTool metadata when available
        if let metaFPS = meta.nominalFPS, metaFPS > 0 {
            fps = metaFPS
        }
        if meta.durationSeconds > 0 {
            duration = meta.durationSeconds
        }

        var parts: [String] = []
        
        // 1. Pixel dimensions
        if w > 0, h > 0 {
            parts.append("\(w)×\(h)")
        }
        
        // 2. Frame rate
        if fps > 0 {
            parts.append(formatFPS(fps))
        }
        
        // 3. Duration
        if duration > 0 {
            parts.append(formatDuration(duration))
        }
        
        // 4. NCLC display from source metadata
        if let nclc = nclcDisplayNow(meta: meta) {
            parts.append(nclc)
        }

        // 5. Bitrate and file size
        if duration > 0, let bytes = fileSizeBytes(url) {
            let bps = (Double(bytes) * 8.0) / duration
            parts.append(formatBitrate(bps))
            parts.append(formatFileSize(bytes))
        } else if let bytes = fileSizeBytes(url) {
            parts.append(formatFileSize(bytes))
        }

        return parts.isEmpty ? "Processing..." : parts.joined(separator: bullet)
    }

    // NEW: Build full technical specs for DST (not estimates)
    func makeDstTechnicalSpecs(url: URL, meta: MediaMetadata, settings: Settings) -> String? {
        // Get source dimensions and properties
        let asset = AVAsset(url: url)
        var srcW = 0, srcH = 0
        var srcFPS: Double = 0
        var srcDuration: Double = 0
        
        if let v = asset.tracks(withMediaType: .video).first {
            let size = v.naturalSize.applying(v.preferredTransform)
            srcW = Int(abs(size.width).rounded())
            srcH = Int(abs(size.height).rounded())
            srcFPS = Double(v.nominalFrameRate)
        }
        
        let duration = CMTimeGetSeconds(asset.duration)
        if duration.isFinite && duration > 0 {
            srcDuration = duration
        }
        
        // Prefer ExifTool metadata for FPS and duration
        if let metaFPS = meta.nominalFPS, metaFPS > 0 {
            srcFPS = metaFPS
        }
        if meta.durationSeconds > 0 {
            srcDuration = meta.durationSeconds
        }

        // Calculate scaled dimensions (with evenization)
        let (dstW, dstH) = scaledEven(w: srcW, h: srcH, settings: settings)

        var parts: [String] = []
        
        // 1. Dimensions (show scaled result)
        if dstW > 0, dstH > 0 {
            parts.append("\(dstW)×\(dstH)")
        }

        // 2. Frame rate (pass-through from source)
        if srcFPS > 0 {
            parts.append(formatFPS(srcFPS))
        }
        
        // 3. Duration (same as source)
        if srcDuration > 0 {
            parts.append(formatDuration(srcDuration))
        }

        // 4. NCLC tags (what will be applied after encoding)
        if let nclcLabel = predictedNCLCLabel(meta: meta, settings: settings) {
            parts.append(nclcLabel)
        }

        // 5. Container format indicator
        parts.append("(\(settings.containerFormat.fileExtension.uppercased()))")

        // 6. Estimated output bitrate and file size (technical specs)
        if let estimate = OutputEstimator.estimate(url: url, meta: meta, settings: settings) {
            let (_, _, totalBps, estBytes, _, _) = estimate
            
            // Add estimated bitrate (as technical spec)
            if totalBps.isFinite && totalBps > 0 {
                parts.append(formatBitrate(totalBps))
            }
            
            // Add estimated file size (as technical spec)
            if estBytes > 0 {
                parts.append(formatFileSize(Int64(estBytes)))
            }
        }

        return parts.isEmpty ? "Processing..." : parts.joined(separator: bullet)
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

// MARK: - Custom Destination Link Component

private struct CustomDestinationLink: View {
    @EnvironmentObject var state: AppState
    let item: MediaItem
    let suggestedURL: URL
    let settings: Settings
    @State private var hovering = false
    
    private var finalURL: URL {
        item.finalOutputURL ?? suggestedURL
    }
    
    private var isEditable: Bool {
        item.status == .queued || item.status == .blocked
    }
    
    private var linkColor: Color {
        if isEditable {
            return hovering ? .blue : .secondary
        } else {
            return item.status == .done ? (hovering ? .blue : .secondary) : .gray
        }
    }
    
    var body: some View {
        Button {
            if isEditable {
                showCustomPathDialog()
            } else if item.status == .done {
                NSWorkspace.shared.activateFileViewerSelecting([finalURL])
            }
        } label: {
            Text(finalURL.lastPathComponent)
                .font(.callout)
                .foregroundColor(linkColor)
                .underline(hovering && (isEditable || item.status == .done), color: .blue.opacity(0.6))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.top, 2)
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hovering = inside
            if inside && (isEditable || item.status == .done) {
                NSCursor.pointingHand.push()
            } else if !inside {
                NSCursor.pop()
            }
        }
        .help(helpText)
    }
    
    private var helpText: String {
        if isEditable {
            return "Click to choose custom destination"
        } else if item.status == .done {
            return "Reveal in Finder"
        } else {
            return "Not available until rendered"
        }
    }
    
    private func showCustomPathDialog() {
        let panel = NSSavePanel()
        panel.title = "Choose Destination"
        panel.message = "Choose where to save the encoded file"
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = finalURL.lastPathComponent
        panel.directoryURL = finalURL.deletingLastPathComponent()
        
        // Set allowed file types to match the original
        let originalExtension = item.url.pathExtension
        if !originalExtension.isEmpty {
            panel.allowedContentTypes = [.init(filenameExtension: originalExtension) ?? .quickTimeMovie]
        }
        
        panel.begin { response in
            guard response == .OK, let newURL = panel.url else { return }
            
            // SAFETY CHECK: For Remote mode, validate path is accessible to farm
            if settings.runMode == .remoteDeadline {
                let pathCheck = EncodeRemote.isInputPathAcceptableForFarm(newURL)
                if !pathCheck.ok {
                    // Show error dialog and don't apply the path
                    DispatchQueue.main.async {
                        let alert = NSAlert()
                        alert.messageText = "Invalid Destination Path"
                        alert.informativeText = pathCheck.reason ?? "The selected destination is not accessible to the render farm. Please choose a location on a shared network volume (e.g., /Volumes/Share/...)."
                        alert.alertStyle = .warning
                        alert.addButton(withTitle: "OK")
                        
                        if let window = NSApp.keyWindow {
                            alert.beginSheetModal(for: window)
                        } else {
                            alert.runModal()
                        }
                        
                        // Also log the issue
                        state.pushMessage(
                            level: .warning,
                            "Custom destination blocked for remote encoding",
                            filename: item.url.lastPathComponent,
                            code: .farmPath,
                            originKey: "custom-destination-farm-path",
                            detail: "Path: \(newURL.path)\nReason: \(pathCheck.reason ?? "Not accessible to render farm")"
                        )
                    }
                    return
                }
            }
            
            // Path is valid - update this specific item's custom destination
            DispatchQueue.main.async {
                if let index = state.files.firstIndex(where: { $0.id == item.id }) {
                    AppCore.shared.files[index].finalOutputURL = newURL
                    
                    // Show success confirmation
                    state.pushMessage(
                        level: .info,
                        "Custom destination set",
                        filename: item.url.lastPathComponent,
                        detail: "Will save to: \(newURL.path)"
                    )
                }
            }
        }
    }
}
