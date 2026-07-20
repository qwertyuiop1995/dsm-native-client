import AppKit
import DsmCore
import Foundation
import ImageIO

/// 从 NAS 文件前缀或完整数据中提取照片/视频元数据，用于详情面板展示。
struct PhotoMetadata: Sendable {
    let width: Int?
    let height: Int?
    let creationDate: Date?
    let cameraMake: String?
    let cameraModel: String?
    let lens: String?
    let iso: String?
    let aperture: String?
    let shutterSpeed: String?
    let focalLength: String?
    let latitude: Double?
    let longitude: Double?
    let locationText: String?
}

final class PhotoMetadataExtractor: Sendable {
    private let files: any FileRepository

    init(files: any FileRepository) {
        self.files = files
    }

    func extract(for item: FileItem) async -> PhotoMetadata? {
        guard !item.isDirectory else { return nil }
        let kind = PreviewKind.classify(item)
        guard kind == .image else { return nil }
        return await extractImageMetadata(for: item)
    }

    private func extractImageMetadata(for item: FileItem) async -> PhotoMetadata? {
        let prefixLength = 524_288 // 512 KiB，通常足以覆盖 EXIF/GPS 头部
        guard let prefix = try? await files.readPrefix(remotePath: item.path, maximumLength: prefixLength),
              !prefix.isEmpty else {
            return nil
        }

        // 先尝试用前缀解析；HEIC 等格式若头部不完整会失败。
        if let metadata = Self.parseImageMetadata(from: prefix) {
            return metadata
        }

        // 前缀失败且文件较小（<= 40 MB）时，下载完整文件再试一次。
        guard let sizeBytes = item.sizeBytes,
              sizeBytes > 0,
              sizeBytes <= 40 * 1_024 * 1_024 else {
            return nil
        }

        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("lanstash-photo-metadata-\(UUID().uuidString)")
            .appendingPathExtension(item.fileExtension ?? "jpg")

        do {
            try await files.download(remotePath: item.path, to: temporaryURL, expectedSize: sizeBytes) { _, _ in }
            let data = try Data(contentsOf: temporaryURL)
            try? FileManager.default.removeItem(at: temporaryURL)
            return Self.parseImageMetadata(from: data)
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            await files.removePartialDownload(to: temporaryURL)
            return nil
        }
    }

    static func parseImageMetadata(from data: Data) -> PhotoMetadata? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldAllowFloat: true
        ]
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options as CFDictionary) as? [String: Any] else {
            return nil
        }

        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        let gps = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any]

        let width = properties[kCGImagePropertyPixelWidth as String] as? Int
        let height = properties[kCGImagePropertyPixelHeight as String] as? Int

        let creationDate = Self.parseDate(
            from: exif?[kCGImagePropertyExifDateTimeOriginal as String] as? String
                ?? exif?[kCGImagePropertyExifDateTimeDigitized as String] as? String
                ?? tiff?[kCGImagePropertyTIFFDateTime as String] as? String
        )

        let cameraMake = (tiff?[kCGImagePropertyTIFFMake as String] as? String)?.trimmingCharacters(in: .whitespaces)
        let cameraModel = (tiff?[kCGImagePropertyTIFFModel as String] as? String)?.trimmingCharacters(in: .whitespaces)
        let lens = (exif?[kCGImagePropertyExifLensModel as String] as? String)?.trimmingCharacters(in: .whitespaces)

        let iso = Self.isoString(from: exif?[kCGImagePropertyExifISOSpeedRatings as String])
        let aperture = Self.numberString(from: exif?[kCGImagePropertyExifFNumber as String])
        let shutterSpeed = Self.rationalString(from: exif?[kCGImagePropertyExifExposureTime as String])
        let focalLength = Self.numberString(from: exif?[kCGImagePropertyExifFocalLength as String])

        let (latitude, longitude, locationText) = Self.parseGPS(gps)

        return PhotoMetadata(
            width: width,
            height: height,
            creationDate: creationDate,
            cameraMake: cameraMake,
            cameraModel: cameraModel,
            lens: lens,
            iso: iso,
            aperture: aperture,
            shutterSpeed: shutterSpeed,
            focalLength: focalLength,
            latitude: latitude,
            longitude: longitude,
            locationText: locationText
        )
    }

    private static func parseDate(from string: String?) -> Date? {
        guard let string else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: string)
    }

    private static func isoString(from value: Any?) -> String? {
        if let value = value as? [Any], let first = value.first {
            return numberString(from: first)
        }
        return numberString(from: value)
    }

    private static func numberString(from value: Any?) -> String? {
        if let number = value as? NSNumber {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            return formatter.string(from: number)
        }
        if let string = value as? String, !string.isEmpty {
            return string
        }
        return nil
    }

    private static func rationalString(from value: Any?) -> String? {
        if let string = value as? String, !string.isEmpty {
            return string
        }
        if let number = value as? NSNumber {
            let doubleValue = number.doubleValue
            if doubleValue > 0 {
                let formatter = NumberFormatter()
                formatter.maximumFractionDigits = 4
                return "1/\(Int(1 / doubleValue))" // 近似分母
            }
        }
        return nil
    }

    private static func parseGPS(_ gps: [String: Any]?) -> (Double?, Double?, String?) {
        guard let gps else { return (nil, nil, nil) }
        guard let latitudeValue = gps[kCGImagePropertyGPSLatitude as String] as? Double,
              let latRef = gps[kCGImagePropertyGPSLatitudeRef as String] as? String,
              let longitudeValue = gps[kCGImagePropertyGPSLongitude as String] as? Double,
              let lonRef = gps[kCGImagePropertyGPSLongitudeRef as String] as? String else {
            return (nil, nil, nil)
        }

        let latitude = latRef.uppercased() == "S" ? -latitudeValue : latitudeValue
        let longitude = lonRef.uppercased() == "W" ? -longitudeValue : longitudeValue
        let text = String(format: "%.5f°, %.5f°", latitude, longitude)
        return (latitude, longitude, text)
    }
}
