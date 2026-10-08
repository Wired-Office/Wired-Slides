/**
 * Line icons drawn on a 24×24 grid, standing in for the SF Symbols the Mac
 * app uses (icons keep their SF Symbol names in files). Each is an SVG path
 * that is stroked; names ending in ".fill" (and a few others) are filled.
 */

const c = (x: number, y: number, r: number) => `M${x - r} ${y}a${r} ${r} 0 1 0 ${r * 2} 0a${r} ${r} 0 1 0 ${-r * 2} 0`;
const rr = (x: number, y: number, w: number, h: number, r: number) =>
  `M${x + r} ${y}h${w - 2 * r}a${r} ${r} 0 0 1 ${r} ${r}v${h - 2 * r}a${r} ${r} 0 0 1 ${-r} ${r}h${-(w - 2 * r)}a${r} ${r} 0 0 1 ${-r} ${-r}v${-(h - 2 * r)}a${r} ${r} 0 0 1 ${r} ${-r}z`;
const circled = (inner: string) => c(12, 12, 9.5) + inner;

const HEART = "M12 20.5S3.5 15.3 3.5 9.2A4.6 4.6 0 0 1 12 6.6a4.6 4.6 0 0 1 8.5 2.6c0 6.1-8.5 11.3-8.5 11.3z";
const STAR = "M12 2.8l2.8 5.8 6.3.9-4.6 4.4 1.1 6.3L12 17.2l-5.6 3 1.1-6.3-4.6-4.4 6.3-.9z";
const CLOUD = "M7 18.5h10.5a4 4 0 0 0 .6-8 5.8 5.8 0 0 0-11.2-1A4.5 4.5 0 0 0 7 18.5z";
const PERSON = c(12, 7.5, 3.8) + "M4.5 20.5c.6-4 3.6-6.5 7.5-6.5s6.9 2.5 7.5 6.5";
const ARROW_R = "M4 12h16M14 6l6 6-6 6";

