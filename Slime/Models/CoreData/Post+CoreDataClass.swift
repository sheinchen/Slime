//
//  Post+CoreDataClass.swift
//  Slime
//
//  Created by shiying on 2026/7/4.
//
//

public import Foundation
public import CoreData

public typealias PostCoreDataClassSet = NSSet

@objc(Post)
public class Post: NSManagedObject {

}

extension Post {
    /// 读情绪只走这一个口。
    ///
    /// nil = 这篇 AI 还没读过。**千万别兜成 `?? .calm`** —— 那样它看起来像被分析过、
    /// 其实没有，正是切片 6 要防的「伪造」。以前库里 emotion 是必填、默认 calm，
    /// 切片 5 之前的老帖子就是这样被迁移悄悄填成 calm 的。
    var slimeEmotion: SlimeEmotion? {
        emotion.flatMap(SlimeEmotion.init(rawValue:))
    }
}
