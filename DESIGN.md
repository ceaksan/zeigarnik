---
name: Zeigarnik # project.yml PRODUCT_NAME (no CFBundleDisplayName; window title "Zeigarnik" in ZeigarnikScenes.swift)
company: ceaksan # decided by Ceair 2026-11-21
brand: Zeigarnik # decided by Ceair 2026-11-21
design_version: 1.2.0
product_version: 0.2.1 # project.yml MARKETING_VERSION (matches zeigarnikVersion in AgentService.swift and tag v0.2.1)
source_commit: 95ac6bf
updated: 2026-11-22
template: design/template.fig
status: implemented
schemes: [light, dark] # NSColor dynamicProvider in Theme.swift; Appearance setting System, Light, Dark
source:
  - Sources/ZeigarnikUI/Theme/Theme.swift
  - Sources/ZeigarnikUI/Theme/Components.swift
colors:
  bg: { light: "#ececec", dark: "#1b1b1d" }
  window: { light: "#ffffff", dark: "#232325" }
  side: { light: "#f5f5f7", dark: "#2a2a2d" }
  line: { light: "#e3e3e6", dark: "#3a3a3d" }
  text: { light: "#1d1d1f", dark: "#f2f2f4" }
  muted: { light: "#86868b", dark: "#9a9aa0" }
  accent: { light: "#0a84ff", dark: "#0a84ff" }
  accentSoft: { light: "#e5f0ff", dark: "#16304f" }
  warn: { light: "#c2410c", dark: "#fb923c" }
  danger: { light: "#d70015", dark: "#ff453a" }
  warnSoft: { light: "#fff1e6", dark: "#3a2416" }
  ok: { light: "#1a7f37", dark: "#4ade80" }
  okSoft: { light: "#e7f6ec", dark: "#163222" }
  chips: # project chip backgrounds, index from stableColorIndex (FNV-1a of the project id, mod 6)
    light: ["#dbeafe", "#fce7f3", "#dcfce7", "#fef3c7", "#ede9fe", "#e0f2fe"]
    dark: ["#1e3a5f", "#4a1d38", "#173d26", "#4a3a10", "#33275a", "#123a52"]
  live: { light: "#28c840", dark: "#28c840" }
  star: { light: "#f5a524", dark: "#f5a524" }
  today: { light: "#ff3b30", dark: "#ff3b30" }
  onAccent: "Color.white" # SwiftUI constant, same in both appearances
  specTrack: "line" # Theme.swift:31 specTrack = line since 2026-11-22 (Ceair); was Color.gray.opacity(0.2), a system gray at 20%
  derived: # computed in views, not separate tokens
    hoverTint: "text at 5% opacity" # NoteCardLayout.hoverTint
    sparklineBar: "accent at 75% opacity"
    outOfMonthDay: "side at 60% opacity"
typography:
  family: "SF system font (Font.system)"
  body: 13pt regular
  small: 11.5pt regular
  caption: 11pt semibold # SectionHeader, uppercased, tracking 0.44
  title: 17pt semibold
  chip: 11pt regular
  dayTotal: 10.5pt regular
  keyValue: 12.5pt regular
  ad-hoc: # set inline in views, not in Theme
    sheet-heading: 14pt semibold # GoToDateSheet, ScheduleSheet, Welcome step titles
    welcome-title: 22pt semibold
    day-number: 12pt regular # MonthView DayCell
rounded:
  corner: 8pt # note cards, note input, missing-project banner
  tagCorner: 5pt
  chipCorner: 4pt # project and scheduled chips
  specBar: 3pt
  sparklineBarTop: 2pt
  menuRow: 6pt
  todayBadge: capsule
spacing:
  inspectorPadding: 14pt
  keyColumnWidth: 110pt
  rowPadding: "8pt 10pt" # defined in Theme, not referenced by any view
  keyValueGrid: { horizontal: 8pt, vertical: 5pt }
  sectionHeader: { top: 14pt, bottom: 6pt }
  noteCard: { padding: 8pt, footerGap: 6pt, footerHeight: 24pt }
  tag: { vertical: 1pt, horizontal: 6pt }
  chip: { vertical: 1pt, horizontal: 5pt }
  banner: { vertical: 8pt, horizontal: 14pt }
  sheet: 16pt
  welcome: 24pt
  menubar: 10pt
components:
  main-window: { default: "1320 x 820", min: "1000 x 620" }
  sidebar: { min: 180pt, ideal: 200pt }
  inspector: { min: 300pt, ideal: 340pt, max: 460pt }
  settings-window: { width: 520pt, min-height: 760pt }
  welcome-window: { size: "580 x 660" }
  go-to-date-sheet: { width: 320pt }
  schedule-sheet: { width: 400pt }
  menubar-panel: { width: 340pt }
  design-gallery: { min: "700 x 600", column: 440pt }
  live-dot: { size: 7pt }
  spec-bar: { width: 60pt, height: 5pt }
  sparkline: { height: 46pt, bar-gap: 3pt, min-fraction: 0.02 }
  note-input: { min-height: 58pt, padding: 4pt }
  month-cell: { min-row-height: 108pt, padding: "5pt 6pt", selected-border: 2pt }
  draft-card-border: { width: 1pt, dash: "4 3" }
