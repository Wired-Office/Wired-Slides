import Foundation

/// The preset geometries, named after their PowerPoint (DrawingML) equivalents.
enum ShapeKind: String, Codable, CaseIterable, Identifiable {
    // Rectangles
    case rect, roundRect, snip1Rect, snip2SameRect, round2SameRect
    // Basic shapes
    case ellipse, triangle, rtTriangle, parallelogram, trapezoid, diamond, pentagon, hexagon, octagon, decagon
    case pie, chord, teardrop, frame, donut, can, cube, heart, lightningBolt, sun, moon, cloud, smileyFace, plaque, noSmoking
    // Block arrows
    case rightArrow, leftArrow, upArrow, downArrow, leftRightArrow, upDownArrow, chevron, homePlate, notchedRightArrow, quadArrow
    // Equation shapes
    case mathPlus, mathMinus, mathMultiply, mathDivide, mathEqual, mathNotEqual
    // Flowchart
    case flowChartProcess, flowChartAlternateProcess, flowChartDecision, flowChartInputOutput, flowChartPredefinedProcess
    case flowChartDocument, flowChartTerminator, flowChartPreparation, flowChartManualInput, flowChartConnector, flowChartDelay
    // Stars and banners
    case star4, star5, star6, star8, star12, star24, irregularSeal1
    // Callouts
    case wedgeRectCallout, wedgeRoundRectCallout, wedgeEllipseCallout, cloudCallout

    var id: String { rawValue }

    enum Category: String, CaseIterable, Identifiable {
        case rectangles = "Rectangles", basic = "Basic Shapes", arrows = "Block Arrows", equation = "Equation Shapes"
        case flowchart = "Flowchart", stars = "Stars and Banners", callouts = "Callouts"
        var id: String { rawValue }
    }

    var category: Category {
        switch self {
        case .rect, .roundRect, .snip1Rect, .snip2SameRect, .round2SameRect: .rectangles
        case .rightArrow, .leftArrow, .upArrow, .downArrow, .leftRightArrow, .upDownArrow, .chevron, .homePlate, .notchedRightArrow, .quadArrow: .arrows
        case .mathPlus, .mathMinus, .mathMultiply, .mathDivide, .mathEqual, .mathNotEqual: .equation
        case .flowChartProcess, .flowChartAlternateProcess, .flowChartDecision, .flowChartInputOutput, .flowChartPredefinedProcess,
             .flowChartDocument, .flowChartTerminator, .flowChartPreparation, .flowChartManualInput, .flowChartConnector, .flowChartDelay: .flowchart
        case .star4, .star5, .star6, .star8, .star12, .star24, .irregularSeal1: .stars
        case .wedgeRectCallout, .wedgeRoundRectCallout, .wedgeEllipseCallout, .cloudCallout: .callouts
        default: .basic
        }
    }

    static func kinds(in category: Category) -> [ShapeKind] { allCases.filter { $0.category == category } }

    var title: String {
        switch self {
        case .rect: "Rectangle"
        case .roundRect: "Rounded Rectangle"
        case .snip1Rect: "Snip Single Corner"
        case .snip2SameRect: "Snip Same Side Corners"
        case .round2SameRect: "Round Same Side Corners"
        case .ellipse: "Oval"
        case .triangle: "Isosceles Triangle"
        case .rtTriangle: "Right Triangle"
        case .parallelogram: "Parallelogram"
        case .trapezoid: "Trapezoid"
        case .diamond: "Diamond"
        case .pentagon: "Pentagon"
        case .hexagon: "Hexagon"
        case .octagon: "Octagon"
        case .decagon: "Decagon"
        case .pie: "Pie"
        case .chord: "Chord"
        case .teardrop: "Teardrop"
        case .frame: "Frame"
        case .donut: "Donut"
        case .can: "Cylinder"
        case .cube: "Cube"
        case .heart: "Heart"
        case .lightningBolt: "Lightning Bolt"
        case .sun: "Sun"
        case .moon: "Moon"
        case .cloud: "Cloud"
        case .smileyFace: "Smiley Face"
        case .plaque: "Plaque"
        case .noSmoking: "\"Not Allowed\" Symbol"
        case .rightArrow: "Right Arrow"
        case .leftArrow: "Left Arrow"
        case .upArrow: "Up Arrow"
        case .downArrow: "Down Arrow"
        case .leftRightArrow: "Left-Right Arrow"
        case .upDownArrow: "Up-Down Arrow"
        case .chevron: "Chevron"
        case .homePlate: "Pentagon Arrow"
        case .notchedRightArrow: "Notched Right Arrow"
        case .quadArrow: "Quad Arrow"
        case .mathPlus: "Plus"
        case .mathMinus: "Minus"
        case .mathMultiply: "Multiply"
        case .mathDivide: "Division"
        case .mathEqual: "Equal"
        case .mathNotEqual: "Not Equal"
        case .flowChartProcess: "Process"
        case .flowChartAlternateProcess: "Alternate Process"
        case .flowChartDecision: "Decision"
        case .flowChartInputOutput: "Data"
        case .flowChartPredefinedProcess: "Predefined Process"
        case .flowChartDocument: "Document"
        case .flowChartTerminator: "Terminator"
        case .flowChartPreparation: "Preparation"
        case .flowChartManualInput: "Manual Input"
        case .flowChartConnector: "Connector"
        case .flowChartDelay: "Delay"
        case .star4: "Star: 4 Points"
        case .star5: "Star: 5 Points"
        case .star6: "Star: 6 Points"
        case .star8: "Star: 8 Points"
        case .star12: "Star: 12 Points"
        case .star24: "Star: 24 Points"
        case .irregularSeal1: "Explosion"
        case .wedgeRectCallout: "Speech Bubble: Rectangle"
        case .wedgeRoundRectCallout: "Speech Bubble: Rounded Rectangle"
        case .wedgeEllipseCallout: "Speech Bubble: Oval"
        case .cloudCallout: "Thought Bubble: Cloud"
        }
    }

