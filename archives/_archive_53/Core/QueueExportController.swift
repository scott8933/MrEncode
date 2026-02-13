//
//  QueueExportController.swift
//  MrEncode
//
//  Created by scott ulrich on 1/22/26.
//


import SwiftUI

@MainActor
final class QueueExportController: ObservableObject {
    @Published var isExporting: Bool = false
    @Published var exportDoc: QueueFileDocument?

    @Published var lastErrorMessage: String?

    func beginExport(items: [MediaItem]) {
        let doc = QueueSaveService.makeDocument(items: items)
        self.exportDoc = QueueFileDocument(document: doc)
        self.isExporting = true
    }

    func handleExportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            // Nothing required, but you could toast/log here.
            break
        case .failure(let error):
            lastErrorMessage = error.localizedDescription
        }
    }
}
