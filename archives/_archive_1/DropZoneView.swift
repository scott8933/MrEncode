// =============================
// File: DropZoneView.swift
// =============================
import SwiftUI
import UniformTypeIdentifiers


struct DropZoneView: View {
@State private var isTargeted: Bool = false
var onURLs: ([URL]) -> Void


var body: some View {
RoundedRectangle(cornerRadius: 12)
.strokeBorder(isTargeted ? Color.accentColor : Color.secondary, style: StrokeStyle(lineWidth: 2, dash: [6,6]))
.overlay(
Text(isTargeted ? "Release to add" : "Drag .mov files…")
.foregroundStyle(.secondary)
)
.onDrop(of: [UTType.movie.identifier, UTType.fileURL.identifier], isTargeted: $isTargeted) { providers in
collectURLs(from: providers) { urls in onURLs(urls) }
return true
}
}


private func collectURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
let group = DispatchGroup()
var results: [URL] = []
for p in providers {
group.enter()
p.loadFileURL(preferredType: .movie) { url in
if let url { results.append(url) }
else {
p.loadFileURL(preferredType: .item) { url2 in if let url2 { results.append(url2) }; group.leave() }
return
}
group.leave()
}
}
group.notify(queue: .main) { completion(results) }
}
}
