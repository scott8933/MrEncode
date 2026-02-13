//
//  DropletAppDelegate.swift
//  MrEncode
//
//  Created by scott ulrich on 2/6/26.
//


import Cocoa

final class DropletAppDelegate: NSObject, NSApplicationDelegate {
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("Droplet didFinishLaunching")
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        NSLog("Droplet open urls: %d %@", urls.count, urls.first?.path ?? "nil")
        DropletLauncher.launchMrEncode(withDroppedURLs: urls)
        NSApp.terminate(nil)
    }
}
