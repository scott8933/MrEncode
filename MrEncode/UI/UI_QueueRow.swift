// =============================
// File: UI_QueueRow.swift  (main row shows Est./Final size + time; SRC/DST in details; consistent v-margins; Cancel support)
// =============================



import SwiftUI
import AppKit

struct UI_QueueRow: View {
    @EnvironmentObject var state: AppState
    
    @Environment(\.colorScheme) private var colorScheme
    private var C: StyleConstants.Colors { StyleConstants.colors(for: colorScheme) }

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
    
    // Non-blocking per-row basics (filled asynchronously)
    @StateObject private var probe = RowProbeModel()
    
    private var probeTaskKey: String {
        // Restart probe if scale changes or the URL changes (e.g., item replaced).
        "\(item.id.uuidString)|\(item.url.path)|\(state.settings.scale.factor)"
    }

    // UI constants
    private let bullet = " • "
    private var text75: Color { Color.primary.opacity(0.75) }
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
    
    private let missingSourceReason = "blocked: source item no longer available"

    private var isMissingSourceBlocked: Bool {
        item.status == .blocked && item.statusReason == missingSourceReason
    }
    
    @State private var hoveringSource: Bool = false
    
    private var sourceLinkColor: Color {
        hoveringSource ? C.linkHover : C.linkNormal
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
        let final = item.finalOutputURL ?? item.plannedOutputURL ?? suggested

        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {

                // Header row: checkbox (Queued) + chevron + DEST filename
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    // “Queued” checkbox (independent of List selection)
                    Toggle("", isOn: isQueuedBinding)
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .offset(y: 1.5)
                        .help(isMissingSourceBlocked
                              ? "This item is blocked because its source is missing. Expand the row, then click the SRC filename to locate it."
                              : "Include this item when encoding (Queued)")
                        .disabled(item.status == .encoding || isMissingSourceBlocked)
                    
                    // Chevron (expand/collapse) — ONLY control for reveal/hide
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
                            .foregroundColor(C.textSecondary)
                            .frame(width: 16, height: 16, alignment: .center)
                            .contentShape(Rectangle()) // keep the chevron hit-target generous
                    }
                    .buttonStyle(.plain)
                    .help(isExpanded ? "Hide details" : "Show details")
                    
                    // Primary filename is the destination. (Queued/Blocked: planned; Done: final)
                    CustomDestinationLink(
                        item: item,
                        suggestedURL: suggested,
                        settings: state.settings
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
                    .contentShape(Rectangle()) // makes the whole filename lane clickable (including empty space)
                    .onTapGesture {
                    #if os(macOS)
                        let flags = NSEvent.modifierFlags
                        if flags.contains(.shift) {
                            state.selectRange(to: item.id)
                        } else if flags.contains(.command) {
                            state.toggleSelection(for: item.id)
                        } else {
                            state.selectSingle(item.id)
                        }
                    #else
                        state.selectSingle(item.id)
                    #endif
                    }
                }
                // Reveal everything else ONLY when expanded
                if isExpanded {

                    // Reveal line: source filename (click to reveal / locate missing)
                    Button {
                        onPrimaryClick()
                    } label: {
                        Text(item.url.lastPathComponent.isEmpty ? "(missing source)" : item.url.lastPathComponent)
                            .font(.callout)
                            .foregroundColor(sourceLinkColor)
                            .underline(hoveringSource, color: .accentColor.opacity(0.6))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(isMissingSourceBlocked ? "Click to locate missing source" : "Reveal in Finder")
                    .padding(.leading, chevronIndent)
                    .onHover { inside in
                        hoveringSource = inside
#if os(macOS)
                        if inside {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
#endif
                    }
                    
                    // Processing indicator
                    if item.isProcessingMetadata {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.6)
                                .controlSize(.mini)
                            Text("Reading metadata...")
                                .font(.caption2)
                                .foregroundColor(C.textSecondary)
                        }
                        .padding(.leading, chevronIndent)
                    }
                    
                    // Main-view tertiary line: Render time (no filesystem access in UI)
                    if let actualSecs = item.actualEncodeSeconds, actualSecs.isFinite, actualSecs > 0 {
                        Text("Render Time: \(EncodeTimeEstimator.formatTime(actualSecs))")
                            .font(.callout)
                            .foregroundColor(C.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .padding(.leading, chevronIndent)
                    } else {
                        // Show estimates using OutputEstimator directly (not cached data)
                        if item.isProcessingMetadata {
                            Text("Calculating estimates...")
                                .font(.callout)
                                .foregroundColor(C.textSecondary)
                                .lineLimit(1)
                                .padding(.leading, chevronIndent)
                        } else {
                            // Build estimate summary directly
                            let estSummary = buildEstimateSummary(basics: probe.basics, meta: item.meta, settings: state.settings)
                            Text(estSummary)
                                .font(.callout)
                                .foregroundColor(C.textSecondary)
                                .lineLimit(1)
                                .padding(.leading, chevronIndent)
                                .id(state.settings.codec)
                        }
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
                                    .foregroundColor(C.textSecondary)
                                    .frame(minWidth: 72, alignment: .leading)
                            }
                        }
                    }
                    .frame(height: 20)                       // fixed rowlet height so the table allocates enough space
                    .padding(.leading, chevronIndent)        // align with other main-view lines
                }