motion:
  animations: none # no withAnimation or .animation in Sources/ZeigarnikUI
  copy-path-confirmation: 1.5s # icon swap to a checkmark, then back
---

# Zeigarnik design

Zeigarnik is a native macOS app (macOS 14 or later, SwiftUI with some AppKit) that shows, day by day, what is going on across a developer's git repositories: last activity by Claude Code, Codex or commit, uncommitted and unpushed work, README and architecture document drift, spec progress, estimated time, repository visibility, and the owner's notes, pins and scheduled follow-ups. It is used by one developer on their own Mac. Everything on screen comes from a local SQLite database filled by the scanner.

This document describes the shipped 0.2.1 interface at commit `017819a`. The Swift sources are the source of truth: [Theme.swift](Sources/ZeigarnikUI/Theme/Theme.swift) for tokens and [Components.swift](Sources/ZeigarnikUI/Theme/Components.swift) for shared components. When this file and the code disagree, the code wins and this file is out of date. Product and architecture context: [README](README.md), [architecture.md](architecture.md), [ADRs](docs/adr/).

`design/template.fig` does not exist yet; it is created separately (see Files and regeneration). No screen captures exist in the repository.

## Overview

Surfaces:

| Surface | Kind | Source |
| --- | --- | --- |
| Main window "Zeigarnik" | `Window` with `NavigationSplitView`: sidebar, detail (List or Calendar), right inspector | `Sources/ZeigarnikUI/ZeigarnikScenes.swift:11`, `Sources/ZeigarnikUI/Window/RootView.swift` |
| Welcome to Zeigarnik | Separate window, first run and Help menu | `Sources/ZeigarnikUI/Welcome/WelcomeView.swift` |
| Settings | Standard macOS Settings scene, grouped form | `Sources/ZeigarnikUI/Settings/SettingsView.swift` |
| Menu bar extra | `MenuBarExtra` with `.window` style | `Sources/ZeigarnikUI/Menubar/MenubarView.swift` |
| Sheets | Go to Date, Schedule (new and edit) | `Sources/ZeigarnikUI/Sheets/` |
| Design Gallery, Menu Bar Preview | DEBUG builds only, audit windows | `Sources/ZeigarnikUI/ZeigarnikScenes.swift:53` |

Shipped: everything above except the two DEBUG windows, which are compiled only in Debug. The Design Gallery renders sample components with synthetic names ("orbit", "lumen") in light and dark side by side; it is a fixture, not product data.

UI text is English. Dates, times and decimals follow the calendar locale (`Sources/ZeigarnikKit/Format/Format.swift:3`); the month grid starts on the locale's first weekday.

## Principles

These are read from code and comments, not from a separate design brief.

1. A failure never looks like empty data. Read and write errors, missing folders and unreadable agent logs are shown as banners while the last loaded rows stay on screen (`Sources/ZeigarnikKit/Model/AppModel.swift:68-71`, `Sources/ZeigarnikKit/Scan/SourceHealth.swift:25`).
2. No system dialogs. Deletes confirm inline inside the card or sheet (`Sources/ZeigarnikUI/Sheets/ScheduleSheet.swift:103`, `Sources/ZeigarnikUI/Theme/Components.swift:248`).
3. Color carries state: `warn` for attention, `ok` for good or public, `accent` for scheduled and selected, `danger` only on the destructive confirm button.
4. Turned-off checks disappear from the table, the sidebar, the inspector and the menu bar instead of showing stale values.

## Colors

Every token in `Theme` is a dynamic `NSColor` that picks the light or dark value from the current appearance (`Sources/ZeigarnikUI/Theme/Theme.swift:48-58`). The app appearance follows the system unless Settings > General > Appearance sets Light or Dark (`Sources/ZeigarnikUI/AppEnvironment.swift:187-193`). No hex value appears in a view outside `Theme.swift`. Window, sidebar and table backgrounds are the system defaults of `NavigationSplitView`, `List(.sidebar)`, `Table` and `Form(.grouped)`; `Theme.bg` is only used by the Design Gallery.

