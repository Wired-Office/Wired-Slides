import AppKit
import AVFoundation
import QuartzCore

/// Shows one slide as Core Animation layers and plays its builds and transitions.
/// The stage's `content` layer uses slide coordinates (points, y down).
final class SlideStage: NSView {
    private(set) var presentation: Presentation
    let root = CALayer()
    /// Holds the current slide's layers, scaled to fit.
    private(set) var content = CALayer()
    private var elementLayers: [UUID: CALayer] = [:]
    private var playerLayers: [UUID: AVPlayerLayer] = [:]
    private var players: [UUID: AVPlayer] = [:]
    private(set) var slideIndex = 0
    private(set) var plan = SlideBuildPlan(Slide(layout: .blank))
    /// The next step to run (0 = the automatic step).
    private(set) var nextStep = 0
    private var stepEndsAt: CFTimeInterval = 0
    var animationsEnabled = true
    /// Called when a step or transition finishes.
    var onIdle: (() -> Void)?
    private var tempFiles: [URL] = []

    init(presentation: Presentation) {
        self.presentation = presentation
        super.init(frame: NSRect(x: 0, y: 0, width: 960, height: 540))
        wantsLayer = true
        layer = root
        root.backgroundColor = NSColor.black.cgColor
        root.masksToBounds = true
        layerContentsRedrawPolicy = .never
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        players.values.forEach { $0.pause() }
        for url in tempFiles { try? FileManager.default.removeItem(at: url) }
    }

    func update(_ presentation: Presentation) { self.presentation = presentation }

    var slideSize: CGSize { presentation.slideSize }

    /// Pixel density for rendering layer images.
    private var pixelScale: CGFloat {
        let backing = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        return fitScale * backing
    }

    private var fitScale: CGFloat {
        min(bounds.width / max(slideSize.width, 1), bounds.height / max(slideSize.height, 1))
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        position(content)
        CATransaction.commit()
    }

    /// Scales and centers a slide container in the view.
    private func position(_ layer: CALayer) {
        layer.bounds = CGRect(origin: .zero, size: slideSize)
        layer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        let s = fitScale
        layer.transform = CATransform3DMakeScale(s, s, 1)
    }

    // MARK: - Building a slide

    /// Makes the layers for a slide in its starting state (entrance-animated elements hidden),
    /// or fully built when `built` is true.
    func makeContainer(for index: Int, built: Bool, allElementLayers: Bool = false) -> (CALayer, [UUID: CALayer], SlideBuildPlan) {
        let slide = presentation.slides[index]
        let plan = SlideBuildPlan(slide, animated: animationsEnabled)
        let container = CALayer()
        container.isGeometryFlipped = true
        container.masksToBounds = true
        position(container)
        let animated = plan.animatedElements
        let media = Set(slide.elements.filter { if case .media = $0.content { return true }; return false }.map(\.id))
        let separate = allElementLayers ? Set(slide.elements.map(\.id)) : animated.union(media)

        // Background, theme graphics, footers and static elements in one image.
        var options = SlideDrawOptions()
        options.skip = separate
        let background = CALayer()
        background.frame = CGRect(origin: .zero, size: slideSize)
        background.contents = SlideRenderer.cgImage(slide, number: index + 1, presentation: presentation, pixelWidth: slideSize.width * pixelScale, options: options)
        background.contentsGravity = .resize
        container.addSublayer(background)

        var layers: [UUID: CALayer] = [:]
        let hidden = built ? Set<UUID>() : plan.initiallyHidden
        for e in slide.elements where separate.contains(e.id) && !e.hidden {
            let layer = makeElementLayer(e, slideNumber: index + 1)
            if hidden.contains(e.id) { layer.opacity = 0 }
            if case .media(let m) = e.content, m.hideWhenNotPlaying, !m.autoplay { layer.opacity = 0 }
            container.addSublayer(layer)
            layers[e.id] = layer
        }
        if built {
            // Apply the end state of every animation (exits hide, emphasis persists).
            for item in plan.steps.flatMap({ $0 }) {
                guard let layer = layers[item.animation.elementID], let e = slide.element(item.animation.elementID) else { continue }
                applyFinalState(item.animation, to: layer, element: e)
            }
        }
        return (container, layers, plan)
    }