export const SYMBOLS: Record<string, string> = {
  // Business
  briefcase: rr(3, 7, 18, 13, 2) + "M9 7V5.2C9 4.5 9.5 4 10.2 4h3.6c.7 0 1.2.5 1.2 1.2V7M3 12.5h18",
  "chart.bar": "M4 20h16M6.5 20v-6M11 20V8M15.5 20v-9M20 20V5",
  "chart.pie": "M12 3.5a8.5 8.5 0 1 0 8.5 8.5H12z" + "M14.5 2.5a7.5 7.5 0 0 1 7 7h-7z",
  "chart.line.uptrend.xyaxis": "M3.5 3.5v17h17M6.5 16l4-5 3.5 3 5.5-7M15.5 7h4v4",
  "dollarsign.circle": circled("M15 8.8c-.5-1-1.6-1.6-3-1.6-1.8 0-3 .9-3 2.2 0 3 6.2 1.6 6.2 4.8 0 1.4-1.3 2.4-3.2 2.4-1.5 0-2.7-.7-3.1-1.8M12 5.5v13"),
  creditcard: rr(2.5, 5, 19, 14, 2) + "M2.5 9.5h19M6 15h4",
  "building.2": "M3.5 21V6.5l7-3V21M10.5 9h10v12M3 21h18M6.5 9v.01M6.5 12.5v.01M6.5 16v.01M14 12.5h3M14 16h3",
  cart: "M2.5 3.5h2.8l2.4 11.2h10.8l2-8H6.3" + c(9, 19, 1.5) + c(17, 19, 1.5),
  bag: "M5 8h14l-1 12.5H6zM9 8V6.5a3 3 0 0 1 6 0V8",
  banknote: rr(2.5, 6, 19, 12, 1.5) + c(12, 12, 2.8) + "M5.5 9v6M18.5 9v6",
  target: c(12, 12, 9) + c(12, 12, 5.5) + c(12, 12, 2),
  flag: "M5 21V3.5M5 4h11.5l-2.5 4.5 2.5 4.5H5",
  trophy: "M7.5 4h9v5a4.5 4.5 0 0 1-9 0zM7.5 6H4.5a3 3 0 0 0 3 4M16.5 6h3a3 3 0 0 1-3 4M12 13.5v3.5M8.5 20.5h7M9.5 20.5l.5-3.5h4l.5 3.5",
  rosette: c(12, 9, 6) + c(12, 9, 2.5) + "M8.5 13.8 7 21l5-2.5 5 2.5-1.5-7.2",
  signature: "M3 17c2-4 4-9 5.5-9S7 15 9.5 15 13 10 14 10s.5 4 2 4 2.5-2 4-2M3 20.5h18",
  "doc.text": "M6 2.5h8l4.5 4.5v14.5H6zM14 2.5V7h4.5M9 11.5h6M9 14.5h6M9 17.5h4",
  folder: "M2.5 6.5c0-1 .8-1.8 1.8-1.8h4.4l2 2.3h9c1 0 1.8.8 1.8 1.8v9.4c0 1-.8 1.8-1.8 1.8H4.3c-1 0-1.8-.8-1.8-1.8z",
  "tray.full": "M3 13.5 5.5 4.5h13l2.5 9v6H3zM3 13.5h5l1 2.5h6l1-2.5h5M8 7.5h8M7.5 10.5h9",
  calendar: rr(3, 4.5, 18, 16, 2) + "M3 9h18M8 2.5v4M16 2.5v4M7 12.5h2M11 12.5h2M15 12.5h2M7 16h2M11 16h2",
  clock: circled("M12 6.5V12l3.5 2.5"),
  // People
  person: PERSON,
  "person.2": c(9, 7.5, 3.3) + "M2.5 19.5c.5-3.6 3.1-5.8 6.5-5.8s6 2.2 6.5 5.8" + c(16.5, 8, 2.8) + "M16.5 13.5c2.6.2 4.6 2.2 5 5",
  "person.3": c(12, 7, 2.8) + "M7 18.5c.4-3 2.4-4.8 5-4.8s4.6 1.8 5 4.8" + c(5.5, 9, 2.2) + c(18.5, 9, 2.2) + "M1.5 18c.3-2.3 1.7-3.6 3.8-3.7M22.5 18c-.3-2.3-1.7-3.6-3.8-3.7",
  "person.crop.circle": circled(c(12, 10, 3.2) + "M6 18.5c1.2-2.5 3.4-3.8 6-3.8s4.8 1.3 6 3.8"),
  "figure.walk": c(13, 4, 1.8) + "M12.5 7.5 10 13l3 3 1 5M10 13l-2.5 7.5M12 8.5l3.5 3 3 .5M12 8.5 8.5 10l-1 3.5",
  "figure.run": c(15, 4, 1.8) + "M9 8.5l4-1 3 3.5 3 .5M13 7.5l-2.5 6 3.5 2.5-1 5M10.5 13.5l-2 3.5H4",
  "hand.raised": "M8 13V6a1.5 1.5 0 0 1 3 0v5V4.5a1.5 1.5 0 0 1 3 0V11V5.5a1.5 1.5 0 0 1 3 0V14c0 4-2.5 7-6.5 7-2.5 0-4-1.3-5.5-3.5L3.5 13a1.5 1.5 0 0 1 2.5-1.5L8 14",
  "hand.thumbsup": "M7 10.5v10H3.5v-10zM7 19.5c1.5.7 3.5 1 6 1h3.5c1.2 0 2-.7 2.3-1.8l1.4-5.8c.3-1.3-.6-2.4-1.9-2.4H14l.7-4c.2-1.4-.8-2.5-2-2.5L7 10.5",
  "person.badge.plus": c(10, 7.5, 3.6) + "M3 20c.6-3.8 3.4-6.3 7-6.3 1.6 0 3 .5 4.2 1.3M18.5 13v7M15 16.5h7",
  "person.wave.2": PERSON + "M18.5 4.5c1.5 1.5 1.5 4.5 0 6M5.5 4.5c-1.5 1.5-1.5 4.5 0 6",
  "figure.2.and.child.holdinghands": c(6, 4.5, 1.8) + c(18, 4.5, 1.8) + c(12, 10.5, 1.4) + "M6 7.5v6.5M4 21l2-7 2 7M18 7.5v6.5M16 21l2-7 2 7M6 9.5l6 3.5 6-3.5M12 13v3.5M10.5 21l1.5-4.5 1.5 4.5",
  "brain.head.profile": "M15 21v-3.5h2.5c1 0 1.8-.8 1.8-1.8V13l1.7-.6-1.7-3.4C19 5.3 16 3 12.2 3 7.6 3 4 6.4 4 11c0 2.4 1 4.4 2.5 5.8V21" + "M10 9.5c0-1.2 1-2 2.2-2s2.2.8 2.2 2c0 1-.6 1.5-1.4 1.9-.8.4-.8 1-.8 1.6",
  heart: HEART,
  // Communication
  envelope: rr(2.5, 5, 19, 14, 2) + "M3 6.5l9 6.5 9-6.5",
  phone: "M6.5 3h3l1.5 4.5-2 1.5a11 11 0 0 0 6 6l1.5-2 4.5 1.5v3c0 1.2-1 2-2.2 2A17.5 17.5 0 0 1 4.5 5.2C4.5 4 5.3 3 6.5 3z",
  message: "M12 4c5 0 9 3.2 9 7.3s-4 7.2-9 7.2c-1 0-2-.1-2.9-.4L4 20.5l1.5-4.1C4 15 3 13.2 3 11.3 3 7.2 7 4 12 4z",
  "bubble.left.and.bubble.right": "M3 4.5h11v8H8l-3.5 3v-3H3zM16.5 8.5H21v8h-1.5v3l-3.5-3h-5.5v-2",
  megaphone: "M3.5 9.5v5h3l9 5v-15l-9 5zM6.5 14.5 8 20h2.5l-1-5M18.5 9.5a3 3 0 0 1 0 5",
  "antenna.radiowaves.left.and.right": c(12, 10, 1.6) + "M12 11.5V21M8 6a5.5 5.5 0 0 0 0 8M16 6a5.5 5.5 0 0 1 0 8M5 3.5a9 9 0 0 0 0 13M19 3.5a9 9 0 0 1 0 13",
  wifi: "M2.5 9a14 14 0 0 1 19 0M5.5 12.5a9.5 9.5 0 0 1 13 0M8.5 16a5 5 0 0 1 7 0M12 19.5h.01",
  paperplane: "M21 3 3 10.5l7 2.5 2.5 7zM21 3 10 13",
  bell: "M6 16.5V11a6 6 0 0 1 12 0v5.5l1.5 2h-15zM10 20.5a2 2 0 0 0 4 0",
  "quote.bubble": "M12 3.5c5 0 9 3.3 9 7.5s-4 7.5-9 7.5c-1 0-2-.1-3-.4L4 20l1.4-4C4 14.6 3 12.9 3 11c0-4.2 4-7.5 9-7.5zM8.5 12.5c0-2 1-3 2-3.5M13 12.5c0-2 1-3 2-3.5",
  video: rr(2.5, 6, 13, 12, 2) + "M15.5 10.5l6-3.5v10l-6-3.5",
  mic: rr(9, 2.5, 6, 11, 3) + "M5.5 11a6.5 6.5 0 0 0 13 0M12 17.5v4M8.5 21.5h7",
  // Technology
  desktopcomputer: rr(2.5, 3.5, 19, 13, 1.5) + "M12 16.5v4M8 20.5h8",
  laptopcomputer: rr(4.5, 5, 15, 10, 1.2) + "M2 18.5h20l-1-2.5H3z",
  iphone: rr(6.5, 2.5, 11, 19, 2.5) + "M10.5 5h3",
  "server.rack": rr(3, 3.5, 18, 5, 1) + rr(3, 9.5, 18, 5, 1) + rr(3, 15.5, 18, 5, 1) + "M6.5 6h.01M6.5 12h.01M6.5 18h.01",
  cpu: rr(6, 6, 12, 12, 1.5) + rr(9, 9, 6, 6, .5) + "M9 2.5V6M12 2.5V6M15 2.5V6M9 18v3.5M12 18v3.5M15 18v3.5M2.5 9H6M2.5 12H6M2.5 15H6M18 9h3.5M18 12h3.5M18 15h3.5",
  memorychip: rr(2.5, 7, 19, 9, 1) + "M6 10v3M10 10v3M14 10v3M18 10v3M5 16v3M9 16v3M15 16v3M19 16v3",
  externaldrive: rr(2.5, 8, 19, 9, 2) + "M3 12.5h18M17 14.8h.01",
  network: c(12, 4.5, 2) + c(4.5, 19.5, 2) + c(19.5, 19.5, 2) + c(12, 19.5, 2) + "M12 6.5v11M12 12H4.5v5.5M12 12h7.5v5.5",
  cloud: CLOUD,
  lock: rr(4.5, 10.5, 15, 10.5, 2) + "M8 10.5V7.5a4 4 0 0 1 8 0v3M12 14.5v2.5",
  key: c(7.5, 12, 4) + "M11.5 12h10M18.5 12v3.5M15.5 12v2.5",
  shield: "M12 2.5 4.5 5.5v6c0 5 3.3 8.5 7.5 10 4.2-1.5 7.5-5 7.5-10v-6z",
  gearshape: c(12, 12, 3) + "M12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3M5.3 5.3l2.1 2.1M16.6 16.6l2.1 2.1M5.3 18.7l2.1-2.1M16.6 7.4l2.1-2.1" + c(12, 12, 6.5),
  "wrench.and.screwdriver": "M14.5 6.5a4 4 0 0 0 5.4 4.9L11.5 20a2 2 0 0 1-3-3l8.6-8.4a4 4 0 0 1-2.6-2.1zM3 4.5 4.5 3l5 4-1.5 1.5zM8 8.5l3.5 3.5",
  hammer: "M14 4.5 18.5 9l-2 2-1.5-1.5L6 18.5a1.8 1.8 0 0 1-2.5-2.5l9-9L11 5.5l1-1c1-.9 2-.9 2 0z",
  terminal: rr(2.5, 4, 19, 16, 2) + "M6.5 9l3 3-3 3M11.5 15.5h5",
  qrcode: rr(3, 3, 7, 7, 1) + rr(14, 3, 7, 7, 1) + rr(3, 14, 7, 7, 1) + "M14 14h3v3h-3zM18 18h3v3h-3zM18 14h3M14 18v3M5.8 6.5h1.4M16.8 6.5h1.4M5.8 17.5h1.4",
  barcode: "M3.5 5v14M6.5 5v14M8.5 5v14M11.5 5v14M14 5v14M15.5 5v14M18 5v14M20.5 5v14",
  // Arrows
  "arrow.right": ARROW_R,
  "arrow.left": "M20 12H4M10 6l-6 6 6 6",
  "arrow.up": "M12 20V4M6 10l6-6 6 6",
  "arrow.down": "M12 4v16M6 14l6 6 6-6",
  "arrow.clockwise": "M19.5 12a7.5 7.5 0 1 1-2.2-5.3M19.5 4v5h-5",
  "arrow.triangle.2.circlepath": "M4.5 11a7.5 7.5 0 0 1 13-4.5M19.5 13a7.5 7.5 0 0 1-13 4.5M17.5 2.5v4h-4M6.5 21.5v-4h4",
  "arrow.up.right": "M6 18 18 6M8.5 6H18v9.5",
  "arrow.left.arrow.right": "M3.5 8h16M15.5 4l4 4-4 4M20.5 16h-16M8.5 12l-4 4 4 4",
  "chevron.right.2": "M5.5 5l7 7-7 7M12 5l7 7-7 7",
  "arrowshape.turn.up.right": "M13.5 4.5 21 11l-7.5 6.5V14C8 14 4.5 15.5 3 20c0-6 3-10.5 10.5-11z",
  "arrow.uturn.left": "M9 14 4 9l5-5M4 9h10.5a5.5 5.5 0 0 1 0 11H11",
  "arrow.triangle.branch": "M6 3.5v17M6 9.5c0 4 7 3 7 7.5V20M17 4l3 3-3 3M6 9.5C6 7 9 7 20 7",
  // Nature
  leaf: "M5 19C4 11 9 4.5 20 4c.5 10.5-6 16-15 15zM5 19l8-8",
  tree: "M12 2.5 5.5 12h3L5 17h14l-3.5-5h3zM12 17v4.5",
  "sun.max": c(12, 12, 4) + "M12 2v2.5M12 19.5V22M2 12h2.5M19.5 12H22M4.9 4.9l1.8 1.8M17.3 17.3l1.8 1.8M4.9 19.1l1.8-1.8M17.3 6.7l1.8-1.8",
  moon: "M20 14.5A8.5 8.5 0 1 1 9.5 4a7 7 0 0 0 10.5 10.5z",
  "cloud.sun": "M8 19.5h9a3.5 3.5 0 0 0 .5-7 5 5 0 0 0-9.6-.8A3.9 3.9 0 0 0 8 19.5zM8.5 3v1.5M3.5 8H2M4.8 4.3l1 1M13 5.5a4.5 4.5 0 0 0-8 2.5",
  "cloud.rain": "M7 15.5h10.5a3.8 3.8 0 0 0 .5-7.5 5.5 5.5 0 0 0-10.6-.9A4.2 4.2 0 0 0 7 15.5zM8 18l-1 3M12 18l-1 3M16 18l-1 3",
  snowflake: "M12 2.5v19M3.8 7.2l16.4 9.6M3.8 16.8l16.4-9.6M9.5 4l2.5 2.5L14.5 4M9.5 20l2.5-2.5 2.5 2.5",
  flame: "M12 21.5c-4 0-6.5-2.7-6.5-6.3 0-4.5 4-6.5 4.5-11.7 3 1.8 4.5 4.5 4.5 7 1-.7 1.8-2 2-3 1.8 2 2 4.5 2 7.6 0 3.6-2.5 6.4-6.5 6.4z",
  drop: "M12 2.5c3.5 4.5 6.5 8.5 6.5 12a6.5 6.5 0 0 1-13 0c0-3.5 3-7.5 6.5-12z",
  bolt: "M13.5 2.5 4.5 13.5H12l-1.5 8 9-11H12z",
  "globe.americas": circled("M12 2.5c-2.5 3-3.5 6.2-3.5 9.5s1 6.5 3.5 9.5M12 2.5c2.5 3 3.5 6.2 3.5 9.5s-1 6.5-3.5 9.5M2.5 12h19"),
  "mountain.2": "M2 19.5 9 7l4 7 2.5-3.5L22 19.5z",
  pawprint: c(7, 9.5, 1.8) + c(17, 9.5, 1.8) + c(10, 5.5, 1.8) + c(14, 5.5, 1.8) + "M12 12c-3 0-5.5 4.5-5.5 6.5 0 1.5 1.3 2.3 2.8 2l2.7-.6 2.7.6c1.5.3 2.8-.5 2.8-2 0-2-2.5-6.5-5.5-6.5z",
  ladybug: c(12, 13.5, 7) + "M12 6.5v14M8.5 4.5 10 6.5M15.5 4.5 14 6.5" + c(9, 12, 1) + c(15, 12, 1) + c(9, 16.5, 1) + c(15, 16.5, 1),
  // Education
  book: "M12 6.5C10 5 7 4.5 3 4.5v14c4 0 7 .5 9 2 2-1.5 5-2 9-2v-14c-4 0-7 .5-9 2zM12 6.5v14",
  "books.vertical": rr(3, 4, 4.5, 16.5, .8) + rr(7.5, 4, 4.5, 16.5, .8) + "M13 5.5l4.2-1.2 4.3 15.5-4.2 1.2z",
  graduationcap: "M2 9 12 4l10 5-10 5zM6 11v5c0 1.5 2.7 3 6 3s6-1.5 6-3v-5M22 9v6",
  pencil: "M15.5 4.5l4 4L8 20H4v-4zM13 7l4 4",
  highlighter: "M14 3.5l6.5 6.5-8 8-6.5-6.5zM6 11.5 4 18l2 2 6.5-2M3.5 21.5h6",
  ruler: "M3 16.5 16.5 3 21 7.5 7.5 21zM7 12.5l2 2M10 9.5l2 2M13 6.5l2 2M5.5 14l1 1M8.5 11l1 1M11.5 8l1 1",
  function: "M15 3.5c-2.5-.5-4 .5-4.5 3L8 18c-.5 2.5-2 3.5-4.5 2.5M6 9.5h9M13 13l6 6M19 13l-6 6",
  "x.squareroot": "M2.5 13.5h3l3 6.5 4-16.5h9M13.5 9.5l6 7M19.5 9.5l-6 7",
  lightbulb: "M9 17.5h6M10 21h4M12 2.5a6.5 6.5 0 0 0-3.8 11.8c.5.4.8 1 .8 1.6v1.6h6v-1.6c0-.6.3-1.2.8-1.6A6.5 6.5 0 0 0 12 2.5z",
  puzzlepiece: "M4 8h4a2.5 2.5 0 1 1 5 0h4v4a2.5 2.5 0 1 1 0 5v4H4v-4.5a2.5 2.5 0 1 0 0-5z",
  atom: c(12, 12, 1.5) + "M12 3c2 0 3.5 4 3.5 9S14 21 12 21s-3.5-4-3.5-9S10 3 12 3zM4.2 7.5c1-1.7 5.2-1 9.5 1.5s7.1 5.8 6.1 7.5-5.2 1-9.5-1.5-7.1-5.8-6.1-7.5zM4.2 16.5c-1-1.7 1.8-5 6.1-7.5s8.5-3.2 9.5-1.5-1.8 5-6.1 7.5-8.5 3.2-9.5 1.5z",
  flask: "M9 2.5h6M10 2.5v6L4.5 19c-.6 1.2.3 2.5 1.6 2.5h11.8c1.3 0 2.2-1.3 1.6-2.5L14 8.5v-6M7 14.5h10",
  "testtube.2": "M5.5 3h5M14 3h5M6.5 3v14.5a2 2 0 0 0 4 0V3M15 3v14.5a2 2 0 0 0 4 0V3M6.5 11.5h4M15 11.5h4",
  microscope: "M9 3.5l4 1-2 7.5-4-1zM11.5 9.5a5.5 5.5 0 0 1 3 9.5M4 20.5h16M7 17.5h7M9.5 13v4.5",
  // Travel
  airplane: "M10.5 21v-1.5l2-1.5v-5L3 16v-2l9.5-6V3.5a1.5 1.5 0 0 1 3 0V8L21 14v2l-5.5-3v5l2 1.5V21l-3.5-1z",
  car: "M3 16.5v-4l2-5.5c.3-.8 1-1.3 1.9-1.3h10.2c.9 0 1.6.5 1.9 1.3l2 5.5v4zM3 12.5h18M5 16.5v2.5M19 16.5v2.5" + c(7, 14.5, .6) + c(17, 14.5, .6),
  bus: rr(4, 3, 16, 15.5, 2.5) + "M4 11h16M4 7h16M8 18.5V21M16 18.5V21" + c(8, 14.5, .6) + c(16, 14.5, .6),
  tram: rr(5, 5, 14, 13, 2.5) + "M5 11h14M9 2.5h6M12 2.5V5M8 18l-2 3.5M16 18l2 3.5" + c(9, 14.5, .6) + c(15, 14.5, .6),
  bicycle: c(5.5, 15.5, 3.5) + c(18.5, 15.5, 3.5) + "M5.5 15.5l4-7h6l3 7M9.5 8.5l3.5 7h-7.5M14 5h3l-1.5 3.5",
  ferry: "M3 17.5l1.5-5h15l1.5 5M6.5 12.5v-4h11v4M9.5 8.5V5.5h5v3M2.5 20.5c1.5 0 2-1 3.2-1s1.8 1 3.2 1 2-1 3.1-1 1.8 1 3.2 1 2-1 3.1-1 1.8 1 3.2 1",
  map: "M3 6l6-2.5 6 2.5 6-2.5V18l-6 2.5-6-2.5-6 2.5zM9 3.5V18M15 6v14.5",
  "mappin.and.ellipse": c(12, 8, 2.2) + "M12 18c-4-4-6-7-6-10a6 6 0 0 1 12 0c0 3-2 6-6 10zM5 17.5c-1.5.5-2.5 1.2-2.5 2 0 1.4 4.3 2.5 9.5 2.5s9.5-1.1 9.5-2.5c0-.8-1-1.5-2.5-2",
  location: "M21 3 3 10.5l8 2.5 2.5 8z",
  house: "M3 11 12 3.5l9 7.5M5.5 9v11.5h13V9M10 20.5v-6h4v6",
  suitcase: rr(3, 7, 18, 13.5, 2) + "M8.5 7V4.5h7V7M8 7v13.5M16 7v13.5",
  globe: circled("M12 2.5c-2.5 3-3.5 6.2-3.5 9.5s1 6.5 3.5 9.5M12 2.5c2.5 3 3.5 6.2 3.5 9.5s-1 6.5-3.5 9.5M2.5 12h19M4 7h16M4 17h16"),
  // Symbols
  "checkmark.circle": circled("M7.5 12.5l3 3 6-6.5"),
  "xmark.circle": circled("M8.5 8.5l7 7M15.5 8.5l-7 7"),
  "exclamationmark.triangle": "M12 3 2 20.5h20zM12 9.5v5M12 17.5h.01",
  "questionmark.circle": circled("M9.5 9.5a2.5 2.5 0 1 1 3.5 2.3c-.6.3-1 .8-1 1.5v.7M12 16.8h.01"),
  "info.circle": circled("M12 11v6M12 7.5h.01"),
  "plus.circle": circled("M12 7.5v9M7.5 12h9"),
  "minus.circle": circled("M7.5 12h9"),
  star: STAR,
  "heart.fill": HEART,
  bookmark: "M6 3h12v18l-6-4.5L6 21z",
  tag: "M3 3h8.5l9.5 9.5-8.5 8.5L3 11.5zM7.5 7.5h.01",
  sparkles: "M10 3c.6 3.9 2.6 5.9 6.5 6.5-3.9.6-5.9 2.6-6.5 6.5-.6-3.9-2.6-5.9-6.5-6.5C7.4 8.9 9.4 6.9 10 3zM18 14c.3 1.8 1.2 2.7 3 3-1.8.3-2.7 1.2-3 3-.3-1.8-1.2-2.7-3-3 1.8-.3 2.7-1.2 3-3z",
  crown: "M3 8l4.5 4L12 5l4.5 7L21 8l-2 11H5zM5 21.5h14",
  infinity: "M12 12c-2-2.5-3.5-4-5.5-4a4 4 0 0 0 0 8c2 0 3.5-1.5 5.5-4zm0 0c2 2.5 3.5 4 5.5 4a4 4 0 0 0 0-8c-2 0-3.5 1.5-5.5 4z",
  number: "M9.5 3.5 7.5 20.5M16.5 3.5l-2 17M4 8.5h16.5M3.5 15.5H20",
  percent: c(7, 7, 2.5) + c(17, 17, 2.5) + "M19 5 5 19",
  // Media
  "play.circle": circled("M10 8.5v7l6-3.5z"),
  "pause.circle": circled("M10 8.5v7M14 8.5v7"),
  "music.note": "M9 17.5V5l10-2v12.5" + c(6.5, 17.5, 2.5) + c(16.5, 15.5, 2.5),
  headphones: "M3.5 17v-4a8.5 8.5 0 0 1 17 0v4" + rr(3.5, 13.5, 4, 7, 1.5) + rr(16.5, 13.5, 4, 7, 1.5),
  camera: "M3 8.5c0-1 .8-1.8 1.8-1.8h2.7L9 4.5h6l1.5 2.2h2.7c1 0 1.8.8 1.8 1.8v10c0 1-.8 1.8-1.8 1.8H4.8c-1 0-1.8-.8-1.8-1.8z" + c(12, 13, 3.8),
  photo: rr(2.5, 4, 19, 16, 2) + c(8, 9, 1.8) + "M2.5 17l5.5-5 4 3.5 3.5-3 5.5 5",
  film: rr(3, 3, 18, 18, 1.5) + "M7 3v18M17 3v18M3 7.5h4M3 12h4M3 16.5h4M17 7.5h4M17 12h4M17 16.5h4",
  tv: rr(2.5, 5, 19, 13, 1.5) + "M8 21h8M8.5 2.5 12 5l3.5-2.5",
  gamecontroller: "M7 7h10a4.5 4.5 0 0 1 4.5 4.8l-.4 4.7a2.8 2.8 0 0 1-5 1.5L14.5 16h-5l-1.6 2a2.8 2.8 0 0 1-5-1.5l-.4-4.7A4.5 4.5 0 0 1 7 7zM7.5 10v4M5.5 12h4M15.5 11h.01M17.5 13h.01",
  paintpalette: "M12 3a9 9 0 0 0 0 18c1.2 0 1.8-.8 1.8-1.7 0-1.4-1.3-1.9-1.3-3.3 0-1 .8-1.8 1.8-1.8H17a4 4 0 0 0 4-4C21 6 17 3 12 3z" + c(7.5, 11.5, 1) + c(9.5, 7.5, 1) + c(14.5, 7.5, 1),
  theatermasks: "M3 4.5c3-1 6-1 9 0V11c0 3-2 5.5-4.5 5.5S3 14 3 11zM12 9c3-1 6-1 9 0v6.5c0 3-2 5.5-4.5 5.5-1.6 0-3-1-3.8-2.5M5.5 8.5h1.5M8.5 8.5H10M5.8 12.5a2.5 2.5 0 0 0 3.4 0M14.5 13h1.5M17.5 13H19M14.8 17.5a2.5 2.5 0 0 1 3.4 0",
  // Health
  "cross.case": rr(2.5, 6.5, 19, 14, 2) + "M8.5 6.5V4.5h7v2M12 10.5v6M9 13.5h6",
  pills: rr(2.5, 9, 11, 6, 3) + "M8 9v6" + c(17.5, 14.5, 4) + "M14.7 17.3l5.6-5.6",
  stethoscope: "M5.5 3H4.5v6a4.5 4.5 0 0 0 9 0V3h-1M9 13.5v2a5 5 0 0 0 10 0v-2" + c(19, 11, 2),
  "heart.text.square": rr(3, 3, 18, 18, 3) + "M12 16.5s-4.5-2.8-4.5-6A2.3 2.3 0 0 1 12 9.3a2.3 2.3 0 0 1 4.5 1.2c0 3.2-4.5 6-4.5 6z",
  bandage: "M3.8 14.5 14.5 3.8a3.5 3.5 0 0 1 5 5L8.8 19.5a3.5 3.5 0 0 1-5-5zM9 9l6 6M10.5 11.5h.01M12.5 9.5h.01M11.5 13.5h.01M13.5 11.5h.01",
  syringe: "M18 2.5l3.5 3.5M19.7 4.3 16 8M17.5 9.5l-3-3M15.5 5.5l3 3L9 18H6v-3zM6 18l-3.5 3.5M9.5 9.5l2 2M12 7l2 2",
  "bed.double": "M2.5 19.5v-12M2.5 14.5h19v5M21.5 14.5v-3c0-1.4-1.1-2.5-2.5-2.5H9v5.5M4.5 11.5a2 2 0 1 0 4 0 2 2 0 1 0-4 0",
  "figure.mind.and.body": c(12, 4.5, 2) + "M4 10.5c2.5 1 5 1.5 8 1.5s5.5-.5 8-1.5M12 12v4M7 21l5-5 5 5M4 18.5c2-1 4-1.5 8-1.5s6 .5 8 1.5",
  // Misc used elsewhere in the app
  "speaker.wave.2": "M3.5 9.5v5h4l5 4.5V5l-5 4.5zM16 9a4 4 0 0 1 0 6M18.5 6.5a7.5 7.5 0 0 1 0 11",
  tablecells: rr(3, 4, 18, 16, 1.5) + "M3 9.5h18M3 14.8h18M9 4v16M15 4v16",
};

