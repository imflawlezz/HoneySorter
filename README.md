# HoneySorter 🍯

**HoneySorter** is a macOS app designed to help you organize a folder full of images into **ordered albums** and apply a **consistent batch rename** (or copy) in a single pass. The result is a predictable naming scheme like `albumIndex_photoIndex.ext`, with options for **separate folders per album** and even a **custom output location**. If you prefer to keep your originals untouched, the **copy mode** makes that easy.

## Use case

Imagine downloading an artwork archive from your favorite artist. Everything is there—but it’s just a **massive pile of files**, ungrouped and overwhelming. The only good news: the files are still in the **correct order**.

That’s exactly where HoneySorter comes in. It lets you take that ordered list and **split it into albums** by defining ranges. You can optionally place each album into its own folder and even **output everything to a different location**.

If you enable **Copy to Separate Location** and use **Copy All**, your original files remain exactly as they were. If that’s not a concern, you can simply rename everything in place.

There’s no database involved. The app works directly with the folders you grant access to, fully aligned with macOS sandboxing.

## How it works

1. **Load a folder**
   The app scans the selected directory for common image formats (JPEG, PNG, HEIC, TIFF, WebP, GIF, and others) and sorts them by filename to ensure a stable, predictable grid.

2. **Define albums**
   Albums are created as **continuous ranges** within that order. You click the **first** image in a range, then the **last**, and HoneySorter automatically includes everything in between. Each range becomes a new album with the next available index. Overlapping ranges are not allowed.

3. **Naming setup**
   In the sidebar, you configure how filenames should be generated. This includes the separator between album and photo indices, optional zero-padding, the starting album index, and whether to create subfolders per album (with an optional prefix).

4. **Apply changes**
   Use **Rename All** to rename files in place, or **Copy All** if you’re working in duplicate mode. The app can also generate a **revert manifest**, allowing you to undo the last batch operation using the **Revert** option in the toolbar (when available).

At the bottom, the **status bar** guides you through the current step (selecting first image, selecting last image, or ready to proceed). The **toolbar** shows the active folder and lets you switch it quickly. For large collections, controls like **thumbnail size** and **unassigned-only filtering** help keep things manageable.

## Features

* **Album ranges**
  Albums are defined by selecting a start and end image. If you change the starting index or remove albums, numbering updates automatically.

* **Batch renaming**
  Files follow the pattern `albumIndex + separator + photoIndex + extension`, with a live preview available in the sidebar.

* **Optional album subfolders**
  You can store each album in its own folder. Folder names can be simple numbers (`1`, `2`, …) or include a custom prefix (e.g. `MyTrip_1`).

* **Copy mode**
  Instead of renaming in place, you can copy renamed files to another location. If no destination is selected, a `Sorted` subfolder is used by default.

* **Single-file rename**
  Right-click any thumbnail and choose **Rename…** to update just one file (the extension is preserved).

* **Undo support**
  After batch renaming, the **Revert** action restores previous filenames if an undo manifest is available.

* **Grid customization**
  Adjust thumbnail size or filter the grid to show only images that haven’t yet been assigned to an album.

* **Folder monitoring**
  The app can detect changes in the underlying folder (such as file count updates) and refresh accordingly.

## Operational instructions

### Open a project folder

* Use the **folder control** in the toolbar (path and folder icon), or click **Select Folder** in the empty state.
* Press **⌘O** to open the folder picker directly.

### Create albums

1. Click an image to mark the **start** of an album (it must not already belong to one).
2. Click another image to mark the **end** of that album. The full range between them is included.
3. Repeat the process for additional albums.
   If needed, adjust **Start Album Index** to begin numbering from a different value.

### Naming options (sidebar)

* **Separator**
  Defines the character between album and photo indices.

* **Zero padding**
  Ensures consistent filename sorting (e.g. `01_01` instead of `1_1`).

* **Create Album Folders**
  Enables per-album subfolders.
  **Folder prefix** is optional text placed directly before the album number.

* **Copy to Separate Location**
  When enabled, **Copy All** writes duplicates instead of renaming in place.
  You can choose a custom **Output** folder or use the default `Sorted` location.

### Apply changes

* **Rename All** / **Copy All**
  Both actions show a confirmation summary. Wait for the process to complete before closing the app or modifying files externally.

* **Revert**
  Available after a rename if a manifest was created. Prompts for confirmation before restoring previous names.

### Clear and inspect

* **Clear All Albums**
  Removes all album assignments (files remain unchanged until you apply a rename or copy).

* **Unassigned only**
  Filters the grid to display only images that are not part of any album.

* **Rename… (context menu)**
  Allows a one-off filename change for a selected image.

## Requirements

* **macOS 14+** (based on the app’s deployment target in Xcode).
  **Tested on macOS 26.0 and newer.**
* Sandboxed environment with **user-selected** read/write access to folders.

## Build and run

```bash
cd HoneySorter
xcodebuild -scheme HoneySorter -configuration Debug build
```

Alternatively, open `HoneySorter.xcodeproj` in Xcode and run the **HoneySorter** scheme to launch the app and debug interactively.