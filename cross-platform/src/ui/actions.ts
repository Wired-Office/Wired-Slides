import type { UUID } from "../model/types";

/** App-level commands the ribbon, menus and canvas share. */
export interface AppActions {
  newPresentation(): void;
  open(): void;
  openRecent(path: string): void;
  save(): Promise<boolean>;
  saveAs(): Promise<boolean>;
  exportAs(kind: "pdf" | "png" | "jpeg" | "outline"): void;
  print(kind?: "slides" | "handouts" | "notes" | "outline"): void;
  close(): void;
  cut(): void;
  copy(): void;
  paste(asText?: boolean): void;
  duplicate(): void;
  insertPictures(replacing?: UUID): void;
  insertMedia(kind: "video" | "audio"): void;
  insertTable(): void;
  insertSmartArt(): void;
  insertIcon(): void;
  insertSymbol(): void;
  insertDateTime(): void;
  insertSlidesFromOutline(): void;
  reuseSlides(): void;
  photoAlbum(): void;
  editChart(id: UUID): void;
  hyperlink(): void;
  action(): void;
  altText(): void;
  findReplace(replace: boolean): void;
  replaceFonts(): void;
  headerFooter(): void;
  slideSize(): void;
  formatBackground(): void;
  setUpShow(): void;
  startShow(from: number | "current", presenter?: boolean, rehearse?: boolean): void;
  readingView(): void;
  accessibility(): void;
  wordCount(): void;
  spelling(): void;
  properties(): void;
  preferences(): void;
  about(): void;
  checkForUpdates(): void;
  openURL(url: string): void;
  designIdeas(): void;
  cropPicture(): void;
}
