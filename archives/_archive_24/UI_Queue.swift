import SwiftUI
import UniformTypeIdentifiers

struct UI_Queue: View {
    @EnvironmentObject var state: AppState

    private enum C {
        static let corner: CGFloat = 8
        static let minH: CGFloat = 140
        static let maxH: CGFloat = 700
        static let initH: CGFloat = 240
        static let pad: CGFloat = 12
    }

    // Drop & panel state
    @State private var isTargeted = false
    @State private var height: CGFloat = C.initH

    // Invalid drops
    @State private var showInvalidAlert = false
    @State private var invalidNames: [String] = []

    // IMPORTANT: local selection to avoid "Publishing changes…" warning
    @State private var localSelection = Set<MediaItem.ID>()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            UI_SectionHeader("Files Queued")

            ZStack {
                RoundedRectangle(cornerRadius: C.corner)
                    .fill(Color(NSColor.windowBackgroundColor))
                RoundedRectangle(cornerRadius: C.corner)
                    .stroke(isTargeted ? Color.accentColor.opacity(0.45)
                                       : Color.secondary.opacity(0.25), lineWidth: 1)

                ZStack {
                    if state.files.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.down.on.square")
                                .font(.system(size: 28))
                                .opacity(0.6)
                            Text("Drop QuickTime files here")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    // Multi-select list bound to LOCAL selection
                    List(selection: $localSelection) {
                        ForEach(state.files) { item in
                            let suggested = OutputNamer.suggestedOutputURL(for: item.url, settings: state.settings)
                            UI_QueueRow(item: item, suggested: suggested)
                                .environmentObject(state)
                                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                }
                .padding(C.pad)

                UI_ResizeHandle(height: $height, minHeight: C.minH, maxHeight: C.maxH)
                    .padding(.bottom, 6)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .clipShape(RoundedRectangle(cornerRadius: C.corner))
            .frame(minHeight: C.minH, idealHeight: height, maxHeight: height)
            .onDrop(of: [UTType.fileURL, UTType.movie, UTType.quickTimeMovie],
                    isTargeted: $isTargeted) { providers in
                handleDrop(providers: providers)
            }

            // When Auto-Encode mode hides the global footer bar,
            // show the Message Area right under the queue so users still see feedback.
            if state.settings.autoEncodeOnDrop {
                UI_MessageArea()
                    .environmentObject(state)
            }
        }
        .alert("Only QuickTime .mov files are supported", isPresented: $showInvalidAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(invalidNames.joined(separator: ", "))
        }
        // Keep local selection in sync with AppState, without publishing during view updates
        .onAppear {
            localSelection = state.selectedIDs
        }
        .onChange(of: localSelection) { newValue in
            // Defer publishing to avoid "Publishing changes from within view updates…" warning
            DispatchQueue.main.async {
                state.selectedIDs = newValue
            }
        }
        .onChange(of: state.files) { files in
            // Drop any selected IDs that were removed from the list
            let valid = Set(files.map { $0.id })
            localSelection.formIntersection(valid)
        }
    }

    // MARK: - Drop handler

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var accepted = false
        var urls = Set<URL>()
        var rejected: [String] = []
        let group = DispatchGroup()

        func push(_ maybe: URL?) {
            guard let u = maybe, u.isFileURL else { return }
            if UI_IsAllowedQuickTime(u) {
                urls.insert(u.standardizedFileURL)
            } else {
                rejected.append(u.lastPathComponent)
            }
        }

        // fileURL flavor
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            group.enter()
            p.loadObject(ofClass: NSURL.self) { obj, _ in
                defer { group.leave() }
                push((obj as? NSURL) as URL?)
            }
        }

        // movie / quicktime flavors
        let movieUTIs = [UTType.movie.identifier, UTType.quickTimeMovie.identifier]
        for p in providers where movieUTIs.contains(where: { p.hasItemConformingToTypeIdentifier($0) }) {
            accepted = true
            if p.canLoadObject(ofClass: NSURL.self) {
                group.enter()
                p.loadObject(ofClass: NSURL.self) { obj, _ in
                    defer { group.leave() }
                    push((obj as? NSURL) as URL?)
                }
                continue
            }
            for uti in movieUTIs where p.hasItemConformingToTypeIdentifier(uti) {
                group.enter()
                p.loadItem(forTypeIdentifier: uti, options: nil) { item, _ in
                    defer { group.leave() }
                    if let u = item as? URL { push(u) }
                    else if let ns = item as? NSURL { push(ns as URL) }
                    else if let s = item as? String {
                        if let u = URL(string: s), u.isFileURL { push(u) }
                        else { push(URL(fileURLWithPath: s)) }
                    }
                }
            }
        }

        group.notify(queue: .main) {
            let existing = Set(state.files.map { $0.url.standardizedFileURL })
            let newOnes = Array(urls.subtracting(existing))
            if !newOnes.isEmpty {
                state.addFiles(newOnes)
                if state.settings.autoEncodeOnDrop {
                    state.submit() // encode all queued (your existing submit-all behavior)
                }
            }
            if !rejected.isEmpty {
                invalidNames = rejected
                showInvalidAlert = true
            }
        }

        return accepted
    }
}
