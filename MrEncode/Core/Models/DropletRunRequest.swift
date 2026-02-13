import Foundation

struct DropletRunRequest: Codable {
    let schemaVersion: Int
    let ingestGroupID: String
    let presetName: String
    let presetJSON: String
    let inputPaths: [String]
    let autoQuitOnCompletion: Bool
}