    /// The DrawingML preset name.
    var ooxml: String { rawValue }

    static func fromOOXML(_ name: String) -> ShapeKind? {
        if let kind = ShapeKind(rawValue: name) { return kind }
        switch name {
        case "flowChartOnlineStorage", "flowChartMagneticDisk": return .can
        case "star7", "star10", "star16", "star32": return .star8
        case "irregularSeal2": return .irregularSeal1
        case "plus": return .mathPlus
        case "round1Rect", "round2DiagRect": return .roundRect
        case "snip2DiagRect", "snipRoundRect": return .snip2SameRect
        case "ribbon", "ribbon2", "wave", "doubleWave": return .rect
        case "flowChartMerge", "flowChartExtract": return .triangle
        default: return nil
        }
    }

    /// Default adjustment values (fractions of the shape's smaller side, unless noted).
    var defaultAdjustments: [Double] {
        switch self {
        case .roundRect, .round2SameRect, .wedgeRoundRectCallout, .flowChartAlternateProcess: [0.1667]
        case .snip1Rect, .snip2SameRect: [0.1667]
        case .plaque: [0.1667]
        case .parallelogram, .trapezoid, .flowChartInputOutput: [0.25]
        case .hexagon: [0.25]
        case .octagon: [0.2929]
        case .rightArrow, .leftArrow, .upArrow, .downArrow, .leftRightArrow, .upDownArrow, .notchedRightArrow: [0.5, 0.5]
        case .quadArrow: [0.22]
        case .chevron, .homePlate: [0.5]
        case .frame: [0.125]
        case .donut, .noSmoking: [0.25]
        case .can: [0.25]
        case .cube: [0.25]
        case .moon: [0.5]
        case .pie: [0, 270]
        case .chord: [45, 270]
        case .star4: [0.25]
        case .star5: [0.38]
        case .star6: [0.5]
        case .star8: [0.62]
        case .star12, .star24: [0.75]
        case .mathPlus, .mathMinus, .mathMultiply, .mathDivide, .mathEqual, .mathNotEqual: [0.235]
        // Callout tail tip as fractions of the frame, relative to the top-left.
        case .wedgeRectCallout, .wedgeEllipseCallout, .cloudCallout: [0.2, 1.4]
        default: []
        }
    }

    /// Whether the shape shows the yellow adjustment handle.
    var hasAdjustHandle: Bool {
        switch self {
        case .roundRect, .round2SameRect, .snip1Rect, .snip2SameRect, .plaque, .parallelogram, .trapezoid, .hexagon, .octagon,
             .chevron, .homePlate, .frame, .donut, .noSmoking, .can, .cube, .moon,
             .star4, .star5, .star6, .star8, .star12, .star24,
             .rightArrow, .leftArrow, .upArrow, .downArrow, .leftRightArrow, .upDownArrow, .notchedRightArrow,
             .wedgeRectCallout, .wedgeRoundRectCallout, .wedgeEllipseCallout, .cloudCallout, .flowChartInputOutput:
            true
        default:
            false
        }
    }

    var isCallout: Bool {
        switch self {
        case .wedgeRectCallout, .wedgeRoundRectCallout, .wedgeEllipseCallout, .cloudCallout: true
        default: false
        }
    }
}

/// Kinds of lines and connectors.
enum ConnectorKind: String, Codable, CaseIterable, Identifiable {
    case straight, elbow, curved
    var id: String { rawValue }

    var title: String {
        switch self {
        case .straight: "Straight"
        case .elbow: "Elbow"
        case .curved: "Curved"
        }
    }

    var ooxml: String {
        switch self {
        case .straight: "line"
        case .elbow: "bentConnector3"
        case .curved: "curvedConnector3"
        }
    }
}
