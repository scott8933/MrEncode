//
//  MrEncodeDropletMain.swift
//  MrEncode
//
//  Created by scott ulrich on 2/6/26.
//


import SwiftUI

@main
struct MrEncodeDropletMain: App {
    @NSApplicationDelegateAdaptor(DropletAppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