    private func makeElementLayer(_ e: SlideElement, slideNumber: Int) -> CALayer {
        var flat = e
        flat.rotation = 0
        let bounds = SlideRenderer.visualBounds(flat)
        let layer = CALayer()
        layer.bounds = CGRect(origin: .zero, size: bounds.size)
        layer.anchorPoint = CGPoint(x: (e.frame.midX - bounds.minX) / max(bounds.width, 1), y: (e.frame.midY - bounds.minY) / max(bounds.height, 1))
        layer.position = CGPoint(x: e.frame.midX, y: e.frame.midY)
        layer.contents = SlideRenderer.elementImage(flat, presentation: presentation, scale: pixelScale, slideNumber: slideNumber)
        layer.contentsGravity = .resize
        layer.transform = CATransform3DMakeRotation(CGFloat(e.rotation * .pi / 180), 0, 0, 1)
        layer.name = e.id.uuidString
        if case .media(let m) = e.content, m.kind == .video, let item = presentation.media[m.mediaID] {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("ws-\(m.mediaID)")
            if !FileManager.default.fileExists(atPath: url.path) { try? item.data.write(to: url); tempFiles.append(url) }
            let player = AVPlayer(url: url)
            player.volume = Float(m.volume)
            let playerLayer = AVPlayerLayer(player: player)
            playerLayer.frame = CGRect(x: e.frame.minX - (layer.position.x - layer.bounds.width * layer.anchorPoint.x), y: e.frame.minY - (layer.position.y - layer.bounds.height * layer.anchorPoint.y),
                                       width: e.frame.width, height: e.frame.height)
            playerLayer.videoGravity = .resizeAspect
            playerLayer.opacity = 0
            layer.addSublayer(playerLayer)
            playerLayers[e.id] = playerLayer
            players[e.id] = player
            if m.loop { loop(player) }
        } else if case .media(let m) = e.content, m.kind == .audio, let item = presentation.media[m.mediaID] {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("ws-\(m.mediaID)")
            if !FileManager.default.fileExists(atPath: url.path) { try? item.data.write(to: url); tempFiles.append(url) }
            let player = AVPlayer(url: url)
            player.volume = Float(m.volume)
            players[e.id] = player
            if m.loop { loop(player) }
        }
        return layer
    }

