//
//  ClipboardManager.swift
//  Slidy
//
//  Created by Ervin Dobri on 2026. 08. 15..
//


import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif


enum ClipboardManager {
    
    
    
    static func copyImage(url: URL) {
        guard let data = try? Data(contentsOf: url) else {
                print("Failed to load data from URL")
                return
            }

            #if os(iOS)
            if let image = UIImage(data: data) {
                UIPasteboard.general.image = image
            }
            #elseif os(macOS)
            if let image = NSImage(data: data) {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.writeObjects([image])
            }
            #endif
    }
}
