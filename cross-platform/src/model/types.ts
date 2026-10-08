/**
 * The presentation model, shaped exactly like the JSON the Mac app writes
 * (Swift's synthesized Codable): enums with associated values are objects
 * keyed by the case name (`{ "solid": { "_0": … } }`), rectangles are
 * `[[x, y], [width, height]]`, and optional values are left out when unset.
 * Keeping that shape in memory means `.wslides` files round-trip untouched.
 */

export type UUID = string;
export type Point = [number, number];
export type Size = [number, number];
export type Frame = [Point, Size];

export interface RGB { r: number; g: number; b: number; a: number }

export type ThemeSlot =
  | "dark1" | "light1" | "dark2" | "light2"
  | "accent1" | "accent2" | "accent3" | "accent4" | "accent5" | "accent6"
  | "hyperlink" | "followedHyperlink";

export type PaintColor =
  | { rgb: { _0: RGB } }
  | { theme: { _0: ThemeSlot; shade: number; alpha: number } };

export interface ThemeColors {
  dark1: RGB; light1: RGB; dark2: RGB; light2: RGB;
  accent1: RGB; accent2: RGB; accent3: RGB; accent4: RGB; accent5: RGB; accent6: RGB;
  hyperlink: RGB; followedHyperlink: RGB;
}

// MARK: Fills and lines

export interface GradientStop { color: PaintColor; position: number }
export interface GradientFill { kind: "linear" | "radial"; stops: GradientStop[]; angle: number }
export interface ImageFill { mediaID: string; mode: "stretch" | "tile" | "fit"; transparency: number }
export type PatternKind = "horizontal" | "vertical" | "diagonalUp" | "diagonalDown" | "grid" | "dots" | "checker";
export interface PatternFill { kind: PatternKind; foreground: PaintColor; background: PaintColor }

export type Fill =
  | { none: Record<string, never> }
  | { solid: { _0: PaintColor } }
  | { gradient: { _0: GradientFill } }
  | { image: { _0: ImageFill } }
  | { pattern: { _0: PatternFill } };

export type DashStyle = "solid" | "roundDot" | "squareDot" | "dash" | "dashDot" | "longDash" | "longDashDot";
export type ArrowHead = "none" | "triangle" | "open" | "stealth" | "diamond" | "oval";

export interface LineStyle {
  color?: PaintColor;
  width: number;
  dash: DashStyle;
  head: ArrowHead;
  tail: ArrowHead;
  roundCaps: boolean;
}

export interface ShadowEffect { color: RGB; opacity: number; blur: number; distance: number; angle: number }
export interface GlowEffect { color: PaintColor; radius: number }
export interface ReflectionEffect { opacity: number; size: number; distance: number }
export interface Effects { shadow?: ShadowEffect; glow?: GlowEffect; reflection?: ReflectionEffect; softEdges: number }

export interface ImageAdjustments { brightness: number; contrast: number; saturation: number; transparency: number; sepia: boolean }
export interface CropInsets { left: number; top: number; right: number; bottom: number }

// MARK: Text

export type FontRole = "heading" | "body";
export type TextAlignment = "left" | "center" | "right" | "justify";
export type NumberingScheme = "arabicPeriod" | "arabicParen" | "romanUpper" | "romanLower" | "alphaUpper" | "alphaLower";
export type VerticalAnchor = "top" | "middle" | "bottom";
export type AutoFit = "none" | "shrink" | "resizeShape";
export type TextDirection = "horizontal" | "rotated90" | "rotated270";

export interface RunStyle {
  fontFamily?: string;
  size?: number;
  bold?: boolean;
  italic?: boolean;
  underline: boolean;
  strikethrough: boolean;
  color?: PaintColor;
  highlight?: RGB;
  /** 1 = superscript, -1 = subscript. */
  baseline: number;
  link?: string;
  allCaps: boolean;
  smallCaps: boolean;
  characterSpacing: number;
  outlineColor?: PaintColor;
  outlineWidth: number;
  shadow: boolean;
}

export interface TextRun { text: string; style: RunStyle }

export type Bullet =
  | { none: Record<string, never> }
  | { symbol: { _0: string } }
  | { numbered: { _0: NumberingScheme; start: number } };

export interface ParagraphStyle {
  alignment: TextAlignment;
  level: number;
  bullet: Bullet;
  lineSpacing: number;
  spaceBefore: number;
  spaceAfter: number;
  bulletColor?: PaintColor;
}

