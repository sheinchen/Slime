//
//  RootPagerViewController.swift
//  Slime
//
//  Created by shiying on 2026/8/19.
//

import UIKit
import SnapKit

//分页容器的一页，负责告诉现在是不是当前页
protocol PagerPage: UIViewController {
    func pageVisibilityDidChange(isCurrent: Bool)
}

final class RootPagerViewController: UIViewController {

    private var currentIndex = 0
    
    private let scrollView = UIScrollView()
    private let dots = UIStackView()
    private var dotsViews: [UIView] = []
    private var dotWidths: [Constraint] = []
    
    private let pages: [UIViewController]
    
    init(pages: [UIViewController]) {
        self.pages = pages
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupScrollView()
        setupPages()
        setupDots()
        updateDots(progress: 0)
        notifyPageVisibility()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }
    

   // MARK: - 搭建
    private func setupScrollView() {
        scrollView.isPagingEnabled = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.bounces = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delegate = self
        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }
    
    private func setupPages() {
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fillEqually
        scrollView.addSubview(row)
        
        row.snp.makeConstraints { make in
            make.edges.equalTo(scrollView.contentLayoutGuide)
            make.height.equalTo(scrollView.frameLayoutGuide)
            make.width.equalTo(scrollView.frameLayoutGuide).multipliedBy(pages.count)
        }
        
        for page in pages {
            addChild(page) 
            row.addArrangedSubview(page.view)
            page.didMove(toParent: self)
        }
    }
    
    private func setupDots() {
        dots.axis = .horizontal
        dots.spacing = 7
        dots.alignment = .center
        view.addSubview(dots)
        
        for _ in pages.indices {
            let dot = UIView()
            dot.layer.cornerRadius = 2
            dot.snp.makeConstraints { make in
                make.height.equalTo(4)
                dotWidths.append(make.width.equalTo(4).constraint)
            }
            dots.addArrangedSubview(dot)
            dotsViews.append(dot)
        }
        dots.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalToSuperview().offset(-44)
        }
    }
    
    //MARK: - 指示器
    
    private func updateDots(progress: CGFloat) {
        for (index, width) in dotWidths.enumerated() {
            let distance = min(abs(progress - CGFloat(index)), 1)
            let t = 1 - distance
            width.update(offset: 4 + 12 * t)
            dotsViews[index].backgroundColor = Sky.ink(0.16 + 0.34 * t)
        }
    }
    
    //MARK: - 判断当前页
    private func updateCurrentPage() {
        guard scrollView.bounds.width > 0 else { return }
        let index = Int((scrollView.contentOffset.x / scrollView.bounds.width).rounded())
        guard pages.indices.contains(index), index != currentIndex else { return }
        currentIndex = index
        notifyPageVisibility()
    }
    
    private func notifyPageVisibility() {
        for (index, page) in pages.enumerated() {
            (page as? PagerPage)?.pageVisibilityDidChange(isCurrent: index == currentIndex)
        }
    }
}

// MARK: - UIScrollViewDelegate

extension RootPagerViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView.bounds.width > 0 else { return }
        updateDots(progress: scrollView.contentOffset.x / scrollView.bounds.width)
    }
    
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        updateCurrentPage()
    }
    
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { updateCurrentPage() }
    }
    
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        updateCurrentPage()
    }
}
