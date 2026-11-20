//
//  BottomPanel.swift
//  WithU
//
//  The Map tab's sliding panel. Dragging is handled in UIKit: a pan gesture
//  moves the panel's frame directly and a velocity-matched spring settles it,
//  the same technique system sheets use. SwiftUI content is hosted inside and
//  is never re-evaluated while the panel moves, so dragging and flicking stay
//  at full frame rate. Touches outside the panel fall through to the map.
//

import SwiftUI
import UIKit

struct BottomPanel<Accessory: View, Content: View>: UIViewControllerRepresentable {
    @Binding var isExpanded: Bool
    var collapsedHeight: CGFloat
    var model: AppModel
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    func makeUIViewController(context: Context) -> BottomPanelController {
        let controller = BottomPanelController()
        controller.onExpandedChange = { expanded in
            if isExpanded != expanded { isExpanded = expanded }
        }
        return controller
    }

    func updateUIViewController(_ controller: BottomPanelController, context: Context) {
        controller.onExpandedChange = { expanded in
            if isExpanded != expanded { isExpanded = expanded }
        }
        // Hosted views don't inherit the SwiftUI environment, so pass the model on.
        controller.setContent(
            AnyView(content().environment(model)),
            accessory: AnyView(accessory().environment(model))
        )
        controller.setCollapsedHeight(collapsedHeight)
        controller.setExpanded(isExpanded, animated: true)
    }
}

/// Lets touches that miss the panel and its buttons reach the map underneath.
private final class PassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}

final class BottomPanelController: UIViewController, UIGestureRecognizerDelegate {
    var onExpandedChange: (Bool) -> Void = { _ in }

    private let panelHost = UIHostingController(rootView: AnyView(EmptyView()))
    private let accessoryHost = UIHostingController(rootView: AnyView(EmptyView()))
    /// Fills the gap below the panel (behind the tab bar) while it rubber-bands.
    private let bottomCover = UIView()

    private var collapsedHeight: CGFloat = 360
    private var isExpanded = false
    /// 0 when expanded, `travel` when collapsed.
    private var offset: CGFloat = 0
    private var dragStartOffset: CGFloat = 0
    private var isDragging = false
    private var animator: UIViewPropertyAnimator?
    private var hasLaidOut = false

    private var expandedHeight: CGFloat {
        max(view.bounds.height * 0.92, collapsedHeight + 120)
    }

    private var travel: CGFloat { max(expandedHeight - collapsedHeight, 1) }

    // MARK: Setup

    override func loadView() {
        view = PassthroughView()
        view.backgroundColor = .clear
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        for host in [panelHost, accessoryHost] {
            addChild(host)
            host.view.backgroundColor = .clear
            host.safeAreaRegions = []
        }
        view.clipsToBounds = false
        bottomCover.backgroundColor = UIColor(Theme.cream)
        view.addSubview(bottomCover)
        view.addSubview(panelHost.view)
        view.addSubview(accessoryHost.view)
        panelHost.didMove(toParent: self)
        accessoryHost.didMove(toParent: self)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        panelHost.view.addGestureRecognizer(pan)
    }

    func setContent(_ content: AnyView, accessory: AnyView) {
        panelHost.rootView = content
        accessoryHost.rootView = accessory
    }

    func setCollapsedHeight(_ height: CGFloat) {
        guard height != collapsedHeight else { return }
        collapsedHeight = height
        guard !isDragging, animator?.isRunning != true else { return }
        offset = isExpanded ? 0 : travel
        UIView.animate(withDuration: 0.25) { self.layoutPanel() }
    }

    /// Driven from SwiftUI (handle tap, pull-down, picking a place).
    func setExpanded(_ expanded: Bool, animated: Bool) {
        guard expanded != isExpanded, !isDragging else { return }
        if hasLaidOut && animated {
            settle(expanded: expanded, velocity: 0)
        } else {
            isExpanded = expanded
            offset = expanded ? 0 : travel
            view.setNeedsLayout()
        }
    }

    // MARK: Layout

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !isDragging, animator?.isRunning != true else { return }
        offset = isExpanded ? 0 : travel
        layoutPanel()
        hasLaidOut = true
    }

    private func layoutPanel() {
        let bounds = view.bounds
        let top = bounds.height - expandedHeight + offset
        panelHost.view.frame = CGRect(x: 0, y: top, width: bounds.width, height: expandedHeight)
        bottomCover.frame = CGRect(x: 0, y: panelHost.view.frame.maxY - 1, width: bounds.width, height: 400)

        let size = accessoryHost.sizeThatFits(in: CGSize(width: bounds.width, height: 400))
        accessoryHost.view.frame = CGRect(x: bounds.width - size.width - 16,
                                          y: top - size.height - 12,
                                          width: size.width,
                                          height: size.height)
        // Map buttons fade out as the panel opens.
        let openness = 1 - min(max(offset / travel, 0), 1)
        accessoryHost.view.alpha = 1 - min(openness * 2, 1)
        accessoryHost.view.isUserInteractionEnabled = openness < 0.5
    }

    // MARK: Dragging

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began:
            // Catch the panel mid-flight if it's still settling.
            if let animator, animator.isRunning,
               let presented = panelHost.view.layer.presentation()?.frame.minY {
                animator.stopAnimation(true)
                offset = presented - (view.bounds.height - expandedHeight)
                layoutPanel()
            }
            animator = nil
            isDragging = true
            dragStartOffset = offset

        case .changed:
            let proposed = dragStartOffset + pan.translation(in: view).y
            offset = rubberBand(proposed)
            layoutPanel()

        case .ended, .cancelled, .failed:
            isDragging = false
            let velocity = pan.velocity(in: view).y
            // Where a flick would carry the panel.
            let projected = offset + velocity * 0.18
            settle(expanded: projected < travel / 2, velocity: velocity)

        default:
            break
        }
    }

    private func rubberBand(_ value: CGFloat) -> CGFloat {
        if value < 0 { return value / 3 }
        if value > travel { return travel + (value - travel) / 3 }
        return value
    }

    private func settle(expanded: Bool, velocity: CGFloat) {
        animator?.stopAnimation(true)
        let target: CGFloat = expanded ? 0 : travel
        let distance = target - offset
        let relativeVelocity = abs(distance) > 1 ? velocity / distance : 0
        let timing = UISpringTimingParameters(dampingRatio: 0.9,
                                              initialVelocity: CGVector(dx: 0, dy: relativeVelocity))
        let animator = UIViewPropertyAnimator(duration: 0.42, timingParameters: timing)
        offset = target
        animator.addAnimations { [weak self] in self?.layoutPanel() }
        animator.startAnimation()
        self.animator = animator

        if expanded != isExpanded {
            isExpanded = expanded
            onExpandedChange(expanded)
        }
    }

    // MARK: UIGestureRecognizerDelegate

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: view)
        // Leave sideways swipes to the circle chips and recents.
        guard abs(velocity.y) > abs(velocity.x) else { return false }
        // Collapsed: drag anywhere. Expanded: drag by the handle; the list scrolls.
        return !isExpanded || pan.location(in: panelHost.view).y < 44
    }
}