| Role | Tokens | Use |
| --- | --- | --- |
| Surface | `window`, `side`, `bg` | `window`: note input fill, gallery columns. `side`: neutral banner fill, days outside the month (60%). `bg`: gallery background only. |
| Text | `text`, `muted` | `muted` for secondary text, agent names, empty states, placeholders, section headers, footers, inactive values in table cells. |
| Structure | `line` | Card borders, note input border, month grid lines, neutral tag fill. |
| Interaction and schedule | `accent`, `accentSoft`, `onAccent` | `accent`: scheduled chip fill, scheduled card border, selected day border (2 pt), spec bar fill, sparkline bars (75%). `accentSoft`: scheduled card fill, menu bar row hover. `onAccent`: text on scheduled chips and on the today badge. |
| Attention | `warn`, `warnSoft` | Warn tags (push needs attention, README behind, dirty over 50, external evidence), warning banners, inline error text, row error icon. |
| Positive | `ok`, `okSoft` | Ok tags, Public in the Visibility column, done evidence check. |
| Destructive | `danger` | Tint of the confirming Delete button and the Delete button in the schedule sheet. |
| Markers | `live`, `star`, `today` | `live`: Open Now dot. `star`: pin star. `today`: today's day number capsule. |
| Project chips | `chips[0...5]` | Calendar project chips; the index is a stable hash of the project id, so a project keeps its color across launches (`Sources/ZeigarnikKit/List/ColorIndex.swift:1-9`). |
| Spec track | `specTrack` | Unfilled part of the spec bar. Equals `line` since 2026-11-22 (`Theme.swift:31`). |

`accent`, `live`, `star` and `today` have the same value in both appearances. Prominent buttons (`.borderedProminent`) use the system tint, not `Theme.accent`.

## Typography

All text uses the system font through `Font.system`, sized in points.

| Token | Size and weight | Use |
| --- | --- | --- |
| `title` | 17 pt semibold | Inspector project name and day title, month title |
| `body` | 13 pt | Default for cards, banners, settings, menu bar, welcome |
| `keyValue` | 12.5 pt | Inspector facts grid |
| `small` | 11.5 pt | Paths, helper text, errors, evidence lines, footers |
| `caption` | 11 pt semibold | Section headers (uppercased, tracking 0.44) and weekday headers |
| `chip` | 11 pt | Tags, chips, note card date line, draft label |
| `dayTotal` | 10.5 pt | Day total in a month cell |

Inline sizes outside `Theme`: 14 pt semibold for sheet headings and welcome step titles, 22 pt semibold for the welcome title, 12 pt for month day numbers. Project names in the table are semibold; spec titles in the inspector are semibold. The Total Time column uses monospaced digits.

## Layout

Main window: default 1320 x 820, minimum 1000 x 620 (`Sources/ZeigarnikUI/ZeigarnikScenes.swift:18`, `Sources/ZeigarnikUI/Window/RootView.swift:35`). Three columns:

1. Sidebar (180 to 200 pt) with sections Views (★ Pinned, All, Open Now), Attention (Uncommitted, Push / Upstream, README Behind, Architecture Behind, Public, Quiet 30+ Days) and Folders (folder groups, Other, Missing). Each filter row shows a count badge; Other has none.
2. Detail: warning banners stacked at the top, then the List table, the Other bucket list or the Calendar month grid.
3. Inspector (300, ideal 340, max 460 pt), hidden on launch, toggled by the Details toolbar button and opened automatically on selection.

Toolbar: a segmented List / Calendar picker in the principal position, Go to Date…, Scan (a small spinner while scanning), Details, and the search field "Search projects".

Project table columns, in order: pin (18 pt), Project, Last Activity, Last Commit, Dirty, Push, README, Visibility, ≈ Total Time, Spec / Plan. SwiftUI `Table` allows 10 columns and the table uses all 10 (architecture.md, Constraints).

Month grid: header row (month title, previous, Today, next), weekday headers, then a 7 x 6 grid of 42 days. Row height is the larger of 108 pt and one sixth of the available height; the grid scrolls when the window is shorter (`Sources/ZeigarnikUI/Calendar/MonthView.swift:20-33`).

Inspector content is a single scrolling column with 14 pt padding: header, facts, section headers, cards, input.

Density: compact desktop density with 11 to 13 pt text. Spacing values are in the frontmatter.

## Elevation and depth

No custom shadows. Depth comes from system window chrome, the split view, sheets and the menu bar panel. Cards are flat with a 1 pt border; hover adds a 5% `text` tint.

## Shapes

Rounded rectangles throughout: 8 pt for note cards and the note input, 5 pt for tags, 4 pt for chips, 3 pt for the spec bar, 6 pt for menu bar rows, 2 pt top corners on sparkline bars, a capsule for today's day number, a circle for the live dot. Draft cards use a dashed 1 pt border (4 on, 3 off). Month cells are square with 1 pt right and bottom lines.

## Motion

None. There is no `withAnimation` or `.animation` in the UI sources; state changes switch instantly. The only timed change is Copy Path: its icon becomes a checkmark for 1.5 s (`Sources/ZeigarnikUI/Inspector/ProjectInspector.swift:47-53`). No reduced-motion handling exists because nothing animates.

## Components

All in `Sources/ZeigarnikUI/Theme/Components.swift` unless noted.

