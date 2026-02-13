//
//  ProgressEvent.swift
//  MrEncode
//
//  Created by scott ulrich on 2/5/26.
//


//
//  ProgressEvent.swift
//  MrEncodeProgress
//

import Foundation

struct ProgressEvent: Decodable {
    let type: String
    let fraction: Double?
    let message: String?
    let eta: Double?

    // file_done / batch_done
    let ok: Bool?
    let output: String?
    let code: String?
}