export interface Paragraph { runs: TextRun[]; style: ParagraphStyle }
export interface EdgeInsets { top: number; left: number; bottom: number; right: number }

export interface TextBody {
  paragraphs: Paragraph[];
  anchor: VerticalAnchor;
  autofit: AutoFit;
  wrap: boolean;
  columns: number;
  direction: TextDirection;
  insets: EdgeInsets;
  defaultSize: number;
  defaultColor: PaintColor;
  fontRole: FontRole;
  prompt?: string;
}

// MARK: Elements

export type ShapeKind =
  | "rect" | "roundRect" | "snip1Rect" | "snip2SameRect" | "round2SameRect"
  | "ellipse" | "triangle" | "rtTriangle" | "parallelogram" | "trapezoid" | "diamond" | "pentagon" | "hexagon" | "octagon" | "decagon"
  | "pie" | "chord" | "teardrop" | "frame" | "donut" | "can" | "cube" | "heart" | "lightningBolt" | "sun" | "moon" | "cloud" | "smileyFace" | "plaque" | "noSmoking"
  | "rightArrow" | "leftArrow" | "upArrow" | "downArrow" | "leftRightArrow" | "upDownArrow" | "chevron" | "homePlate" | "notchedRightArrow" | "quadArrow"
  | "mathPlus" | "mathMinus" | "mathMultiply" | "mathDivide" | "mathEqual" | "mathNotEqual"
  | "flowChartProcess" | "flowChartAlternateProcess" | "flowChartDecision" | "flowChartInputOutput" | "flowChartPredefinedProcess"
  | "flowChartDocument" | "flowChartTerminator" | "flowChartPreparation" | "flowChartManualInput" | "flowChartConnector" | "flowChartDelay"
  | "star4" | "star5" | "star6" | "star8" | "star12" | "star24" | "irregularSeal1"
  | "wedgeRectCallout" | "wedgeRoundRectCallout" | "wedgeEllipseCallout" | "cloudCallout";

export type ConnectorKind = "straight" | "elbow" | "curved";
export type PlaceholderRole = "title" | "centeredTitle" | "subtitle" | "body" | "picture" | "date" | "footer" | "slideNumber";

export type ElementAction =
  | { url: { _0: string } }
  | { slide: { _0: UUID } }
  | { nextSlide: Record<string, never> }
  | { previousSlide: Record<string, never> }
  | { firstSlide: Record<string, never> }
  | { lastSlide: Record<string, never> }
  | { endShow: Record<string, never> };

export interface ShapeContent {
  kind: ShapeKind;
  fill: Fill;
  line: LineStyle;
  effects: Effects;
  text: TextBody;
  adjustments: number[];
}

export interface ImageContent {
  mediaID: string;
  crop: CropInsets;
  line: LineStyle;
  effects: Effects;
  adjustments: ImageAdjustments;
  maskShape?: ShapeKind;
}

export interface LineContent {
  kind: ConnectorKind;
  line: LineStyle;
  effects: Effects;
  startElement?: UUID;
  endElement?: UUID;
}

export interface TableCell { text: TextBody; fill?: Fill; rowSpan: number; columnSpan: number; isMerged: boolean }

export interface TableStyleOptions {
  headerRow: boolean;
  totalRow: boolean;
  bandedRows: boolean;
  firstColumn: boolean;
  lastColumn: boolean;
  bandedColumns: boolean;
  color: PaintColor;
  /** 0 = medium, 1 = light, 2 = dark. */
  intensity: number;
  borderColor?: PaintColor;
  borderWidth: number;
}

export interface TableContent { rows: TableCell[][]; columnWidths: number[]; rowHeights: number[]; style: TableStyleOptions }

export type ChartKind = "column" | "stackedColumn" | "bar" | "stackedBar" | "line" | "lineMarkers" | "area" | "pie" | "doughnut" | "scatter";
export type LegendPosition = "none" | "bottom" | "right" | "top" | "left";
export interface ChartSeries { name: string; values: number[]; color?: PaintColor }

export interface ChartContent {
  kind: ChartKind;
  title?: string;
  categories: string[];
  series: ChartSeries[];
  legend: LegendPosition;
  showDataLabels: boolean;
  showGridlines: boolean;
  fontSize: number;
  textColor: PaintColor;
  background: Fill;
}

export interface IconContent { symbol: string; color: PaintColor }

export interface MediaContent {
  kind: "video" | "audio";
  mediaID: string;
  posterID?: string;
  autoplay: boolean;
  loop: boolean;
  volume: number;
  hideWhenNotPlaying: boolean;
}

