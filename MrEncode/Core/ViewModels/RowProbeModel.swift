//
//  RowProbeModel.swift
//  MrEncode
//
//  Created by scott ulrich on 1/15/26.
//


import Foundation

@MainActor
final class RowProbeModel: ObservableObject {
    @Published var basics: MediaBasics? = nil

    private var task: Task<Void, Never>?
    private var lastKey: String?

    func start(url: URL, meta: MediaMetadata, scale: ScaleOption) {
        let key = "\(url.path)|\(scale.factor)"

        // Idempotency: if we're already resolved for this key, do nothing
        if key == lastKey, basics != nil {
            return
        }

        // If inputs changed, reset visible state
        if key != lastKey {
            basics = nil
        }
        lastKey = key

        // Cancel any previous probe task
        task?.cancel()

        // Start / join background probe
        task = Task { [weak self] in
            let t = await MediaProbeService.shared.probeBasics(
                url: url,
                meta: meta,
                scale: scale
            )
            let result = await t.value
            guard !Task.isCancelled else { return }
            self?.basics = result
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
