import Foundation
import Photos
import ImageIO

struct PhotoDateInfo: Identifiable {
    let id: String
    let filename: String
    let current: Date?
    let systemOriginal: Date?
    let exifOriginal: Date?

    func chosen(allowExif: Bool) -> Date? {
        systemOriginal ?? (allowExif ? exifOriginal : nil)
    }
}

enum PhotoDateService {
    static func inspect(asset: PHAsset) async -> PhotoDateInfo {
        let systemOriginal = await contentEditingCreationDate(asset)
        let exif = await exifOriginalDate(asset)
        let filename = PHAssetResource.assetResources(for: asset).first?.originalFilename ?? asset.localIdentifier
        return PhotoDateInfo(id: asset.localIdentifier, filename: filename, current: asset.creationDate,
                             systemOriginal: systemOriginal, exifOriginal: exif)
    }

    private static func contentEditingCreationDate(_ asset: PHAsset) async -> Date? {
        await withCheckedContinuation { continuation in
            let options = PHContentEditingInputRequestOptions()
            options.isNetworkAccessAllowed = true
            asset.requestContentEditingInput(with: options) { input, _ in
                continuation.resume(returning: input?.creationDate)
            }
        }
    }

    private static func exifOriginalDate(_ asset: PHAsset) async -> Date? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.version = .original
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                guard let data,
                      let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                      let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
                      let raw = exif[kCGImagePropertyExifDateTimeOriginal] as? String else {
                    continuation.resume(returning: nil); return
                }
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
                formatter.timeZone = .current
                continuation.resume(returning: formatter.date(from: raw))
            }
        }
    }

    static func apply(_ infos: [PhotoDateInfo], allowExifFallback: Bool) async throws {
        let ids = infos.map(\.id)
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var assets: [String: PHAsset] = [:]
        fetched.enumerateObjects { asset, _, _ in assets[asset.localIdentifier] = asset }

        try await PHPhotoLibrary.shared().performChanges {
            for info in infos {
                guard let asset = assets[info.id],
                      let date = info.chosen(allowExif: allowExifFallback) else { continue }
                PHAssetChangeRequest(for: asset).creationDate = date
            }
        }
    }
}
