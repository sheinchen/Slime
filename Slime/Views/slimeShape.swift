//
//  slimeShape.swift
//  Slime
//
//  Created by shiying on 2026/7/8.
//

import Foundation
import UIKit

//抽成协议 后期换精致
protocol SlimeShapeProviding {
    func bodyPath(in rect: CGRect, emotion: SlimeEmotion) ->UIBezierPath
    func eyePaths(in rect: CGRect, emotion: SlimeEmotion) -> [UIBezierPath]
    func mouthPath(in rect: CGRect, emotion: SlimeEmotion) -> UIBezierPath
}

struct BlobSlimeShape: SlimeShapeProviding {
    func bodyPath(in rect: CGRect, emotion: SlimeEmotion) -> UIBezierPath {
        let p = UIBezierPath()
        p.move(to: CGPoint(x: 50, y: 12))
        p.addCurve(to: CGPoint(x: 90, y: 62), controlPoint1: CGPoint(x: 77, y: 12), controlPoint2: CGPoint(x: 90, y: 37))
        p.addCurve(to: CGPoint(x: 50, y: 94), controlPoint1: CGPoint(x: 90, y: 81), controlPoint2: CGPoint(x: 73, y: 94))
        p.addCurve(to: CGPoint(x: 10, y: 62), controlPoint1: CGPoint(x: 27, y: 94), controlPoint2: CGPoint(x: 10, y: 81))
        p.addCurve(to: CGPoint(x: 50, y: 12), controlPoint1: CGPoint(x: 10, y: 37), controlPoint2: CGPoint(x: 23, y: 12))
        p.close()
        p.apply(Self.fitTransform(for: rect))
        return p
                   
    }
    
    func eyePaths(in rect: CGRect, emotion: SlimeEmotion) -> [UIBezierPath] {
        let t = Self.fitTransform(for: rect)
        let r: CGFloat = 6
        let centers = [CGPoint(x: 38, y: 54), CGPoint(x: 62, y: 54)]
        return centers.map { c in
            let path = UIBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            path.apply(t)
            return path
        }
    }
    
    func mouthPath(in rect: CGRect, emotion: SlimeEmotion) -> UIBezierPath {
        let p = UIBezierPath()
        p.move(to: CGPoint(x: 41, y: 68))
        p.addQuadCurve(to: CGPoint(x: 59, y: 68), controlPoint: CGPoint(x: 50, y: 76))
        p.apply(Self.fitTransform(for: rect))
        return p
    }
    
    private static func fitTransform(for rect: CGRect) -> CGAffineTransform {
        let scale = CGAffineTransform(scaleX: rect.width / 100.0, y: rect.height / 100.0)
        let translate = CGAffineTransform(translationX: rect.minX, y: rect.minY)
        return scale.concatenating(translate)
    }
}
