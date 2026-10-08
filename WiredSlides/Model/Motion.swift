import Foundation

enum TransitionKind: String, Codable, CaseIterable, Identifiable {
    case none, morph, fade, fadeThroughBlack, push, wipe, split, reveal, cover, uncover, zoom, flip, cube, circle, dissolve, blinds

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "None"
        case .morph: "Morph"
        case .fade: "Fade"
        case .fadeThroughBlack: "Fade Through Black"
        case .push: "Push"
        case .wipe: "Wipe"
        case .split: "Split"
        case .reveal: "Reveal"
        case .cover: "Cover"
        case .uncover: "Uncover"
        case .zoom: "Zoom"
        case .flip: "Flip"
        case .cube: "Cube"
        case .circle: "Shape"
        case .dissolve: "Dissolve"
        case .blinds: "Blinds"
        }
    }

    var symbol: String {
        switch self {
        case .none: "nosign"
        case .morph: "wand.and.stars"
        case .fade: "circle.lefthalf.filled"
        case .fadeThroughBlack: "circle.fill"
        case .push: "arrow.left.to.line"
        case .wipe: "rectangle.righthalf.inset.filled"
        case .split: "rectangle.split.2x1"
        case .reveal: "rectangle.portrait.and.arrow.right"
        case .cover: "rectangle.stack"
        case .uncover: "rectangle.on.rectangle.angled"
        case .zoom: "plus.magnifyingglass"
        case .flip: "arrow.left.and.right.righttriangle.left.righttriangle.right"
        case .cube: "cube"
        case .circle: "circle.dashed"
        case .dissolve: "aqi.medium"
        case .blinds: "line.3.horizontal"
        }
    }

    var hasDirection: Bool {
        switch self {
        case .push, .wipe, .reveal, .cover, .uncover, .flip, .cube, .split: true
        default: false
        }
    }

    var ooxml: String? {
        switch self {
        case .none, .morph: nil
        case .fade: "fade"
        case .fadeThroughBlack: "fade"
        case .push: "push"
        case .wipe: "wipe"
        case .split: "split"
        case .reveal: "cover"
        case .cover: "cover"
        case .uncover: "pull"
        case .zoom: "zoom"
        case .flip: "push"
        case .cube: "push"
        case .circle: "circle"
        case .dissolve: "dissolve"
        case .blinds: "blinds"
        }
    }
}

enum MotionDirection: String, Codable, CaseIterable, Identifiable {
    case fromRight, fromLeft, fromTop, fromBottom
    var id: String { rawValue }

    var title: String {
        switch self {
        case .fromRight: "From Right"
        case .fromLeft: "From Left"
        case .fromTop: "From Top"
        case .fromBottom: "From Bottom"
        }
    }

    var symbol: String {
        switch self {
        case .fromRight: "arrow.left"
        case .fromLeft: "arrow.right"
        case .fromTop: "arrow.down"
        case .fromBottom: "arrow.up"
        }
    }

    var ooxml: String {
        switch self {
        case .fromRight: "l"
        case .fromLeft: "r"
        case .fromTop: "d"
        case .fromBottom: "u"
        }
    }
}

struct Transition: Codable, Hashable {
    var kind: TransitionKind = .none
    var direction: MotionDirection = .fromRight
    var duration: Double = 0.7
    var advanceOnClick = true
    /// Advance automatically after this many seconds.
    var advanceAfter: Double?
}

enum AnimationCategory: String, Codable, CaseIterable, Identifiable {
    case entrance, emphasis, exit, motionPath
    var id: String { rawValue }

    var title: String {
        switch self {
        case .entrance: "Entrance"
        case .emphasis: "Emphasis"
        case .exit: "Exit"
        case .motionPath: "Motion Paths"
        }
    }
}

enum AnimationEffect: String, Codable, CaseIterable, Identifiable {
    // Entrance
    case appear, fadeIn, flyIn, floatIn, wipeIn, splitIn, zoomIn, growTurnIn, swivelIn, bounceIn, spinIn
    // Emphasis
    case pulse, spin, growShrink, teeter, transparency, colorPulse, wave
    // Exit
    case disappear, fadeOut, flyOut, floatOut, wipeOut, splitOut, zoomOut, shrinkTurnOut, swivelOut, bounceOut
    // Motion paths
    case pathLine, pathArc, pathCircle, pathZigzag

    var id: String { rawValue }

    var category: AnimationCategory {
        switch self {
        case .appear, .fadeIn, .flyIn, .floatIn, .wipeIn, .splitIn, .zoomIn, .growTurnIn, .swivelIn, .bounceIn, .spinIn: .entrance
        case .pulse, .spin, .growShrink, .teeter, .transparency, .colorPulse, .wave: .emphasis
        case .disappear, .fadeOut, .flyOut, .floatOut, .wipeOut, .splitOut, .zoomOut, .shrinkTurnOut, .swivelOut, .bounceOut: .exit
        case .pathLine, .pathArc, .pathCircle, .pathZigzag: .motionPath
        }
    }

