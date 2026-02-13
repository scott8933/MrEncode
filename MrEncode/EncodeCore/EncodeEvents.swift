//
//  EncodeEvents.swift
//  MrEncode
//
//  Created by scott ulrich on 2/2/26.
//


import Foundation

public enum EncodeEvent: Sendable {
    case phase(EncodePhase)
    case progress(EncodeProgress)
    case warning(String)
    case completed(EncodeResult)
    case failed(EncodeError)
}

public enum EncodePhase: String, Sendable {
    case preparing
    case probingSource
    case buildingPipeline
    case encodingVideo
    case encodingAudio
    case finalizing
}

public struct EncodeProgress: Sendable {
    public var fraction: Double                 // 0...1
    public var framesDone: Int?
    public var framesTotal: Int?
    public var secondsDone: Double?
    public var secondsTotal: Double?
    public var fps: Double?
    public var etaSeconds: Double?
    public var bytesWritten: Int64?
    public var message: String?

    public init(
        fraction: Double,
        framesDone: Int? = nil,
        framesTotal: Int? = nil,
        secondsDone: Double? = nil,
        secondsTotal: Double? = nil,
        fps: Double? = nil,
        etaSeconds: Double? = nil,
        bytesWritten: Int64? = nil,
        message: String? = nil
    ) {
        self.fraction = max(0.0, min(1.0, fraction))
        self.framesDone = framesDone
        self.framesTotal = framesTotal
        self.secondsDone = secondsDone
        self.secondsTotal = secondsTotal
        self.fps = fps
        self.etaSeconds = etaSeconds
        self.bytesWritten = bytesWritten
        self.message = message
    }
}

public typealias EncodeEventSink = @Sendable (EncodeEvent) -> Void
public typealias CancelCheck = @Sendable () -> Bool

public struct EncodeResult: Sendable {
    public let outputURL: URL
    public let durationSeconds: Double?
    public let framesEncoded: Int?

    public init(outputURL: URL, durationSeconds: Double? = nil, framesEncoded: Int? = nil) {
        self.outputURL = outputURL
        self.durationSeconds = durationSeconds
        self.framesEncoded = framesEncoded
    }
}

public struct EncodeError: Error, Sendable {
    public enum Code: String, Sendable {
        case cancelled
        case invalidInput
        case readerFailed
        case writerFailed
        case pipelineFailed
        case finalizeFailed
        case unknown
    }

    public let code: Code
    public let message: String

    public init(_ code: Code, _ message: String) {
        self.code = code
        self.message = message
    }
}
