/** App preferences, stored per machine. */
export interface Settings {
  showTemplateChooserOnLaunch: boolean;
  defaultThemeID: string;
  authorName: string;
  /** Default format for Save. */
  defaultFormat: "wslides" | "pptx";
  smartGuides: boolean;
  snapToGrid: boolean;
  checkForUpdates: boolean;
  lastUpdateCheck: number;
  skippedVersion: string;
  recentFiles: string[];
}

const KEY = "wiredslides.settings";

const defaults: Settings = {
  showTemplateChooserOnLaunch: true,
  defaultThemeID: "wired",
  authorName: "",
  defaultFormat: "wslides",
  smartGuides: true,
  snapToGrid: false,
  checkForUpdates: true,
  lastUpdateCheck: 0,
  skippedVersion: "",
  recentFiles: [],
};

let current: Settings = load();
const listeners = new Set<(settings: Settings) => void>();

function load(): Settings {
  try {
    return { ...defaults, ...JSON.parse(localStorage.getItem(KEY) ?? "{}") };
  } catch {
    return { ...defaults };
  }
}

export function settings(): Settings {
  return current;
}

export function updateSettings(change: Partial<Settings>) {
  current = { ...current, ...change };
  try {
    localStorage.setItem(KEY, JSON.stringify(current));
  } catch {
    // Settings still apply for this session.
  }
  listeners.forEach((listener) => listener(current));
}

export function onSettingsChange(listener: (settings: Settings) => void) {
  listeners.add(listener);
}

export function addRecentFile(path: string) {
  const recent = [path, ...settings().recentFiles.filter((p) => p !== path)].slice(0, 10);
  updateSettings({ recentFiles: recent });
}