- **Tag** (`:4-41`): text pill in `chip` type, tones `neutral` (text on `line`), `warn` (`warn` on `warnSoft`), `ok` (`ok` on `okSoft`).
- **ProjectChip** (`:43-66`): project name plus optional detail (duration); the detail never truncates, the name truncates first. Background from `chips` by color index.
- **ScheduledChip** (`:68-85`): "◷ " plus time and project, white on `accent`, one line.
- **NoteMarker** (`:87-104`): "✎ " plus text, `muted`, no background.
- **LiveDot** (`:106-116`): 7 pt `live` circle, tooltip and accessibility label "Open Now".
- **SpecBar** (`:118-142`): 60 x 5 pt track with `accent` fill for done/total; accessibility label "Spec progress", value "done/total".
- **SectionHeader** (`:144-159`): uppercased `caption` in `muted`.
- **KeyValueGrid** (`:161-183`): two columns, keys in `muted` at 110 pt, values in `text`.
- **NoteCard** (`:193-238`): text, then a footer with date (prefixed "◷ " when scheduled), optional badge tag and accessory. States: plain (1 pt `line` border), scheduled (`accentSoft` fill, `accent` border), interactive hover (5% tint, only when an accessory exists). With an accessory the footer is fixed at 24 pt so the text never moves.
- **CardActions** (`:249-276`): pencil and trash icon buttons in `muted`. Confirming state: "Delete?" with Cancel and a `danger` tinted prominent Delete, small control size.
- **ScheduledItemCard** (`:279-294`): NoteCard in scheduled style with a sync badge; tapping the card opens the editor. Delete help text: "Delete; the calendar event goes too".
- **EditableNoteCard** (`Sources/ZeigarnikUI/Sheets/ScheduleSheet.swift:105-152`): NoteCard with CardActions; edit swaps in the inline editor. Context menu: Edit, Delete.
- **InlineNoteEditor** (`Sources/ZeigarnikUI/Sheets/ScheduleSheet.swift:155-179`): NoteInput plus "⌘↩ saves, Esc cancels", Cancel and a prominent save button, inline error.
- **DraftNoteCard** (`Sources/ZeigarnikUI/Sheets/ScheduleSheet.swift:183-254`): dashed border, text in `muted`, footer "<Kind> draft" (README, Architecture, Push, Uncommitted), checkmark (Accept as a note) and xmark (Dismiss until this is resolved). Context menu: Accept as Note…, Dismiss.
- **NoteInput** (`Sources/ZeigarnikUI/Inspector/ProjectInspector.swift:206-225`): `TextEditor` at least 58 pt high on `window`, 8 pt corner, `line` border, `muted` placeholder.
- **Sparkline** (`:296-317`): 14 bars, 46 pt high, 3 pt gap, `accent` at 75%, minimum bar 2% of the height.
- **Banner** (`:319-358`): full-width strip; tones neutral (`side`), warn (`warnSoft` with a triangle icon), ok (`okSoft`).
- **ProjectOpenButtons** (`Sources/ZeigarnikUI/Support/ProjectOpenButtons.swift`): Show in Finder, Copy Path (menu form only), Open in <terminal>, Open in herdr (only when `hc` is installed), Open in <editor>. Compact form in the inspector shows short labels with icons.
- **MenuRow** (`Sources/ZeigarnikUI/Menubar/MenubarView.swift:97-114`): plain button row, `accentSoft` hover with a 6 pt corner.

## Behavior rules

Navigation and keyboard

- ⌘1 shows List, ⌘2 shows Calendar (`Sources/ZeigarnikUI/Window/RootView.swift:129-136`). ⌘L opens Go to Date, ⌘R scans with fetch (`RootView.swift:107-118`). ⌘F (Find Projects, replaces the Edit menu text group) focuses the toolbar search field through AppKit, because `searchFocused` needs macOS 15 (`Sources/ZeigarnikUI/ZeigarnikScenes.swift:21-23`, `Sources/ZeigarnikUI/Support/SearchFieldFocus.swift`).
- Changing the sidebar selection switches the detail to List (`RootView.swift:31`). Selecting a project opens the inspector; selecting a day opens it in Calendar view (`RootView.swift:33-34`). With nothing selected the inspector shows "Select a project" or "Select a day".
- Go to Date and every menu bar schedule row switch to Calendar, show that month and select the day (`Sources/ZeigarnikKit/Model/AppModel.swift:372-379`).
- In sheets, Return is the default action and Esc cancels. In the inspectors ⌘↩ triggers Add Note; in the inline editor ⌘↩ and Esc are read from the focused editor so they do not clash with Add Note (`Sources/ZeigarnikUI/Sheets/ScheduleSheet.swift:104`, `:164-169`).

List, filters, search, sort