                // Details – SRC/DST with full technical specifications (non-blocking)
                if isExpanded {
                    // SRC: show what we know now; avoid any synchronous AVAsset work
                    let srcText: String = {
                        var parts: [String] = []

                        // Dimensions:
                        if let b = probe.basics {
                            parts.append("\(b.srcW)×\(b.srcH)")
                        }

                        // FPS / Duration from metadata (fast)
                        if let fps = item.meta.nominalFPS, fps > 0 { parts.append(formatFPS(fps)) }
                        if item.meta.durationSeconds > 0 { parts.append(formatDuration(item.meta.durationSeconds)) }

                        // NCLC from metadata (fast)
                        if let n = nclcDisplayNow(meta: item.meta) { parts.append(n) }

                        // File size / bitrate (fast)
                        if item.meta.durationSeconds > 0, let bytes = item.cachedFileSize {
                            let bps = (Double(bytes) * 8.0) / item.meta.durationSeconds
                            parts.append(formatBitrate(bps))
                            parts.append(formatFileSize(bytes))
                        } else if let bytes = item.cachedFileSize {
                            parts.append(formatFileSize(bytes))
                        }

                        return parts.isEmpty ? "Processing..." : parts.joined(separator: bullet)
                    }()

                    Text("SRC: \(srcText)")
                        .font(.caption)
                        .foregroundColor(C.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.leading, chevronIndent)
                        .transition(.opacity)

                    // DST: use basics if available (non-blocking); otherwise placeholder
                    let dstText: String = {
                        var parts: [String] = []

                        // Dimensions (scaled + evenized) if basics known; otherwise omit
                        if let b = probe.basics {
                            // b.outW/outH are already scaled; evenize for display
                            let evenW = (b.outW & ~1)
                            let evenH = (b.outH & ~1)
                            parts.append("\(evenW)×\(evenH)")
                        }

                        // FPS / Duration (pass-through from source metadata)
                        if let fps = item.meta.nominalFPS, fps > 0 { parts.append(formatFPS(fps)) }
                        if item.meta.durationSeconds > 0 { parts.append(formatDuration(item.meta.durationSeconds)) }

                        // NCLC tags (predicted output labeling)
                        if let nclcLabel = predictedNCLCLabel(meta: item.meta, settings: state.settings) {
                            parts.append(nclcLabel)
                        }

                        // Container format indicator
                        parts.append("(\(state.settings.containerFormat.fileExtension.uppercased()))")

                        // No recompression path
                        if state.settings.codec == .bypass {
                            parts.append("No recompression (stream copy)")
                            return parts.joined(separator: bullet)
                        }

                        // Estimated output bitrate and file size (requires basics)
                        if let basics = probe.basics, let estimate = OutputEstimator.estimate(basics: basics, meta: item.meta, settings: state.settings) {
                            let (_, _, totalBps, estBytes, _, _) = estimate
                            if totalBps.isFinite && totalBps > 0 { parts.append(formatBitrate(totalBps)) }
                            if estBytes > 0 { parts.append(formatFileSize(Int64(estBytes))) }
                        }

                        return parts.isEmpty ? "Processing..." : parts.joined(separator: bullet)
                    }()

                    Text("DST: \(dstText)")
                        .font(.caption)
                        .foregroundColor(C.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.leading, chevronIndent)
                        .transition(.opacity)
                        .id(state.settings.codec)   // force re-eval on codec changes

                    if item.status == .blocked, let reason = item.statusReason {
                        Text(reason)
                            .font(.caption)
                            .foregroundColor(text75)
                            .lineLimit(2)
                            .padding(.leading, chevronIndent)
                            .transition(.opacity)
                    }
                    
                    if let warning = item.warningReason {
                        Text("Warning: \(warning)")
                            .font(.caption)
                            .foregroundColor(.orange.opacity(0.9))
                            .lineLimit(3)
                            .padding(.leading, chevronIndent)
                            .transition(.opacity)
                    }
                }
            }
            .padding(.vertical, 5)   // consistent top/bottom margin folded or expanded

            Spacer()

            // Right-side actions / status — ONLY place with Cancel while encoding
            HStack(spacing: 8) {
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
                    if item.status == .queued, item.warningReason != nil {
                        // Primary-row soft warning indicator (matches "Blocked" accent color)
                        (Text("Queued") + Text(" (warning)").foregroundColor(.orange))
                            .font(.caption)
                            .foregroundColor(C.textSecondary) // applies to the "Queued" portion
                            .opacity(item.status == .done ? 0.0 : 1.0)
                    } else {
                        Text(status.label)
                            .font(.caption)
                            .foregroundColor(status.color)
                            .opacity(item.status == .done ? 0.0 : 1.0)
                    }

                    Button {
                        onDelete?()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.monochrome)
                            .foregroundColor(C.textSecondary)
                            .imageScale(.medium)
                    }
                    .buttonStyle(.plain)
                    .help("Remove from queue")
                    .disabled(item.status == .encoding)
                }
            }
        }
        // Probe only when expanded. Debounce slightly to avoid starting work for rapid toggles.
        .task(id: "\(probeTaskKey)|\(isExpanded)") {
            guard isExpanded else { return }
            try? await Task.sleep(nanoseconds: 200_000_000)   // 200ms debounce
            guard isExpanded else { return }
            probe.start(url: item.url, meta: item.meta, scale: state.settings.scale)
        }
        .onDisappear {
            // Optional: don’t cancel if you want caches to continue warming.
            // For WebDAV, cancelling is often a win.
            probe.cancel()
        }

        .contentShape(Rectangle())
        .contextMenu {
            Button("Duplicate") {
                AppCore.shared.duplicateItems(withIDs: [item.id])
            }

            Button(item.isChecked ? "Unqueue Item" : "Queue Item") {
                // Missing-source blocked is un-queueable via menu as well.
                guard !isMissingSourceBlocked else { return }

                if let idx = AppCore.shared.index(of: item.id) {
                    AppCore.shared.updateFile(at: idx) { file in
                        file.isChecked.toggle()
                        // Do NOT auto-clear blocked here; status transitions should remain explicit.
                    }
                }
            }
            .disabled(item.status == .encoding || isMissingSourceBlocked)

            Divider()

            Button("Remove from Queue") {
                if let onDelete { onDelete() }
            }
            .disabled(item.status == .encoding)

            Divider()

            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            .disabled(isMissingSourceBlocked)
        }
    }
    
    
    // ─────────────────────────────────────────────
    // MARK: - Primary Row Click (Reveal / Reload)
    // ─────────────────────────────────────────────
    
    private func onPrimaryClick() {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let exists = fm.fileExists(atPath: item.url.path, isDirectory: &isDir)

        if exists && !isDir.boolValue {
            NSWorkspace.shared.activateFileViewerSelecting([item.url])
            return
        }

        // Missing source -> prompt user to locate/replace it
        showLocateSourceDialog()
    }
    
    private func showLocateSourceDialog() {
        let panel = NSOpenPanel()
        panel.title = "Locate Source"
        panel.message = "The original source file is missing. Choose a replacement file to restore this queue row."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true

        // Start in the closest existing parent folder (best effort)
        let startDir = item.url.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: startDir.path) {
            panel.directoryURL = startDir
        }

        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window) { response in
                guard response == .OK, let newURL = panel.url else { return }
                applyReplacedSourceURL(newURL)
            }
        } else {
            panel.begin { response in
                guard response == .OK, let newURL = panel.url else { return }
                applyReplacedSourceURL(newURL)
            }
        }
    }

    private func applyReplacedSourceURL(_ newURL: URL) {
        let url = newURL.standardizedFileURL

        // Recompute planned output URL (exclude this item to avoid self-collision warnings)
        let base = OutputNamer.suggestedOutputURL(for: url, settings: state.settings)
        let plan = AppCore.shared.planOutputURL(base: base, excludingID: item.id)

        AppCore.shared.updateFile(id: item.id) { file in
            file.url = url
            file.status = .queued
            file.statusReason = nil
            file.isChecked = true

            file.meta = .empty
            file.isProcessingMetadata = false

            file.plannedOutputURL = plan.url
            file.allowOverwrite = false
            file.warningReason = plan.warningReason
        }


        // Re-run inspection for this row so metadata/probe updates
        AppCore.shared.startInspection(for: item.id)

        state.pushMessage(
            level: .info,
            "Source replaced",
            filename: url.lastPathComponent,
            detail: url.path
        )
    }



    private func tryReloadSource() {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let exists = fm.fileExists(atPath: item.url.path, isDirectory: &isDir)

        guard exists && !isDir.boolValue else {
            state.pushMessage(
                level: .warning,
                "Source still missing",
                filename: item.url.lastPathComponent,
                detail: item.url.path
            )
            return
        }

        // Source is back — clear the missing-source block and allow user to queue again.
        AppCore.shared.updateFile(id: item.id) { file in
            file.status = .queued
            file.statusReason = nil

            // Decide policy: after reload, default to checked (user intent).
            file.isChecked = true
        }

        state.pushMessage(
            level: .info,
            "Source reloaded",
            filename: item.url.lastPathComponent,
            detail: item.url.path
        )
    }

}

