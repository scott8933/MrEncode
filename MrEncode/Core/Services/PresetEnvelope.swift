//
//  PresetEnvelope.swift
//  MrEncode
//
//  Created by scott ulrich on 2/8/26.
//


import Foundation

struct PresetEnvelope: Codable {
    let createdDate: Double?
    let presetName: String
    let settings: Settings
}
