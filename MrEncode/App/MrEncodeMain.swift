//
//  MrEncodeMain.swift
//  MrEncode
//
//  Created by scott ulrich on 2/3/26.
//


import Foundation

@main
struct MrEncodeMain {
    static func main() {
        if CommandLine.arguments.contains("--cli") {
            // Unbuffer stderr/stdout so droplet logs are immediate.
            setbuf(stdout, nil)
            setbuf(stderr, nil)

            let code = EncodeRunner.run(arguments: CommandLine.arguments)
            exit(Int32(code))
        }
        
        // Before touching SwiftUI, capture any run-request.
        let args = CommandLine.arguments
        if let runRequestPath = args.value(after: "--run-request") {
            RunRequestLoader.enqueue(path: runRequestPath)
        }
        
        // Only now touch SwiftUI.
        MrEncodeApp.main()

    }
}


private extension Array where Element == String {
    func value(after flag: String) -> String? {
        guard let idx = firstIndex(of: flag), idx + 1 < count else { return nil }
        return self[idx + 1]
    }
}
