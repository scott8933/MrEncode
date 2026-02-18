//
//  RunRequestLoader.swift
//  MrEncode
//
//  Created by scott ulrich on 2/6/26.
//


import Foundation

enum RunRequestLoader {
    private static var pending: (path: String, request: DropletRunRequest)?

    static func enqueue(path: String) {
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url) else {
            NSLog("MrEncode: RunRequestLoader failed to read \(path)")
            return
        }

        let decoder = JSONDecoder()

        do {
            let req = try decoder.decode(DropletRunRequest.self, from: data)
            pending = (path: path, request: req)
            NSLog("MrEncode: RunRequestLoader enqueued request (\(req.inputPaths.count) path(s))")
        } catch {
            NSLog("MrEncode: RunRequestLoader invalid request: \(error)")
        }
    }

    static func consumeIfPresent() -> (path: String, request: DropletRunRequest)? {
        defer { pending = nil }
        return pending
    }
}