// MARK: - Row helpers (fileprivate)

fileprivate extension UI_QueueRow {
    func perItemETA(item: MediaItem, settings: Settings) -> String? {
        // Require basics for ETA estimation
        guard let basics = probe.basics, let total = EncodeTimeEstimator.estimateSeconds(
            basics: basics,
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
    func buildEstimateSummary(basics: MediaBasics?, meta: MediaMetadata, settings: Settings) -> String {
        var parts: [String] = []

        // Size estimate (pure; requires basics)
        if let estimate = OutputEstimator.estimate(basics: basics, meta: meta, settings: settings) {
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

        // Render time estimate (pure; requires basics)
        if let wallTime = EncodeTimeEstimator.estimateSeconds(
            basics: basics,
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
    @Environment(\.colorScheme) private var colorScheme
    private var C: StyleConstants.Colors { StyleConstants.colors(for: colorScheme) }

    let item: MediaItem
    let suggestedURL: URL
    let settings: Settings
    @State private var hovering = false

    /// The NEXT encode destination (what should respond to suffix edits and collision planning).
    private var plannedURL: URL {
        item.plannedOutputURL ?? suggestedURL
    }

    /// The URL to reveal when the encode is done (history).
    private var revealURL: URL {
        item.finalOutputURL ?? plannedURL
    }

    /// What we display in the row.
    /// - queued/blocked/encoding: show the NEXT destination (planned)
    /// - done: show the final output (history), falling back to planned
    private var displayURL: URL {
        (item.status == .done) ? revealURL : plannedURL
    }

    private var isEditable: Bool {
        item.status == .queued || item.status == .blocked
    }

    private var linkColor: Color {
        if isEditable {
            return hovering ? C.linkHover : C.linkNormal
        } else {
            return item.status == .done
                ? (hovering ? C.linkHover : C.linkNormal)
                : C.linkDisabled
        }
    }
    
    var body: some View {
        Button {
            if isEditable {
                showCustomPathDialog()
            } else if item.status == .done {
                NSWorkspace.shared.activateFileViewerSelecting([revealURL])
            }
        } label: {
            Text(displayURL.lastPathComponent)
                .font(.callout)
                .foregroundColor(linkColor)
                .underline(hovering && (isEditable || item.status == .done), color: .accentColor.opacity(0.6))
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
    
    func showCustomPathDialog() {
        let panel = NSSavePanel()
        panel.title = "Choose Destination"
        panel.message = "Choose where to save the encoded file"
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = displayURL.lastPathComponent
        panel.directoryURL = displayURL.deletingLastPathComponent()
        
        // Set allowed file types to match the original
        let originalExtension = item.url.pathExtension
        if !originalExtension.isEmpty {
            panel.allowedContentTypes = [.init(filenameExtension: originalExtension) ?? .quickTimeMovie]
        }

        panel.begin { response in
            guard response == .OK, let newURL = panel.url else { return }

            // SAFETY CHECK: For Remote mode, validate path is accessible to farm
            if settings.runMode == .remoteDeadline {
                if case .failure(let error) = EncodeRenderfarm.isInputPathAcceptableForFarm(newURL) {
                    DispatchQueue.main.async {
                        let alert = NSAlert()
                        alert.messageText = "Invalid Destination Path"
                        alert.informativeText = error.message + "\n\nThe selected destination is not accessible to the render farm. Please choose a location on a shared network volume (e.g., /Volumes/Share/...)."
                        alert.alertStyle = .warning
                        alert.addButton(withTitle: "OK")

                        if let window = NSApp.keyWindow {
                            alert.beginSheetModal(for: window)
                        } else {
                            alert.runModal()
                        }

                        state.pushMessage(
                            level: .warning,
                            "Custom destination blocked for remote encoding",
                            filename: item.url.lastPathComponent,
                            code: .farmPath,
                            originKey: "custom-destination-farm-path",
                            detail: "Path: \(newURL.path)\nReason: \(error.message)"
                        )
                    }
                    return
                }
            }

            // Path is valid – confirm overwrite if needed, then update this item's planned destination
            DispatchQueue.main.async {
                var allowOverwrite = false
                let fm = FileManager.default

                if fm.fileExists(atPath: newURL.path) {
                    let alert = NSAlert()
                    alert.messageText = "Replace existing file?"
                    alert.informativeText = "A file named \"\(newURL.lastPathComponent)\" already exists in this location. Replacing it cannot be undone."
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "Replace")
                    alert.addButton(withTitle: "Cancel")

                    let response = alert.runModal()
                    if response != .alertFirstButtonReturn {
                        return // user cancelled
                    }
                    allowOverwrite = true
                }

                if let index = state.files.firstIndex(where: { $0.id == item.id }) {
                    AppCore.shared.updateFile(at: index) { file in
                        // This is the NEXT encode destination.
                        file.plannedOutputURL = newURL
                        file.allowOverwrite = allowOverwrite
                        
                        // Manual rename is authoritative → clear any auto-rename warning
                        file.warningReason = nil

                        // If it was blocked (conflict), rename is the remedy: restore to queued.
                        if file.status == .blocked {
                            file.status = .queued
                            file.statusReason = nil
                        }
                    }

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

