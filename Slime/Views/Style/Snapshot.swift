//
//  Snapshot.swift
//  Slime
//
//  Created by shiying on 2026/8/22.
//

import Foundation
import UIKit

extension UIView {
    func blurredSnapshot(radius: CGFloat = 10) -> UIImage? {
        let scale: CGFloat = 0.3
        let size = CGSize(width: bounds.width * scale, height: bounds.height *  scale)
//        guard size.width > 1, size.height > 1 else { return nil }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque  = true
        
        let shot = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
        guard let input = CIImage(image: shot),
              let filter = CIFilter(name: "CIGaussianBlur")
        else { return nil }
        
        filter.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(radius * scale, forKey: kCIInputRadiusKey)
        
        guard let output = filter.outputImage,
              let cgImage = CIContext().createCGImage(output, from: input.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