const FILLED = new Set(["heart.fill", "star", "bolt", "drop", "flame"]);

/** The SVG path for a symbol, or a generic shape when the name is unknown. */
export function symbolPath(name: string): { d: string; filled: boolean } {
  const d = SYMBOLS[name] ?? SYMBOLS[name.replace(/\.(fill|circle|square)$/, "")] ?? circled("M12 7.5v5M12 16h.01");
  return { d, filled: FILLED.has(name) || name.endsWith(".fill") };
}

const path2D = new Map<string, Path2D>();

/** Draws a symbol, fitted into a rectangle. */
export function drawSymbol(ctx: CanvasRenderingContext2D | OffscreenCanvasRenderingContext2D, name: string,
  r: { x: number; y: number; w: number; h: number }, color: string, flipH = false, flipV = false) {
  const { d, filled } = symbolPath(name);
  let p = path2D.get(d);
  if (!p) { p = new Path2D(d); path2D.set(d, p); }
  const s = Math.min(r.w, r.h) / 24;
  ctx.save();
  ctx.translate(r.x + r.w / 2, r.y + r.h / 2);
  ctx.scale(s * (flipH ? -1 : 1), s * (flipV ? -1 : 1));
  ctx.translate(-12, -12);
  ctx.strokeStyle = color;
  ctx.fillStyle = color;
  ctx.lineWidth = 1.7;
  ctx.lineCap = "round";
  ctx.lineJoin = "round";
  if (filled) ctx.fill(p, "nonzero");
  ctx.stroke(p);
  ctx.restore();
}

export function symbolSVG(name: string, size = 24): string {
  const { d, filled } = symbolPath(name);
  return `<svg viewBox="0 0 24 24" width="${size}" height="${size}" fill="${filled ? "currentColor" : "none"}" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="${d}"/></svg>`;
}
