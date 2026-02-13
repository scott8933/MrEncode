
// =============================
// File: NSItemProvider+URL.swift
// =============================


import AppKit
import UniformTypeIdentifiers


extension NSItemProvider {
func loadFileURL(preferredType: UTType, completion: @escaping (URL?) -> Void) {
if hasItemConformingToTypeIdentifier(preferredType.identifier) {
_ = loadInPlaceFileRepresentation(forTypeIdentifier: preferredType.identifier) { url, _, _ in
completion(url)
}
return
}
completion(nil)
}
}
