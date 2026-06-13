import Foundation
import UIKit

enum ProfileImageShareEncoder {
    static let maxDimension: CGFloat = 256
    static let maxByteCount = 120_000

    static func sharedImageData(from sourceData: Data?) -> Data? {
        guard
            let sourceData,
            !sourceData.isEmpty,
            let image = UIImage(data: sourceData)
        else { return nil }

        let side = min(maxDimension, max(image.size.width, image.size.height))
        guard side > 0 else { return nil }

        let targetSize = CGSize(width: side, height: side)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resized = renderer.image { context in
            UIColor.systemBackground.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))

            let sourceSize = image.size
            let scale = max(targetSize.width / sourceSize.width, targetSize.height / sourceSize.height)
            let drawSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
            let drawOrigin = CGPoint(
                x: (targetSize.width - drawSize.width) / 2,
                y: (targetSize.height - drawSize.height) / 2
            )
            image.draw(in: CGRect(origin: drawOrigin, size: drawSize))
        }

        for quality in stride(from: 0.78, through: 0.42, by: -0.12) {
            guard let data = resized.jpegData(compressionQuality: quality) else { continue }
            if data.count <= maxByteCount {
                return data
            }
        }
        return resized.jpegData(compressionQuality: 0.36)
    }
}