export interface GroupContent { children: SlideElement[] }

export type ElementContent =
  | { shape: { _0: ShapeContent } }
  | { image: { _0: ImageContent } }
  | { line: { _0: LineContent } }
  | { table: { _0: TableContent } }
  | { chart: { _0: ChartContent } }
  | { icon: { _0: IconContent } }
  | { media: { _0: MediaContent } }
  | { group: { _0: GroupContent } };

export interface SlideElement {
  id: UUID;
  name: string;
  frame: Frame;
  rotation: number;
  flipH: boolean;
  flipV: boolean;
  locked: boolean;
  hidden: boolean;
  lockAspectRatio: boolean;
  placeholder?: PlaceholderRole;
  action?: ElementAction;
  altText: string;
  content: ElementContent;
}

// MARK: Motion

export type TransitionKind =
  | "none" | "morph" | "fade" | "fadeThroughBlack" | "push" | "wipe" | "split" | "reveal" | "cover" | "uncover"
  | "zoom" | "flip" | "cube" | "circle" | "dissolve" | "blinds";
export type MotionDirection = "fromRight" | "fromLeft" | "fromTop" | "fromBottom";

export interface Transition {
  kind: TransitionKind;
  direction: MotionDirection;
  duration: number;
  advanceOnClick: boolean;
  advanceAfter?: number;
}

export type AnimationEffect =
  | "appear" | "fadeIn" | "flyIn" | "floatIn" | "wipeIn" | "splitIn" | "zoomIn" | "growTurnIn" | "swivelIn" | "bounceIn" | "spinIn"
  | "pulse" | "spin" | "growShrink" | "teeter" | "transparency" | "colorPulse" | "wave"
  | "disappear" | "fadeOut" | "flyOut" | "floatOut" | "wipeOut" | "splitOut" | "zoomOut" | "shrinkTurnOut" | "swivelOut" | "bounceOut"
  | "pathLine" | "pathArc" | "pathCircle" | "pathZigzag";
export type AnimationTrigger = "onClick" | "withPrevious" | "afterPrevious";

export interface SlideAnimation {
  id: UUID;
  elementID: UUID;
  effect: AnimationEffect;
  trigger: AnimationTrigger;
  duration: number;
  delay: number;
  direction: MotionDirection;
  repeatCount: number;
  amount: number;
}

// MARK: Slides and presentation

export type LayoutKind =
  | "title" | "titleContent" | "sectionHeader" | "twoContent" | "comparison" | "titleOnly" | "blank"
  | "contentCaption" | "pictureCaption" | "quote" | "bigNumber";

export interface SlideComment {
  id: UUID;
  author: string;
  date: string;
  text: string;
  resolved: boolean;
  replies: SlideComment[];
  position: Point;
}

export interface Slide {
  id: UUID;
  layout: LayoutKind;
  elements: SlideElement[];
  background?: Fill;
  notes: string;
  transition: Transition;
  animations: SlideAnimation[];
  hidden: boolean;
  comments: SlideComment[];
  hideBackgroundGraphics: boolean;
}

export interface SlideSection { id: UUID; name: string; firstSlideID: UUID }

export interface HeaderFooter {
  showDate: boolean;
  fixedDate?: string;
  showSlideNumber: boolean;
  showFooter: boolean;
  footerText: string;
  hideOnTitleSlide: boolean;
}

export interface SlideShowSettings {
  loopUntilEscape: boolean;
  showWithoutAnimation: boolean;
  useTimings: boolean;
  usePresenterView: boolean;
  penColor: RGB;
  laserColor: RGB;
}

export interface PresentationTheme {
  id: string;
  name: string;
  colors: ThemeColors;
  headingFont: string;
  bodyFont: string;
  background: Fill;
  decorations: SlideElement[];
  titleDecorations: SlideElement[];
  titleBackground?: Fill;
  titleColor: PaintColor;
  titleSize: number;
  titleBold: boolean;
  titleCaps: boolean;
  bodySize: number;
  bulletSymbol: string;
  bulletColor?: PaintColor;
  variants: ThemeColors[];
}

/** Media bytes live beside the JSON in the file; in memory they are kept here by id. */
export interface MediaItem { filename: string; data: Uint8Array }

export interface Presentation {
  slides: Slide[];
  theme: PresentationTheme;
  slideSize: Size;
  sections: SlideSection[];
  headerFooter: HeaderFooter;
  showSettings: SlideShowSettings;
  title: string;
  author: string;
  created: string;
  media: Record<string, MediaItem>;
}
