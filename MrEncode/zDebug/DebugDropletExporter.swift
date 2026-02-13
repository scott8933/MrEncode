import Foundation

enum DebugDropletExporter {

    @MainActor
    static func export() {
        // AppState.shared is MainActor-isolated
        guard let appState = AppState.shared else {
            NSLog("DebugDropletExporter: AppState.shared is nil")
            return
        }

        // Construct DropletFile using only fields that exist in your model.
        // If DropletFile is Codable and has presetName + settings, this will work.
        var droplet = DropletFile(
            presetName: appState.settings.selectedPresetName,
            settings: appState.settings
        )

        // If your DropletFile type has an exitWhenDone property, set it here.
        // If it does NOT exist, delete this block.
        if let _ = Mirror(reflecting: droplet).children.first(where: { $0.label == "exitWhenDone" }) {
            // Can’t set via Mirror; keep this as a compile-time edit:
            // droplet.exitWhenDone = true
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .deferredToDate

        do {
            let data = try encoder.encode(droplet)
            print(String(decoding: data, as: UTF8.self))
        } catch {
            NSLog("DebugDropletExporter: encode failed: \(error)")
        }
    }
}