- Search matches display name or path, ignoring case and diacritics, and treats ı and İ as i and I (`Sources/ZeigarnikKit/List/ProjectFilter.swift:74-89`).
- Every filter except Pinned and Missing counts only active projects; Pinned includes missing pinned projects (`ProjectFilter.swift:37-63`). Quiet 30+ Days means neither activity nor commit in more than 30 days, or none recorded. Push / Upstream means no upstream, ahead or behind; a detached HEAD is not counted (`Sources/ZeigarnikKit/Format/Format.swift:55-58`).
- Sidebar rows appear conditionally: Open Now only when herdr's `hc` is installed, with a "?" badge when its state cannot be read; README Behind only with the README check on; Architecture Behind only with that check on and at least one project with an architecture document; Public only with the visibility check on and at least one public repository (`Sources/ZeigarnikUI/Window/SidebarView.swift:15-32`). Folder groups sort by name, then Root, then Outside (`SidebarView.swift:52-59`).
- Default sort is Last Activity, newest first (`Sources/ZeigarnikKit/Model/AppModel.swift:81-82`). Rows without a value for the sort key always go last in either direction; ties sort by name (`Sources/ZeigarnikKit/List/ProjectSort.swift:7-23`).
- Columns can be hidden, reordered and resized from the header context menu; the layout persists in `projectTableColumns`. Project cannot be hidden. README and Visibility columns hide and show with their checks (`Sources/ZeigarnikUI/List/ProjectTableView.swift:16-17`, `:40`, `:98-106`).
- Dirty shows a neutral tag, or a warn tag above 50 files (`ProjectTableView.swift:121-128`). Push and README show a warn tag when they need attention, otherwise muted text. Public visibility is `ok` colored.
- Right-clicking one row opens the Open buttons menu (`ProjectTableView.swift:88-92`).

Notes, drafts, schedules, pins, spec marks

- An empty note is ignored without an error. A day note without a project shows "Select a project for the note." (`Sources/ZeigarnikUI/Inspector/DayInspector.swift:104-116`).
- A note from the project inspector is dated today; a note from the day inspector is dated the selected day (`AppModel.swift:264-270`). The day inspector preselects the project only when exactly one project was active that day (`AppModel.swift:311-318`).
- Deleting a note or a scheduled item always passes an inline confirmation: "Delete?" on cards, "Are you sure?" in the schedule sheet. The context menu Delete enters the same confirmation (`Sources/ZeigarnikUI/Sheets/ScheduleSheet.swift:47-60`, `:125-128`).
- Accepting a draft opens it in the editor; saving adds a note dated today and dismisses the draft. Dismissing hides that kind of draft for the project until its state clears (`AppModel.swift:278-288`, ADR-006).
- New schedule from a project: title "<project>: ", next full hour, 1 hour, Also add to macOS Calendar on (`Sources/ZeigarnikUI/Inspector/ProjectInspector.swift:179-191`). From a day: 10:00 on that day, project from the day's picker (`DayInspector.swift:62-64`, `:83-87`). The project picker is hidden when editing or when the project and a title are already set (`ScheduleSheet.swift:21`). Durations offered: 30 min, 1, 1.5, 2 and 3 hours, plus the item's own duration if different (`ScheduleSheet.swift:81-84`). An empty title saves as the project name (`AppModel.swift:330-331`).
- Saving a schedule with calendar on asks for calendar access the first time (`Sources/ZeigarnikUI/AppEnvironment.swift:259-265`). The sheet shows a warning for denied, write-only, not yet requested, or no target calendar (`AppEnvironment.swift:249-256`). Sync badges: Pending, In Calendar, Not in Calendar, Removed from Calendar, "Unresolved: <detail>" (`Sources/ZeigarnikUI/Support/UIFormat.swift:21-29`).
- ★ Pin and Unpin toggle immediately. Mark Done, Mark Not Done and Reset on a spec apply immediately without confirmation and start a scan without fetch (`AppModel.swift:352-356`).

Persistence and refresh

- Notes, pins, schedules and spec marks are written to SQLite at once; there is no save step. Settings apply on change (no Save button); a folder or vault change rescans, an added folder also fetches, an activity gap change reloads totals (`Sources/ZeigarnikKit/Model/AppSettings.swift:109-140`). Removing a folder in Settings or Welcome has no confirmation.
- Changes made by the `zeigarnik` CLI or an agent appear within 2 seconds; upcoming items refresh every 60 seconds (`AppEnvironment.swift:90-103`).

Errors and empty states

- Detail banners, top to bottom: database open failure, failed reload (last rows stay), owner data failure, each source problem (with Open Settings for a folder or vault), moved projects found again (neutral), errors in last scan (`Sources/ZeigarnikUI/Window/RootView.swift:76-96`).
- A project with a scan error shows a warn triangle with the error as tooltip. A missing project shows a warn banner in its inspector; its notes and schedules are kept.
- Table empty: spinner with "First scan in progress: reading repositories, git status and agent history." while the first scan runs, otherwise "No projects in this view" (`ProjectTableView.swift:107-118`).
- Open errors ("<app> is no longer installed.", "Could not open in <app>: …") appear under the inspector's open buttons (`AppEnvironment.swift:140-152`).

