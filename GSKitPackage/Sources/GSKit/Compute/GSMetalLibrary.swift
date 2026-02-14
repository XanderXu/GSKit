//
//  GSMetalLibrary.swift
//  GSKit
//

import Foundation
import Metal
import Dispatch

@available(macOS 26.0, *)
enum GSMetalLibrary {
    private final class BundleToken {}
    private static let resourceBundleName = "GSKit_GSKit"

    static func makeDefault(device: MTLDevice) throws -> MTLLibrary {
        // Prefer the package resource bundle first so we do not accidentally pick
        // an older process-bundled default.metallib with a mismatched kernel signature.
        // Load from Data instead of URL to avoid noisy companion binary archive lookups.
        for bundle in candidateBundles() {
            if let explicitURL = bundle.url(forResource: "default", withExtension: "metallib"),
               let bundledData = try? Data(contentsOf: explicitURL) {
                let bundledDispatchData = bundledData.withUnsafeBytes { DispatchData(bytes: $0) }
                if let bundledLibrary = try? device.makeLibrary(data: bundledDispatchData) {
                    return bundledLibrary
                }
            }
        }

        if let processDefaultLibrary = device.makeDefaultLibrary() {
            return processDefaultLibrary
        }

        throw NSError(
            domain: "GSKit.Metal",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unable to locate default.metallib in package or process bundle."]
        )
    }

    private static func candidateBundles() -> [Bundle] {
        let hosts = [Bundle.main, Bundle(for: BundleToken.self)]
        var seenURLs = Set<URL>()
        var bundles: [Bundle] = []

        func appendBundle(_ bundle: Bundle?) {
            guard let bundle else { return }
            let bundleURL = bundle.bundleURL.standardizedFileURL
            guard seenURLs.insert(bundleURL).inserted else { return }
            bundles.append(bundle)
        }

        for host in hosts {
            if let resourceBundleURL = host.url(forResource: resourceBundleName, withExtension: "bundle") {
                appendBundle(Bundle(url: resourceBundleURL))
            }

            if host.bundleURL.lastPathComponent == "\(resourceBundleName).bundle" {
                appendBundle(host)
            }
        }

        for bundle in Bundle.allBundles where bundle.bundleURL.lastPathComponent == "\(resourceBundleName).bundle" {
            appendBundle(bundle)
        }

        return bundles + hosts
    }
}
