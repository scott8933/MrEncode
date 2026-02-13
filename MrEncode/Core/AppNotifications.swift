//
//  File.swift
//  MrEncode
//
//  Created by scott ulrich on 1/22/26.
//


import Foundation


enum QueueImportMode {
    case replace
    case append
}

extension Notification.Name {

    // Queue persistence
    static let mrEncodeSaveQueueRequested =
        Notification.Name("io.grayrobot.mrencode.saveQueueRequested")

    static let mrEncodeOpenQueueRequested =
        Notification.Name("io.grayrobot.mrencode.openQueueRequested")

    static let mrEncodeAppendQueueRequested =
        Notification.Name("io.grayrobot.mrencode.appendQueueRequested")

    // Media import
    static let mrEncodeImportMediaRequested =
        Notification.Name("io.grayrobot.mrencode.importMediaRequested")
}