Welcome and menu bar

- The Welcome window opens on launch until finished once; its button reads "Skip for Now" without folders and "Start" with folders, and both mark it shown. Help > Welcome to Zeigarnik reopens it (`Sources/ZeigarnikUI/ZeigarnikScenes.swift:81-99`, `Sources/ZeigarnikUI/Welcome/WelcomeView.swift:65-69`).
- The menu bar icon is `list.bullet.rectangle` with the count of today's scheduled items when above zero (`ZeigarnikScenes.swift:47-51`). Today and Upcoming lists today plus the next seven days, at most five items (`Sources/ZeigarnikKit/Model/MenubarSummary.swift:12-20`). A pinned row opens the window on the Pinned filter with that project selected; an attention row opens the window on that filter.

## Screen inventory

| Screen | Source | States |
| --- | --- | --- |
| List: project table | `Sources/ZeigarnikUI/List/ProjectTableView.swift` | first scan in progress, no projects in this view, populated, row selected, row with error icon, row with live dot, pinned rows, warn tags, column context menu, row context menu, README and Visibility columns hidden by checks, search active |
| List: Other bucket | `Sources/ZeigarnikUI/Window/OtherBucketView.swift` | "No work outside projects", populated with footer text |
| Sidebar | `Sources/ZeigarnikUI/Window/SidebarView.swift` | each filter selected, Open Now hidden, Open Now with "?", conditional Attention rows, folder groups |
| Banners | `Sources/ZeigarnikUI/Window/RootView.swift:76-96` | startup error, load error, owner data error, source problem with and without Open Settings, relinks, scan errors |
| Calendar: month grid | `Sources/ZeigarnikUI/Calendar/MonthView.swift` | empty month, populated (day totals, up to 2 scheduled chips, up to 3 project chips, "+N" or "Other ≈…", 1 note marker), today badge, selected day, days outside the month |
| Project inspector | `Sources/ZeigarnikUI/Inspector/ProjectInspector.swift` | populated facts, missing project banner, path copied, open error, spec section with evidence (done, pending, external, no evidence), disclosure open, drafts, scheduled items, notes, "No notes yet.", note error, editing a note, confirming delete, accepting a draft |
| Day inspector | `Sources/ZeigarnikUI/Inspector/DayInspector.swift` | "No recorded work" with "-", populated projects, scheduled section, notes section, project not selected error |
| Inspector placeholder | `RootView.swift:71` | "Select a project", "Select a day" |
| Go to Date sheet | `Sources/ZeigarnikUI/Sheets/GoToDateSheet.swift` | default (today) |
| Schedule sheet | `Sources/ZeigarnikUI/Sheets/ScheduleSheet.swift` | new with project picker ("Schedule · Select a Project"), new with locked project, edit ("Edit Schedule · …"), confirm delete, calendar warning, project required error, save error |
| Welcome | `Sources/ZeigarnikUI/Welcome/WelcomeView.swift` | no folders (Skip for Now), folders added (Start), vault set, calendar access not determined, denied, write-only, granted |
| Settings | `Sources/ZeigarnikUI/Settings/SettingsView.swift` | no folders banner, folders listed, vault none and set, calendar not determined, denied, write-only, granted with target picker, no terminal or editor installed, launch at login error, About links |
| Menu bar panel | `Sources/ZeigarnikUI/Menubar/MenubarView.swift` | nothing scheduled, upcoming items, pinned section, attention section, scanning, last scan time |
| Design Gallery (DEBUG) | `Sources/ZeigarnikUI/Theme/DesignGallery.swift` | light and dark columns |

## Files and regeneration

- Tokens: `Sources/ZeigarnikUI/Theme/Theme.swift`. Shared components: `Sources/ZeigarnikUI/Theme/Components.swift`. Note card variants: `Sources/ZeigarnikUI/Sheets/ScheduleSheet.swift`.
- Views: `Sources/ZeigarnikUI/{Window,List,Calendar,Inspector,Sheets,Menubar,Settings,Welcome,Support}/`. Composition root: `Sources/ZeigarnikUI/AppEnvironment.swift`. View state and actions: `Sources/ZeigarnikKit/Model/AppModel.swift`. Display strings: `Sources/ZeigarnikKit/Format/Format.swift`.
- App target: `App/ZeigarnikApp.swift` hands off to `ZeigarnikScenes`; the app icon is `App/Assets.xcassets/AppIcon.appiconset` with its source `docs/assets/app-icon.svg`. The asset catalog has no color sets.

