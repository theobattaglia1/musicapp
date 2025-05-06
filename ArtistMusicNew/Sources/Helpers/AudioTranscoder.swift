//
//  AudioTranscoder.swift
//  ArtistMusic
//
//  Created by Theo Battaglia on 5/5/25.
//


//
//  AudioTranscoder.swift
//  ArtistMusic
//
//  Converts unsupported audio to m4a (AAC) when needed.
//  If the source is already decodable by AVFoundation,
//  it simply copies the file.
//

import Foundation
import AVFoundation

enum AudioTranscoder {

    /// Returns a URL to a **local m4a** or the copied source file if it was
    /// already playable.  Returns `nil` on failure.
    static func ensurePlayableCopy(of src: URL,
                                   in destinationDir: URL) -> URL? {

        // quick test: can AVFoundation open it?
        let asset = AVURLAsset(url: src)
        if !asset.tracks.isEmpty {
            // playable → copy
            let dest = destinationDir.appendingPathComponent(src.lastPathComponent)
            try? FileManager.default.removeItem(at: dest)
            do    { try FileManager.default.copyItem(at: src, to: dest); return dest }
            catch { print("copy error:", error); return nil }
        }

        // not playable → transcode to m4a
        let dest = destinationDir
            .appendingPathComponent(src.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("m4a")

        let exporter = AVAssetExportSession(asset: asset,
                                            presetName: AVAssetExportPresetAppleM4A)
        exporter?.outputURL        = dest
        exporter?.outputFileType   = .m4a
        exporter?.shouldOptimizeForNetworkUse = false

        let semaphore = DispatchSemaphore(value: 0)
        exporter?.exportAsynchronously {
            semaphore.signal()
        }
        semaphore.wait()

        if exporter?.status == .completed {
            return dest
        } else {
            print("transcode failed:", exporter?.error ?? "unknown")
            return nil
        }
    }
}