    private func loop(_ player: AVPlayer) {
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }
    }

    /// Plays or pauses a media element (clicking it during the show).
    func toggleMedia(_ id: UUID) {
        guard let player = players[id] else { return }
        if player.rate > 0 { player.pause() } else {
            if player.currentTime() >= (player.currentItem?.duration ?? .zero), player.currentItem?.duration.isNumeric == true { player.seek(to: .zero) }
            playerLayers[id]?.opacity = 1
            elementLayers[id]?.opacity = 1
            player.play()
        }
    }

    private func stopMedia() {
        players.values.forEach { $0.pause() }
        players = [:]
        playerLayers = [:]
    }

    private func startAutoplayMedia() {
        for e in presentation.slides[slideIndex].elements {
            if case .media(let m) = e.content, m.autoplay { toggleMedia(e.id) }
        }
    }

    /// The media element at a point in view coordinates.
    func mediaElement(at viewPoint: CGPoint) -> UUID? {
        let p = slidePoint(viewPoint)
        return presentation.slides[slideIndex].elements.reversed().first { e in
            if case .media = e.content { return CanvasGeometry.contains(e, p, tolerance: 2) }
            return false
        }?.id
    }

    func slidePoint(_ viewPoint: CGPoint) -> CGPoint {
        let s = fitScale
        let w = slideSize.width * s, h = slideSize.height * s
        let origin = CGPoint(x: bounds.midX - w / 2, y: bounds.midY - h / 2)
        // View coordinates are y-up here.
        return CGPoint(x: (viewPoint.x - origin.x) / s, y: (bounds.height - viewPoint.y - (bounds.height - origin.y - h)) / s)
    }

    /// Shows a slide immediately (no transition).
    func show(_ index: Int, built: Bool) {
        stopMedia()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let (container, layers, plan) = makeContainer(for: index, built: built)
        content.removeFromSuperlayer()
        root.addSublayer(container)
        content = container
        elementLayers = layers
        self.plan = plan
        slideIndex = index
        nextStep = built ? plan.steps.count : 0
        CATransaction.commit()
        startAutoplayMedia()
        if !built { runStep() }
    }

    // MARK: - Steps

    var hasMoreSteps: Bool { nextStep < plan.steps.count }
    var isAnimating: Bool { CACurrentMediaTime() < stepEndsAt }

    /// Runs the next build step. Returns false when the slide is fully built.
    @discardableResult
    func runStep() -> Bool {
        guard hasMoreSteps else { return false }
        let step = plan.steps[nextStep]
        nextStep += 1
        let now = CACurrentMediaTime()
        let slide = presentation.slides[slideIndex]
        for item in step {
            guard let layer = elementLayers[item.animation.elementID], let e = slide.element(item.animation.elementID) else { continue }
            animate(item.animation, layer: layer, element: e, begin: now + item.start)
        }
        stepEndsAt = now + plan.duration(of: nextStep - 1)
        // The automatic step can be empty; click steps chain into following automatic ones.
        if step.isEmpty, nextStep == 1 { return true }
        DispatchQueue.main.asyncAfter(deadline: .now() + max(plan.duration(of: nextStep - 1), 0) + 0.02) { [weak self] in
            self?.onIdle?()
        }
        return true
    }

    /// Jumps every running animation to its end.
    func finishAnimations() {
        guard isAnimating else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in elementLayers.values {
            layer.removeAllAnimations()
            layer.mask?.removeAllAnimations()
        }
        CATransaction.commit()
        stepEndsAt = 0
    }

    private func applyFinalState(_ a: SlideAnimation, to layer: CALayer, element e: SlideElement) {
        let rotation = CATransform3DMakeRotation(CGFloat(e.rotation * .pi / 180), 0, 0, 1)
        switch a.effect.category {
        case .entrance:
            layer.opacity = 1
            layer.transform = rotation
            layer.position = CGPoint(x: e.frame.midX, y: e.frame.midY)
        case .exit:
            layer.opacity = 0
        case .emphasis:
            switch a.effect {
            case .growShrink: layer.transform = CATransform3DScale(rotation, 1.5 * a.amount, 1.5 * a.amount, 1)
            case .transparency: layer.opacity = 0.5
            default: break
            }
        case .motionPath:
            let end = motionPath(a, element: e).currentPoint
            layer.position = end
        }
        layer.mask = nil
    }

    // MARK: - Effects

    private func offscreenOffset(_ direction: MotionDirection, element e: SlideElement) -> CGSize {
        switch direction {
        case .fromBottom: return CGSize(width: 0, height: slideSize.height - e.frame.minY + 20)
        case .fromTop: return CGSize(width: 0, height: -(e.frame.maxY + 20))
        case .fromLeft: return CGSize(width: -(e.frame.maxX + 20), height: 0)
        case .fromRight: return CGSize(width: slideSize.width - e.frame.minX + 20, height: 0)
        }
    }

    private func motionPath(_ a: SlideAnimation, element e: SlideElement) -> CGMutablePath {
        let start = CGPoint(x: e.frame.midX, y: e.frame.midY)
        let distance = 150 * CGFloat(a.amount)
        var d = CGSize.zero
        switch a.direction {
        case .fromBottom: d.height = -distance
        case .fromTop: d.height = distance
        case .fromLeft: d.width = distance
        case .fromRight: d.width = -distance
        }
        let path = CGMutablePath()
        path.move(to: start)
        switch a.effect {
        case .pathArc:
            let end = CGPoint(x: start.x + d.width, y: start.y + d.height)
            let control = CGPoint(x: (start.x + end.x) / 2 + d.height * 0.6, y: (start.y + end.y) / 2 - abs(d.width) * 0.6 - (d.width == 0 ? 0 : 0))
            path.addQuadCurve(to: end, control: control)
        case .pathCircle:
            let r = 70 * CGFloat(a.amount)
            path.addArc(center: CGPoint(x: start.x, y: start.y + r), radius: r, startAngle: -.pi / 2, endAngle: 1.5 * .pi, clockwise: false)
        case .pathZigzag:
            for i in 1...4 {
                let t = CGFloat(i) / 4
                let wiggle: CGFloat = (i % 2 == 0 ? -1 : 1) * 30
                path.addLine(to: CGPoint(x: start.x + d.width * t + (d.width == 0 ? wiggle : 0), y: start.y + d.height * t + (d.height == 0 ? wiggle : 0)))
            }
        default:
            path.addLine(to: CGPoint(x: start.x + d.width, y: start.y + d.height))
        }
        return path
    }

    private func animate(_ a: SlideAnimation, layer: CALayer, element e: SlideElement, begin: CFTimeInterval) {
        let duration = max(a.duration, 0.01)
        let rotation = CATransform3DMakeRotation(CGFloat(e.rotation * .pi / 180), 0, 0, 1)
        let final = CGPoint(x: e.frame.midX, y: e.frame.midY)
        func basic(_ key: String, from: Any?, to: Any?, timing: CAMediaTimingFunctionName = .easeInEaseOut) -> CABasicAnimation {
            let anim = CABasicAnimation(keyPath: key)
            anim.fromValue = from
            anim.toValue = to
            anim.duration = duration
            anim.beginTime = begin
            anim.fillMode = .both
            anim.timingFunction = CAMediaTimingFunction(name: timing)
            anim.repeatCount = Float(max(a.repeatCount, 1))
            return anim
        }
        func keyframes(_ key: String, _ values: [Any], times: [NSNumber]? = nil) -> CAKeyframeAnimation {
            let anim = CAKeyframeAnimation(keyPath: key)
            anim.values = values
            anim.keyTimes = times
            anim.duration = duration
            anim.beginTime = begin
            anim.fillMode = .both
            anim.repeatCount = Float(max(a.repeatCount, 1))
            return anim
        }
        func mask(_ from: CGRect, _ to: CGRect) {
            let m = CALayer()
            m.backgroundColor = NSColor.black.cgColor
            m.frame = to
            layer.mask = m
            let anim = basic("bounds", from: NSValue(rect: CGRect(origin: .zero, size: from.size)), to: NSValue(rect: CGRect(origin: .zero, size: to.size)))
            let pos = basic("position", from: NSValue(point: CGPoint(x: from.midX, y: from.midY)), to: NSValue(point: CGPoint(x: to.midX, y: to.midY)))
            m.add(anim, forKey: "wipe-bounds")
            m.add(pos, forKey: "wipe-position")
        }
        let b = layer.bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        switch a.effect {
        // Entrances
        case .appear:
            layer.opacity = 1
            layer.add(basic("opacity", from: 0, to: 1), forKey: "fx")
        case .fadeIn:
            layer.opacity = 1
            layer.add(basic("opacity", from: 0, to: 1), forKey: "fx")
        case .flyIn:
            layer.opacity = 1
            let o = offscreenOffset(a.direction, element: e)
            layer.position = final
            layer.add(basic("position", from: NSValue(point: CGPoint(x: final.x + o.width, y: final.y + o.height)), to: NSValue(point: final), timing: .easeOut), forKey: "fx")
        case .floatIn:
            layer.opacity = 1
            layer.position = final
            let o = a.direction == .fromTop ? -40.0 : a.direction == .fromBottom ? 40.0 : 0
            let ox = a.direction == .fromLeft ? -40.0 : a.direction == .fromRight ? 40.0 : 0
            let group = CAAnimationGroup()
            group.animations = [basic("opacity", from: 0, to: 1), basic("position", from: NSValue(point: CGPoint(x: final.x + ox, y: final.y + o)), to: NSValue(point: final), timing: .easeOut)]
            group.duration = duration; group.beginTime = begin; group.fillMode = .both
            group.animations?.forEach { $0.beginTime = 0 }
            layer.add(group, forKey: "fx")
        case .wipeIn:
            layer.opacity = 1
            let start: CGRect
            switch a.direction {
            case .fromLeft: start = CGRect(x: 0, y: 0, width: 0, height: b.height)
            case .fromRight: start = CGRect(x: b.width, y: 0, width: 0, height: b.height)
            case .fromTop: start = CGRect(x: 0, y: 0, width: b.width, height: 0)
            case .fromBottom: start = CGRect(x: 0, y: b.height, width: b.width, height: 0)
            }
            mask(start, b)
        case .splitIn:
            layer.opacity = 1
            mask(CGRect(x: b.midX, y: 0, width: 0, height: b.height), b)
        case .zoomIn:
            layer.opacity = 1
            layer.transform = rotation
            layer.add(basic("transform", from: NSValue(caTransform3D: CATransform3DScale(rotation, 0.2, 0.2, 1)), to: NSValue(caTransform3D: rotation), timing: .easeOut), forKey: "fx")
            layer.add(basic("opacity", from: 0, to: 1), forKey: "fx2")
        case .growTurnIn:
            layer.opacity = 1
            layer.transform = rotation
            layer.add(basic("transform", from: NSValue(caTransform3D: CATransform3DRotate(CATransform3DScale(rotation, 0.1, 0.1, 1), -.pi / 2, 0, 0, 1)),
                            to: NSValue(caTransform3D: rotation), timing: .easeOut), forKey: "fx")
            layer.add(basic("opacity", from: 0, to: 1), forKey: "fx2")
        case .swivelIn:
            layer.opacity = 1
            layer.transform = rotation
            var start = rotation
            start.m34 = -1 / 500
            start = CATransform3DRotate(start, .pi / 2, 0, 1, 0)
            layer.add(basic("transform", from: NSValue(caTransform3D: start), to: NSValue(caTransform3D: rotation), timing: .easeOut), forKey: "fx")
        case .bounceIn:
            layer.opacity = 1
            layer.position = final
            let high = CGPoint(x: final.x, y: final.y - 220)
            let points = [high, final, CGPoint(x: final.x, y: final.y - 60), final, CGPoint(x: final.x, y: final.y - 18), final].map { NSValue(point: $0) }
            let anim = keyframes("position", points, times: [0, 0.4, 0.6, 0.78, 0.9, 1])
            anim.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeIn), count: 5)
            layer.add(anim, forKey: "fx")
            layer.add(basic("opacity", from: 0, to: 1), forKey: "fx2")
        case .spinIn:
            layer.opacity = 1
            layer.transform = rotation
            layer.add(basic("transform", from: NSValue(caTransform3D: CATransform3DRotate(CATransform3DScale(rotation, 0.3, 0.3, 1), -2 * .pi + 0.001, 0, 0, 1)),
                            to: NSValue(caTransform3D: rotation), timing: .easeOut), forKey: "fx")
            layer.add(basic("opacity", from: 0, to: 1), forKey: "fx2")
        // Emphasis
        case .pulse:
            layer.add(keyframes("transform", [rotation, CATransform3DScale(rotation, 1.12, 1.12, 1), rotation].map { NSValue(caTransform3D: $0) }), forKey: "fx")
        case .spin:
            let anim = basic("transform.rotation.z", from: CGFloat(e.rotation * .pi / 180), to: CGFloat(e.rotation * .pi / 180) + 2 * .pi * CGFloat(a.amount))
            layer.add(anim, forKey: "fx")
        case .growShrink:
            let target = CATransform3DScale(rotation, 1.5 * a.amount, 1.5 * a.amount, 1)
            layer.transform = target
            layer.add(basic("transform", from: NSValue(caTransform3D: rotation), to: NSValue(caTransform3D: target)), forKey: "fx")
        case .teeter:
            let values = [0, 0.09, -0.09, 0.06, -0.06, 0].map { NSValue(caTransform3D: CATransform3DRotate(rotation, $0, 0, 0, 1)) }
            layer.add(keyframes("transform", values), forKey: "fx")
        case .transparency:
            layer.opacity = 0.5
            layer.add(basic("opacity", from: 1, to: 0.5), forKey: "fx")
        case .colorPulse:
            layer.add(keyframes("opacity", [1, 0.35, 1, 0.35, 1]), forKey: "fx")
        case .wave:
            let values = [0, -12, 8, -4, 0].map { NSValue(point: CGPoint(x: final.x, y: final.y + $0)) }
            layer.add(keyframes("position", values), forKey: "fx")
        // Exits
        case .disappear:
            layer.opacity = 0
            layer.add(basic("opacity", from: 1, to: 0), forKey: "fx")
        case .fadeOut:
            layer.opacity = 0
            layer.add(basic("opacity", from: 1, to: 0), forKey: "fx")
        case .flyOut:
            let o = offscreenOffset(a.direction, element: e)
            let end = CGPoint(x: final.x + o.width, y: final.y + o.height)
            layer.opacity = 0
            let group = CAAnimationGroup()
            let move = basic("position", from: NSValue(point: final), to: NSValue(point: end), timing: .easeIn)
            let keep = basic("opacity", from: 1, to: 1)
            move.beginTime = 0; keep.beginTime = 0
            group.animations = [move, keep]
            group.duration = duration; group.beginTime = begin; group.fillMode = .backwards
            layer.add(group, forKey: "fx")
        case .floatOut:
            layer.opacity = 0
            let o: CGFloat = a.direction == .fromTop ? 40 : -40
            let group = CAAnimationGroup()
            let move = basic("position", from: NSValue(point: final), to: NSValue(point: CGPoint(x: final.x, y: final.y + o)))
            let fade = basic("opacity", from: 1, to: 0)
            move.beginTime = 0; fade.beginTime = 0
            group.animations = [move, fade]
            group.duration = duration; group.beginTime = begin; group.fillMode = .backwards
            layer.add(group, forKey: "fx")
        case .wipeOut, .splitOut:
            layer.opacity = 0
            let fade = basic("opacity", from: 1, to: 1)
            fade.fillMode = .backwards
            layer.add(fade, forKey: "fx-keep")
            let end: CGRect
            if a.effect == .splitOut { end = CGRect(x: b.midX, y: 0, width: 0, height: b.height) } else {
                switch a.direction {
                case .fromLeft: end = CGRect(x: b.width, y: 0, width: 0, height: b.height)
                case .fromRight: end = CGRect(x: 0, y: 0, width: 0, height: b.height)
                case .fromTop: end = CGRect(x: 0, y: b.height, width: b.width, height: 0)
                case .fromBottom: end = CGRect(x: 0, y: 0, width: b.width, height: 0)
                }
            }
            mask(b, end)
        case .zoomOut, .shrinkTurnOut:
            layer.opacity = 0
            let end = a.effect == .zoomOut ? CATransform3DScale(rotation, 0.2, 0.2, 1) : CATransform3DRotate(CATransform3DScale(rotation, 0.1, 0.1, 1), .pi / 2, 0, 0, 1)
            let group = CAAnimationGroup()
            let t = basic("transform", from: NSValue(caTransform3D: rotation), to: NSValue(caTransform3D: end), timing: .easeIn)
            let fade = basic("opacity", from: 1, to: 0)
            t.beginTime = 0; fade.beginTime = 0
            group.animations = [t, fade]
            group.duration = duration; group.beginTime = begin; group.fillMode = .backwards
            layer.add(group, forKey: "fx")
        case .swivelOut:
            layer.opacity = 0
            var end = rotation
            end.m34 = -1 / 500
            end = CATransform3DRotate(end, .pi / 2, 0, 1, 0)
            let group = CAAnimationGroup()
            let t = basic("transform", from: NSValue(caTransform3D: rotation), to: NSValue(caTransform3D: end), timing: .easeIn)
            let keep = basic("opacity", from: 1, to: 1)
            t.beginTime = 0; keep.beginTime = 0
            group.animations = [t, keep]
            group.duration = duration; group.beginTime = begin; group.fillMode = .backwards
            layer.add(group, forKey: "fx")
        case .bounceOut:
            layer.opacity = 0
            let points = [final, CGPoint(x: final.x, y: final.y - 40), CGPoint(x: final.x, y: slideSize.height + e.frame.height)].map { NSValue(point: $0) }
            let group = CAAnimationGroup()
            let move = keyframes("position", points, times: [0, 0.3, 1])
            let keep = basic("opacity", from: 1, to: 1)
            move.beginTime = 0; keep.beginTime = 0
            group.animations = [move, keep]
            group.duration = duration; group.beginTime = begin; group.fillMode = .backwards
            layer.add(group, forKey: "fx")
        // Motion paths
        case .pathLine, .pathArc, .pathCircle, .pathZigzag:
            let path = motionPath(a, element: e)
            let anim = CAKeyframeAnimation(keyPath: "position")
            anim.path = path
            anim.duration = duration
            anim.beginTime = begin
            anim.fillMode = .both
            anim.calculationMode = .paced
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.position = path.currentPoint
            layer.add(anim, forKey: "fx")
        }
        CATransaction.commit()
        if case .media = e.content, a.effect.category == .entrance, let player = players[e.id] {
            DispatchQueue.main.asyncAfter(deadline: .now() + max(begin - CACurrentMediaTime(), 0)) { player.play() }
        }
    }

    // MARK: - Transitions

    /// Moves to a slide, playing the incoming slide's transition.
    func transition(to index: Int, backwards: Bool = false, completion: (() -> Void)? = nil) {
        let slide = presentation.slides[index]
        let t = slide.transition
        guard animationsEnabled || t.kind == .fade, t.kind != .none, !backwards else {
            show(index, built: backwards)
            completion?()
            return
        }
        stopMedia()
        let old = content
        let oldLayers = elementLayers
        let oldSlide = presentation.slides[slideIndex]
        let morph = t.kind == .morph
        let (incoming, layers, plan) = makeContainer(for: index, built: false, allElementLayers: morph)
        let duration = max(t.duration, 0.05)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.addSublayer(incoming)
        CATransaction.commit()

        let w = slideSize.width, h = slideSize.height
        var offset = CGSize.zero
        switch t.direction {
        case .fromRight: offset = CGSize(width: w, height: 0)
        case .fromLeft: offset = CGSize(width: -w, height: 0)
        case .fromBottom: offset = CGSize(width: 0, height: h)
        case .fromTop: offset = CGSize(width: 0, height: -h)
        }
        let s = fitScale
        let screenOffset = CGSize(width: offset.width * s, height: -offset.height * s)  // root layer is y-up
        let center = incoming.position
        func anim(_ key: String, _ from: Any?, _ to: Any?, delay: Double = 0, d: Double? = nil) -> CABasicAnimation {
            let a = CABasicAnimation(keyPath: key)
            a.fromValue = from
            a.toValue = to
            a.duration = d ?? duration
            a.beginTime = CACurrentMediaTime() + delay
            a.fillMode = .both
            a.isRemovedOnCompletion = false
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            return a
        }
        func moved(_ p: CGPoint, _ d: CGSize) -> NSValue { NSValue(point: CGPoint(x: p.x + d.width, y: p.y + d.height)) }

        switch t.kind {
        case .none:
            break
        case .fade, .dissolve:
            if t.kind == .dissolve {
                incoming.mask = dissolveMask(duration: duration)
            } else {
                incoming.add(anim("opacity", 0, 1), forKey: "t")
            }
        case .fadeThroughBlack:
            old.add(anim("opacity", 1, 0, d: duration / 2), forKey: "t")
            incoming.add(anim("opacity", 0, 1, delay: duration / 2, d: duration / 2), forKey: "t")
        case .push:
            incoming.add(anim("position", moved(center, screenOffset), NSValue(point: center)), forKey: "t")
            old.add(anim("position", NSValue(point: center), moved(center, CGSize(width: -screenOffset.width, height: -screenOffset.height))), forKey: "t")
        case .cover:
            incoming.add(anim("position", moved(center, screenOffset), NSValue(point: center)), forKey: "t")
        case .reveal, .uncover:
            // The old slide moves away, revealing the new one beneath.
            incoming.removeFromSuperlayer()
            root.insertSublayer(incoming, below: old)
            old.add(anim("position", NSValue(point: center), moved(center, CGSize(width: -screenOffset.width, height: -screenOffset.height))), forKey: "t")
            if t.kind == .reveal { old.add(anim("opacity", 1, 0.2), forKey: "t2") }
        case .wipe:
            let m = CALayer()
            m.backgroundColor = NSColor.black.cgColor
            m.anchorPoint = .zero
            let full = CGRect(origin: .zero, size: CGSize(width: w, height: h))
            var start = full
            switch t.direction {
            case .fromRight: start = CGRect(x: w, y: 0, width: 0, height: h)
            case .fromLeft: start = CGRect(x: 0, y: 0, width: 0, height: h)
            case .fromBottom: start = CGRect(x: 0, y: h, width: w, height: 0)
            case .fromTop: start = CGRect(x: 0, y: 0, width: w, height: 0)
            }
            m.frame = full
            incoming.mask = m
            m.add(anim("bounds", NSValue(rect: CGRect(origin: .zero, size: start.size)), NSValue(rect: CGRect(origin: .zero, size: full.size))), forKey: "t")
            m.add(anim("position", NSValue(point: start.origin), NSValue(point: .zero)), forKey: "t2")
        case .split:
            let m = CALayer()
            m.backgroundColor = NSColor.black.cgColor
            m.frame = CGRect(x: 0, y: 0, width: w, height: h)
            incoming.mask = m
            m.add(anim("bounds", NSValue(rect: CGRect(x: 0, y: 0, width: 0, height: h)), NSValue(rect: CGRect(x: 0, y: 0, width: w, height: h))), forKey: "t")
        case .zoom:
            incoming.add(anim("transform", NSValue(caTransform3D: CATransform3DMakeScale(s * 0.3, s * 0.3, 1)), NSValue(caTransform3D: CATransform3DMakeScale(s, s, 1))), forKey: "t")
            incoming.add(anim("opacity", 0, 1), forKey: "t2")
            old.add(anim("transform", NSValue(caTransform3D: CATransform3DMakeScale(s, s, 1)), NSValue(caTransform3D: CATransform3DMakeScale(s * 1.6, s * 1.6, 1))), forKey: "t3")
            old.add(anim("opacity", 1, 0), forKey: "t4")
        case .flip, .cube:
            var perspective = CATransform3DIdentity
            perspective.m34 = -1 / 1400
            root.sublayerTransform = perspective
            let axisY: CGFloat = (t.direction == .fromTop || t.direction == .fromBottom) ? 0 : 1
            let axisX: CGFloat = 1 - axisY
            let sign: CGFloat = (t.direction == .fromRight || t.direction == .fromBottom) ? 1 : -1
            let base = CATransform3DMakeScale(s, s, 1)
            if t.kind == .flip {
                let half = duration / 2
                old.add(anim("transform", NSValue(caTransform3D: base), NSValue(caTransform3D: CATransform3DRotate(base, sign * .pi / 2, axisX, axisY, 0)), d: half), forKey: "t")
                incoming.add(anim("transform", NSValue(caTransform3D: CATransform3DRotate(base, -sign * .pi / 2, axisX, axisY, 0)), NSValue(caTransform3D: base), delay: half, d: half), forKey: "t")
            } else {
                let depth = (axisY == 1 ? w : h) * s / 2
                func cube(_ angle: CGFloat) -> CATransform3D {
                    var m = CATransform3DMakeTranslation(0, 0, -depth)
                    m = CATransform3DRotate(m, angle, axisX, axisY, 0)
                    m = CATransform3DTranslate(m, 0, 0, depth)
                    return CATransform3DConcat(base, m)
                }
                old.add(anim("transform", NSValue(caTransform3D: cube(0)), NSValue(caTransform3D: cube(-sign * .pi / 2))), forKey: "t")
                incoming.add(anim("transform", NSValue(caTransform3D: cube(sign * .pi / 2)), NSValue(caTransform3D: cube(0))), forKey: "t")
            }
        case .circle:
            let m = CAShapeLayer()
            m.frame = CGRect(x: 0, y: 0, width: w, height: h)
            let r = hypot(w, h) / 2
            let small = CGPath(ellipseIn: CGRect(x: w / 2 - 1, y: h / 2 - 1, width: 2, height: 2), transform: nil)
            let large = CGPath(ellipseIn: CGRect(x: w / 2 - r, y: h / 2 - r, width: r * 2, height: r * 2), transform: nil)
            m.path = large
            incoming.mask = m
            m.add(anim("path", small, large), forKey: "t")
        case .blinds:
            let m = CALayer()
            m.frame = CGRect(x: 0, y: 0, width: w, height: h)
            let count = 8
            let stripe = h / CGFloat(count)
            for i in 0..<count {
                let s = CALayer()
                s.backgroundColor = NSColor.black.cgColor
                s.anchorPoint = CGPoint(x: 0.5, y: 0)
                s.frame = CGRect(x: 0, y: CGFloat(i) * stripe, width: w, height: stripe + 0.5)
                s.add(anim("bounds", NSValue(rect: CGRect(x: 0, y: 0, width: w, height: 0)), NSValue(rect: CGRect(x: 0, y: 0, width: w, height: stripe + 0.5))), forKey: "t")
                m.addSublayer(s)
            }
            incoming.mask = m
        case .morph:
            morphTransition(from: oldSlide, oldLayers: oldLayers, to: slide, newLayers: layers, old: old, incoming: incoming, duration: duration)
        }

        content = incoming
        elementLayers = layers
        self.plan = plan
        slideIndex = index
        nextStep = 0
        stepEndsAt = CACurrentMediaTime() + duration
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.03) { [weak self] in
            guard let self else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            old.removeFromSuperlayer()
            incoming.removeAllAnimations()
            incoming.mask = nil
            incoming.opacity = 1
            incoming.transform = CATransform3DMakeScale(self.fitScale, self.fitScale, 1)
            incoming.position = CGPoint(x: self.bounds.midX, y: self.bounds.midY)
            self.root.sublayerTransform = CATransform3DIdentity
            for layer in layers.values where layer.animation(forKey: "morph") != nil { layer.removeAnimation(forKey: "morph") }
            CATransaction.commit()
            self.startAutoplayMedia()
            self.runStep()
            completion?()
            self.onIdle?()
        }
    }

    /// Random squares revealing the incoming slide.
    private func dissolveMask(duration: Double) -> CALayer {
        let m = CALayer()
        let w = slideSize.width, h = slideSize.height
        m.frame = CGRect(x: 0, y: 0, width: w, height: h)
        let columns = 24, rows = Int((Double(columns) * Double(h / w)).rounded(.up))
        let cw = w / CGFloat(columns), ch = h / CGFloat(rows)
        let now = CACurrentMediaTime()
        for r in 0..<rows {
            for c in 0..<columns {
                let cell = CALayer()
                cell.backgroundColor = NSColor.black.cgColor
                cell.frame = CGRect(x: CGFloat(c) * cw, y: CGFloat(r) * ch, width: cw + 0.5, height: ch + 0.5)
                let a = CABasicAnimation(keyPath: "opacity")
                a.fromValue = 0
                a.toValue = 1
                a.duration = 0.05
                a.beginTime = now + Double.random(in: 0...(duration * 0.9))
                a.fillMode = .backwards
                cell.add(a, forKey: "d")
                m.addSublayer(cell)
            }
        }
        return m
    }

    /// Smoothly moves matching objects (same id or same name) between slides.
    private func morphTransition(from oldSlide: Slide, oldLayers: [UUID: CALayer], to newSlide: Slide, newLayers: [UUID: CALayer],
                                 old: CALayer, incoming: CALayer, duration: Double) {
        let now = CACurrentMediaTime()
        func anim(_ key: String, _ from: Any?, _ to: Any?) -> CABasicAnimation {
            let a = CABasicAnimation(keyPath: key)
            a.fromValue = from
            a.toValue = to
            a.duration = duration
            a.beginTime = now
            a.fillMode = .both
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            return a
        }
        // Background crossfades; matched objects move; others fade.
        if let background = incoming.sublayers?.first {
            background.add(anim("opacity", 0, 1), forKey: "morph")
        }
        old.add(anim("opacity", 1, 0), forKey: "morph")
        for e in newSlide.elements {
            guard let layer = newLayers[e.id] else { continue }
            let match = oldSlide.elements.first { $0.id == e.id } ?? oldSlide.elements.first { $0.name == e.name && $0.kindName == e.kindName && !e.name.isEmpty }
            guard let previous = match else {
                layer.add(anim("opacity", 0, layer.opacity), forKey: "morph")
                continue
            }
            let fromPosition = CGPoint(x: previous.frame.midX, y: previous.frame.midY)
            let sx = previous.frame.width / max(e.frame.width, 1), sy = previous.frame.height / max(e.frame.height, 1)
            let fromTransform = CATransform3DScale(CATransform3DMakeRotation(CGFloat(previous.rotation * .pi / 180), 0, 0, 1), sx, sy, 1)
            let group = CAAnimationGroup()
            let move = anim("position", NSValue(point: fromPosition), NSValue(point: layer.position))
            let transform = anim("transform", NSValue(caTransform3D: fromTransform), NSValue(caTransform3D: layer.transform))
            move.beginTime = 0; transform.beginTime = 0
            group.animations = [move, transform]
            group.duration = duration
            group.beginTime = now
            group.fillMode = .both
            layer.add(group, forKey: "morph")
            // Crossfade from the old look.
            if let oldLayer = oldLayers[previous.id] ?? old.sublayers?.first(where: { $0.name == previous.id.uuidString }), let contents = oldLayer.contents {
                let ghost = CALayer()
                ghost.contents = contents
                ghost.bounds = layer.bounds
                ghost.anchorPoint = layer.anchorPoint
                ghost.position = layer.position
                ghost.contentsGravity = .resize
                ghost.opacity = 0
                incoming.addSublayer(ghost)
                let g = CAAnimationGroup()
                let gm = anim("position", NSValue(point: fromPosition), NSValue(point: layer.position))
                let gt = anim("transform", NSValue(caTransform3D: fromTransform), NSValue(caTransform3D: layer.transform))
                let gf = anim("opacity", 1, 0)
                gm.beginTime = 0; gt.beginTime = 0; gf.beginTime = 0
                g.animations = [gm, gt, gf]
                g.duration = duration
                g.beginTime = now
                g.fillMode = .both
                ghost.add(g, forKey: "morph")
                DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) { ghost.removeFromSuperlayer() }
                layer.add(anim("opacity", 0, 1), forKey: "morph-fade")
            }
        }
    }

    /// The fully composed current state as an image (presenter view).
    func snapshot() -> CGImage? {
        SlideRenderer.cgImage(presentation.slides[slideIndex], number: slideIndex + 1, presentation: presentation, pixelWidth: 960)
    }
}
