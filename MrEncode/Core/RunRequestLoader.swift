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
            return
        }

        let decoder = JSONDecoder()

        do {
            let req = try decoder.decode(DropletRunRequest.self, from: data)
            pending = (path: path, request: req)
        } catch {
        }
    }

    static func consumeIfPresent() -> (path: String, request: DropletRunRequest)? {
        defer { pending = nil }
        return pending
    }
}