    static func effects(in category: AnimationCategory) -> [AnimationEffect] { allCases.filter { $0.category == category } }

    var title: String {
        switch self {
        case .appear: "Appear"
        case .fadeIn: "Fade"
        case .flyIn: "Fly In"
        case .floatIn: "Float In"
        case .wipeIn: "Wipe"
        case .splitIn: "Split"
        case .zoomIn: "Zoom"
        case .growTurnIn: "Grow & Turn"
        case .swivelIn: "Swivel"
        case .bounceIn: "Bounce"
        case .spinIn: "Spinner"
        case .pulse: "Pulse"
        case .spin: "Spin"
        case .growShrink: "Grow/Shrink"
        case .teeter: "Teeter"
        case .transparency: "Transparency"
        case .colorPulse: "Color Pulse"
        case .wave: "Wave"
        case .disappear: "Disappear"
        case .fadeOut: "Fade"
        case .flyOut: "Fly Out"
        case .floatOut: "Float Out"
        case .wipeOut: "Wipe"
        case .splitOut: "Split"
        case .zoomOut: "Zoom"
        case .shrinkTurnOut: "Shrink & Turn"
        case .swivelOut: "Swivel"
        case .bounceOut: "Bounce"
        case .pathLine: "Lines"
        case .pathArc: "Arcs"
        case .pathCircle: "Shapes"
        case .pathZigzag: "Zigzag"
        }
    }

    var symbol: String {
        switch self {
        case .appear, .disappear: "star"
        case .fadeIn, .fadeOut: "circle.lefthalf.filled"
        case .flyIn, .flyOut: "paperplane"
        case .floatIn, .floatOut: "arrow.up.to.line"
        case .wipeIn, .wipeOut: "rectangle.righthalf.inset.filled"
        case .splitIn, .splitOut: "rectangle.split.2x1"
        case .zoomIn, .zoomOut: "plus.magnifyingglass"
        case .growTurnIn, .shrinkTurnOut: "arrow.up.left.and.arrow.down.right"
        case .swivelIn, .swivelOut: "arrow.triangle.2.circlepath"
        case .bounceIn, .bounceOut: "figure.jumprope"
        case .spinIn, .spin: "arrow.clockwise"
        case .pulse: "waveform.path.ecg"
        case .growShrink: "arrow.up.backward.and.arrow.down.forward"
        case .teeter: "metronome"
        case .transparency: "square.dashed"
        case .colorPulse: "paintpalette"
        case .wave: "water.waves"
        case .pathLine: "line.diagonal.arrow"
        case .pathArc: "point.topleft.down.to.point.bottomright.curvepath"
        case .pathCircle: "circle.dotted"
        case .pathZigzag: "bolt"
        }
    }

    var hasDirection: Bool {
        switch self {
        case .flyIn, .flyOut, .floatIn, .floatOut, .wipeIn, .wipeOut, .pathLine, .pathArc: true
        default: false
        }
    }

    var defaultDuration: Double {
        switch self {
        case .appear, .disappear: 0
        case .flyIn, .flyOut, .floatIn, .floatOut, .wipeIn, .wipeOut, .fadeIn, .fadeOut: 0.5
        case .spin, .pathLine, .pathArc, .pathCircle, .pathZigzag, .spinIn: 2
        default: 1
        }
    }

    /// Entrance effects start hidden; exit effects end hidden.
    var startsHidden: Bool { category == .entrance }
    var endsHidden: Bool { category == .exit }
}

enum AnimationTrigger: String, Codable, CaseIterable, Identifiable {
    case onClick, withPrevious, afterPrevious
    var id: String { rawValue }

    var title: String {
        switch self {
        case .onClick: "On Click"
        case .withPrevious: "With Previous"
        case .afterPrevious: "After Previous"
        }
    }

    var symbol: String {
        switch self {
        case .onClick: "cursorarrow.click"
        case .withPrevious: "equal.circle"
        case .afterPrevious: "clock"
        }
    }
}

struct SlideAnimation: Codable, Hashable, Identifiable {
    var id = UUID()
    var elementID: UUID
    var effect: AnimationEffect
    var trigger: AnimationTrigger = .onClick
    var duration: Double
    var delay: Double = 0
    var direction: MotionDirection = .fromBottom
    var repeatCount = 1
    /// Motion path distance / emphasis strength.
    var amount: Double = 1

    init(elementID: UUID, effect: AnimationEffect, trigger: AnimationTrigger = .onClick) {
        self.elementID = elementID
        self.effect = effect
        self.trigger = trigger
        duration = effect.defaultDuration
    }
}
