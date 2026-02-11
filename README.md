# NotionSketch

NotionSketch is a powerful iPadOS application that bridges the gap between freeform sketching and structured knowledge management in Notion. Built with SwiftUI and PencilKit, it allows you to create expansive canvas drawings that automatically sync to your Notion workspace.

## ✨ Features

- **Expansive Canvas**: Draw freely on a large digital canvas using the high-performance PencilKit engine.
- **Bi-Directional Sync**:
  - **Drawings**: Automatically uploaded as images to Notion page blocks.
  - **OCR**: Handwritten text is recognized on-device and synced to a text property in Notion.
  - **Titles**: Rename a sketch in the app or in Notion, and changes sync both ways.
  - **Connected Pages**: Link your sketches to other Notion pages (e.g., Projects, Tasks) directly from the app.
- **Deep Linking**: Open sketches directly from Notion using the `Open in App` link (`notionsketch://`).
- **Offline First**: fully functional offline. Changes are queued and synced automatically when back online.
- **Spotlight Search**: Find sketches by title, date, or connected page names.

## 🚀 Getting Started

### 1. Notion Setup

To use NotionSketch, you need a Notion database to store your sketches.

1.  **Create a New Database** in Notion (or use an existing one).
2.  Add the following properties (names must match exactly or be configured in code):
    *   **Name**: The default title property.
    *   **OCR** (`Text` or `Rich Text`): Stores the recognized text from your drawing.
    *   **Open in App** (`URL`): Stores the deep link to reopen the sketch on iPad.
    *   **Connected Pages** (`Relation`): A relation property pointing to another database (e.g., your "Wiki" or "Projects" database). This allows you to link sketches to other contexts.
3.  **Create an Internal Integration**:
    *   Go to [Notion My Integrations](https://www.notion.so/my-integrations).
    *   Click "New integration".
    *   Name it "NotionSketch" and select the relevant workspace.
    *   Copy the **Internal Integration Secret** (starts with `secret_`).
4.  **Connect Integration to Database**:
    *   Go to your Notion database page.
    *   Click the `...` menu (top right) -> `Connect to` -> Search for "NotionSketch" and select it.

### 2. App Installation

1.  Clone this repository.
2.  Open `NotionSketch.xcodeproj` in Xcode.
3.  Build and run on an iPad Simulator or Device.

You can also look into something like [Sidestore](https://sidestore.io) to have it stay without having to rebuild it

### 3. App Configuration

1.  Launch NotionSketch.
2.  Tap the **Settings** (gear icon) in the sidebar.
3.  **API Token**: Paste your Internal Integration Secret.
4.  **Database ID**: Paste the ID of your sketches database (or just paste the full URL of the database page; the app will extract the ID).
5.  (Optional) **Short.io**: Configure Short.io API keys if you want shorter, cleaner deep links that redirect reliably on iOS.

## 🛠️ Usage

- **Create**: Tap `+` to start a new sketch. A corresponding page is created in Notion immediately.
- **Draw**: Use the Apple Pencil or finger. Drawing strokes are saved locally and synced to Notion periodically (debounced) or on close.
- **Link**: Tap the "Link" icon to connect the sketch to other Notion pages. You can search for pages in your connected database.
- **Sync**: Status is shown in the top right. "Synced ✓" means your changes are safe in Notion.

## ⚠️ Requirements

- iOS/iPadOS 17.0+
- Xcode 15.0+
- A Notion Account

## 📄 License

This project is licensed under the MIT License.
