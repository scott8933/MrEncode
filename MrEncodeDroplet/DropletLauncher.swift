//
//  DropletLauncher.swift
//  MrEncode
//
//  Created by scott ulrich on 2/6/26.
//


import Foundation
import AppKit

private struct DropletPayload: Codable {
    let presetName: String
    let autoQuitOnCompletion: Bool
}

enum DropletLauncher {

    // Must match MrEncode.app bundle identifier
    private static let mrEncodeBundleID = "com.grayrobot.mrencode"

    static func launchMrEncode(withDroppedURLs urls: [URL]) {
        guard !urls.isEmpty else { return }

        guard
            let payload = loadPayload(),
            let presetJSON = loadPresetJSON()
        else {
            showError("Missing DropletPayload.json or Preset.mrepreset in this droplet.")
            return
        }

        let request = DropletRunRequest(
            schemaVersion: 1,
            ingestGroupID: UUID().uuidString,
            presetName: payload.presetName,
            presetJSON: presetJSON,
            inputPaths: urls.map { $0.path },
            autoQuitOnCompletion: true
        )

        guard let requestURL = writeRunRequest(request) else {
            showError("Failed to write run request.")
            return
        }

        // Step 1A: contract trace (droplet side)
        NSLog("MrEncodeDroplet: wrote RunRequest %@", requestURL.path)
        NSLog(
            "MrEncodeDroplet: preset=%@ inputs=%d autoQuit=%@",
            payload.presetName,
            urls.count,
            payload.autoQuitOnCompletion ? "true" : "false"
        )

        launchMrEncode(runRequestURL: requestURL)

    }

    // MARK: - Load Resources

    private static func loadPayload() -> DropletPayload? {
        guard let url = Bundle.main.url(forResource: "DropletPayload", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return nil }

        return try? JSONDecoder().decode(DropletPayload.self, from: data)
    }

    private static func loadPresetJSON() -> String? {
        guard let url = Bundle.main.url(forResource: "Preset", withExtension: "mrepreset"),
              let data = try? Data(contentsOf: url),
              let s = String(data: data, encoding: .utf8)
        else { return nil }

        return s
    }

    // MARK: - Write request

    private static func writeRunRequest(_ request: DropletRunRequest) -> URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }

        let runsDir = caches
            .appendingPathComponent(mrEncodeBundleID, isDirectory: true)
            .appendingPathComponent("DropletRuns", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: runsDir, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let url = runsDir
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .deferredToDate

        do {
            let data = try encoder.encode(request)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Launch MrEncode

    private static func launchMrEncode(runRequestURL: URL) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: mrEncodeBundleID) else {
            showError("MrEncode not found. Install it in /Applications.")
            return
        }

        let config = NSWorkspace.OpenConfiguration()
        config.arguments = ["--run-request", runRequestURL.path]
        config.activates = true

        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, error in
            if let error = error {
                showError("Failed to launch MrEncode: \(error.localizedDescription)")
            }
        }
    }

    private static func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Droplet Error"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
