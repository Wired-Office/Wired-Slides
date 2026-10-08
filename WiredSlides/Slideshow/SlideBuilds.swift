import Foundation

/// A slide's animations split into click steps with start times.
struct SlideBuildPlan {
    struct Item {
        var animation: SlideAnimation
        var start: Double
        var end: Double { start + animation.duration * Double(max(animation.repeatCount, 1)) }
    }

    /// Step 0 runs automatically when the slide appears (it may be empty); later steps each need a click.
    var steps: [[Item]]

    init(_ slide: Slide, animated: Bool = true) {
        let animations = animated ? slide.validAnimations : []
        var steps: [[Item]] = [[]]
        var stepStart = true
        var lastStart = 0.0, lastEnd = 0.0
        for (i, a) in animations.enumerated() {
            if a.trigger == .onClick {
                steps.append([])
                lastStart = 0
                lastEnd = 0
                stepStart = true
            } else if i == 0 {
                stepStart = true
            }
            let start: Double
            switch a.trigger {
            case .onClick: start = a.delay
            case .withPrevious: start = (stepStart ? 0 : lastStart) + a.delay
            case .afterPrevious: start = lastEnd + a.delay
            }
            let item = Item(animation: a, start: start)
            steps[steps.count - 1].append(item)
            lastStart = start
            lastEnd = max(lastEnd, item.end)
            stepStart = false
        }
        self.steps = steps
    }

    var clickCount: Int { steps.count - 1 }

    /// Elements hidden before any animation runs.
    var initiallyHidden: Set<UUID> {
        var seen = Set<UUID>()
        var hidden = Set<UUID>()
        for item in steps.flatMap({ $0 }) {
            let id = item.animation.elementID
            if !seen.contains(id) {
                seen.insert(id)
                if item.animation.effect.startsHidden { hidden.insert(id) }
            }
        }
        return hidden
    }

    /// Elements that need their own layers.
    var animatedElements: Set<UUID> { Set(steps.flatMap { $0 }.map(\.animation.elementID)) }

    func duration(of step: Int) -> Double {
        steps.indices.contains(step) ? (steps[step].map(\.end).max() ?? 0) : 0
    }
}