Run locally (documented in README.md and CLAUDE.md; builds need the owner's approval, one at a time):

```bash
open Zeigarnik.xcodeproj   # choose the Zeigarnik scheme, then Run
```

```bash
xcodebuild -project Zeigarnik.xcodeproj -scheme Zeigarnik -configuration Release -derivedDataPath build build
open build/Build/Products/Release/Zeigarnik.app
```

For captures on a separate data set, CLAUDE.md documents a Debug build with its own `PRODUCT_BUNDLE_IDENTIFIER`, launched with `--home <absolute dir>` and `--settings-json '<AppSettings JSON>'`. DEBUG builds also accept `--gallery`, `--menubar-preview`, `--settings` (`Sources/ZeigarnikUI/ZeigarnikScenes.swift:64-79`), `--select <display name>` and `--day <yyyy-MM-dd>` (`Sources/ZeigarnikUI/Window/RootView.swift:45-53`). Fixtures must be synthetic (CLAUDE.md).

Design template (Level 1 since design 1.1.0). Tools live in `design/`: `package.json` pins `@open-pencil/cli`, `@open-pencil/core` and `@open-pencil/scene-graph` at exactly 0.16.0 (`bun.lock` committed, `design/node_modules/` and `design/.venv/` in `.gitignore`); `requirements.txt` pins `fonttools` for `font-outlines.py`. `tokens.mjs` reads this frontmatter and takes every token from the source line it cites (`path:line` plus a pattern that must match that line; light and dark both from the `color(light:dark:)` call); `components.mjs` draws the components from those tokens with copy from `DesignGallery.swift`; `font-outlines.py` extracts SF Pro Text glyph outlines from `/System/Library/Fonts` (macOS only), because OpenPencil cannot load the system font by name.

Commands, run from the repository root with Node 22 (tested with v22.23.0) and Bun; none of them builds the app:

```bash
cd design && bun install && cd ..
python3 -m venv design/.venv && design/.venv/bin/python -m pip install -r design/requirements.txt
node design/generate-template.mjs                          # overwrites design/template.fig (Cover, Tokens, Components)
node design/generate-template.mjs "$TMPDIR/template.fig"   # or write elsewhere
node design/verify-template.mjs                            # reopens design/template.fig from disk, exits non-zero on any mismatch
```

The generator uses `design/.venv/bin/python` when it exists, else `python3` (override with `PYTHON=`). The verifier checks the pinned package versions, page order, Cover values against this frontmatter with page links, one collection `Zeigarnik` with modes `Light` and `Dark`, every variable name, type and per-mode value against the line it cites, the frontmatter light and dark hex colors (including `chips`) against `Theme.swift`, every swatch binding and literal, every solid fill and stroke of every main component bound to a variable with the same color, every node opacity equal to 1 or an `Opacity /` token, glyph outlines on every component text, one Dark instance per main component whose bound paints resolve to the Dark values (OpenPencil 0.16.0 does not save `variableModes` on an instance, so the mode sits on the `Mode / Dark` lane around it), and the version label on every page after Cover. A token whose line moved fails until `design/tokens.mjs` points at the new line.

`design/template.fig` contents (Level 1): Cover; Tokens (collection `Zeigarnik`, modes `Light` and `Dark`, 64 variables: 23 colors with swatches per mode, literal, hex and `path:line`, then Opacity, Type, Radius, Spacing and Size groups); Components (20 main components in Light, each with a Dark instance: Tag neutral, warn and ok, ProjectChip for color indexes 0 to 5, ScheduledChip, NoteMarker, LiveDot, SectionHeader, KeyValueGrid, NoteCard scheduled with badge, plain and interactive hover, Sparkline, Banner warn and neutral). Pages after Cover carry the label `Zeigarnik · design <version> · product <version> · <page>` bound to `side`, `line` and `text`.

Target for later levels (unchanged): `design/template.fig` (OpenPencil) is to hold the screen states listed above in light and dark appearance, the color token collection with both modes, the shared components and the behavior rules. When a screen or token changes in code, update the template from new captures of the same states.

## Versioning

`design_version` versions this document and `design/template.fig` together; `product_version` is the app release they describe (project.yml `MARKETING_VERSION`). Bump major for navigation or layout changes, minor for new states, components or tokens, patch for corrections. A new app release updates `product_version`, `source_commit` and `updated`.

- 1.0.0 (2026-11-21, `017819a`): DESIGN.md and Level 0 template (Cover only).
- 1.1.0 (2026-11-22, `95ac6bf`): Level 1 template (Tokens and Components pages) with generator and verifier in `design/`. Minor bump: new tokens and components in the template; no rule or value in this file changed.
- 1.2.0 (2026-11-22): SpecBar drawn in three gallery states (9/11, 12/12, 0/0) with three new size and radius tokens. Code change decided by Ceair: `Theme.specTrack` is now `line` instead of `Color.gray.opacity(0.2)` (`Theme.swift:31`), so the track has a repository value in both appearances. Minor bump: new tokens and components. Not built yet; the visual change needs a Debug build to confirm.

## Anti-patterns

Each is backed by a code comment or an existing choice.

- System alerts or confirmation dialogs for deletes; confirmations stay inline (`ScheduleSheet.swift:103`).
- Hex colors in views instead of `Theme` tokens.
- `hashValue` for project colors; it is seeded per launch and would recolor projects (`Sources/ZeigarnikKit/List/ColorIndex.swift:1`).
- Putting `.badge` or `.help` outside `.tag` on a sidebar row; List selection then ignores the row (`SidebarView.swift:47`).
- Building a `DateFormatter` per table cell; it made sidebar selection visibly slow (`Format.swift:135`).
- Showing an empty list in place of a read error or a missing source.

## Known gaps

- **Brand**: not stated anywhere in the repository. Evidence points two ways: bundle prefix `com.ceaksan`, GitHub `ceaksan/zeigarnik`, About links to ceaksan.com and lab.ceaksan.com/zeigarnik, but the repository sits under the DNOMIA products folder. Left as `unknown`.
- **No captures**: Superseded 2026-11-22: there is no `design/` folder (it now holds the Level 1 template tools). Still true: no screenshots and no capture script. Rendered sizes of system controls (table row height, sidebar, toolbar, form rows) are not recorded here because they come from AppKit defaults and were not measured.
- **Fixed accent**: `Theme.accent` is a fixed `#0a84ff` and does not follow the user's system accent color, while `.borderedProminent` buttons use the system tint. With a non-blue system accent the two blues would differ. Not verified visually.
- **Unused or gallery-only tokens**: `Theme.rowPadding` is not referenced by any view; `Theme.bg` is used only by the Design Gallery.
- **Inline fonts outside Theme**: 14 pt semibold (sheet headings, welcome steps), 22 pt semibold (welcome title), 12 pt (day numbers).
- **Delete copy differs**: cards ask "Delete?", the schedule sheet asks "Are you sure?".
- **Accessibility**: labels exist for LiveDot, SpecBar, Copy Path and Remove folder only. The Sparkline, chips and stars have no accessibility labels. Increased contrast and reduced transparency are not handled in code; not tested.
- **Design spec and mockup**: `docs/superpowers/specs/2026-11-18-zeigarnik-design.md` and `2026-11-18-zeigarnik-mockup.html` exist locally but are gitignored, so they are not linked here and were not used as a source of values.
- **Localization**: UI strings are English only; only dates, times and decimals are localized.
- **Template Level 1** (added 2026-11-22):
  - `◷` (ScheduledChip, scheduled card date) and `✎` (NoteMarker) are not in SF Pro; macOS draws them from a fallback font that was not identified, so the template leaves them blank. SF Symbols (`exclamationmark.triangle`, `pencil`, `trash`) are color-bound placeholder squares (accepted for Level 1 by Ceair 2026-11-22).
  - Not drawn: SpecBar (its track `specTrack` is `Color.gray.opacity(0.2)`, a system color with no value in the repository), the CardActions confirm state (system `.small` buttons and `.borderedProminent` tint), Banner ok (no view uses it; the neutral banner copy uses a sample project name), draft cards and other view-local variants in `Sheets/` and `Calendar/`, and the inline 14, 22 and 12 pt fonts. Resolved 2026-11-22 for SpecBar: `specTrack` now equals `line` and SpecBar is drawn (design 1.2.0); the rest of this line still holds.
  - Widths follow the Design Gallery column (440 pt minus 14 pt inspector padding on both sides, `DesignGallery.swift:12`); text uses SF Pro outlines from `SFNS.ttf` (optical size 17), which differ between macOS versions. Line heights are approximated as 1.2 x size; layout is reproduced from padding and stack spacing, not measured from a running app.
  - Level 2 (screens) needs captures from a Debug build (CLAUDE.md documents the separate data set flags); not attempted, needs Ceair's approval.
  - Added 2026-11-22: SpecBar is still not drawn after the Platform (system) work in the other templates. Its track is `Color.gray.opacity(0.2)` (Theme.swift:31), which is `NSColor.systemGray` on macOS. The Apple HIG Color page (https://developer.apple.com/design/human-interface-guidelines/color, fetched 2026-11-22) gives gray values only in its iOS, iPadOS system gray colors table (`systemGray` R-142,G-142,B-147 in both default appearances, with the note that SwiftUI `gray` is its equivalent); its System colors table has no gray, and the macOS dynamic colors are listed without values. Using the iOS value for macOS needs Ceair's decision. No other drawn or missing component here uses a system color or text style (the remaining gaps are system controls), so no `Platform (system)` collection was added and `design_version` stays 1.1.0. Resolved 2026-11-22: Ceair declined using the iOS systemGray value and chose `specTrack = line` in code instead; SpecBar is drawn since design 1.2.0.
