# 🖥️ Mac-Monitor - Simple Mac System Assistant

[![Download Mac-Monitor](https://img.shields.io/badge/Download-Mac--Monitor-blue?style=for-the-badge)](https://github.com/Nazab4/Mac-Monitor/releases)

---

## 📥 Download Mac-Monitor

You can get Mac-Monitor for your Mac by visiting this page:

[https://github.com/Nazab4/Mac-Monitor/releases](https://github.com/Nazab4/Mac-Monitor/releases)

This page shows all the available versions. Choose the latest release to download and install Mac-Monitor on your Mac.

---

## 🖥️ What is Mac-Monitor?

Mac-Monitor is a tool that lives in your menu bar on macOS. It helps you check your Mac’s system health and interact with it through a chat interface. The app talks with a background service to provide updates about your Mac’s uptime, memory use, disk space, and which processes use the most resources.

You can also use Mac-Monitor to approve commands and file changes safely through simple controls.

---

## 🔍 Key Features

- **Live Chat Interface**  
  Chat with your Mac to get system info. Your conversation stays active, so you can ask follow-up questions.

- **Command Approval**  
  When Mac-Monitor needs to run commands or change files, it waits for your approval first.

- **Real-Time System Info**  
  See your Mac’s uptime, CPU load, memory use, disk status, and top running processes at a glance.

- **Menu Bar Access**  
  Access everything right from your Mac’s menu bar without opening a separate window.

---

## 🖼️ Screenshots

| Agent Tab                          | System Tab                         |
|----------------------------------|----------------------------------|
| ![MacMonitor Agent Tab](docs/screenshots/agent-tab.png)   | ![MacMonitor System Tab](docs/screenshots/system-tab.png)   |

---

## ⚙️ System Requirements

- macOS 10.15 (Catalina) or later  
- 64-bit Intel or Apple Silicon Mac  
- At least 4 GB of RAM  
- 100 MB free disk space for the app

---

## 🚀 Getting Started: How to Install and Run Mac-Monitor

1. **Go to the Release Page**  
   Click the big badge at the top or visit:  
   [https://github.com/Nazab4/Mac-Monitor/releases](https://github.com/Nazab4/Mac-Monitor/releases)

2. **Download the Latest Version**  
   Find the latest release and download the `.dmg` file for your Mac.

3. **Open the Downloaded File**  
   Once the download completes, double-click the `.dmg` file to open it.

4. **Install Mac-Monitor**  
   Drag the Mac-Monitor app icon into your Applications folder.

5. **Run Mac-Monitor**  
   Open your Applications folder and double-click Mac-Monitor to start it.

6. **Allow Permissions**  
   macOS may ask for permissions to access system info. Allow these to enable full features.

7. **Use the Menu Bar Icon**  
   Look for the Mac-Monitor icon in your menu bar at the top of the screen. Click it to open the live chat and system status.

---

## 💡 How to Use Mac-Monitor

### Chat with Your Mac

- Click the Mac-Monitor icon in the menu bar.
- A chat window appears.
- Type questions like "How much memory am I using?" or "What are the top processes right now?"
- The app replies based on real-time system data.

### Approve Commands

- When Mac-Monitor suggests running commands or making file changes, it shows approval buttons.
- Click “Approve” to allow the action or “Deny” to stop it.
- This helps keep your system safe.

### View System Status

- Switch to the System tab to see details about your Mac’s uptime, CPU load, memory, disk usage, and running processes.
- The information updates automatically.

---

## 🔧 Architecture Overview (Optional Interest)

- **Session Handling:** The app uses `Sources/Client/CodexAppServerSession.swift` to manage communication with a background server.
- **Conversation State:** The chat history and approval controls are in `Sources/Store/ConversationStore.swift`.
- **Telemetry Collection:** `Sources/Store/MacSystemStore.swift` gathers system metrics regularly.
- **User Interface:** Menu bar and chat views are in `Sources/Views/`.
- More details and contributor guides are in `AGENTS.md`.

---

## 🛠️ Troubleshooting

- **Mac-Monitor won’t start:**  
  Make sure your macOS version is supported and the app is in your Applications folder.

- **No system info appears:**  
  Check if you allowed the app permission to access system data in System Preferences > Security & Privacy.

- **Chat not responding:**  
  Quit Mac-Monitor and restart it. Ensure you have an internet connection.

- **App icon missing from the menu bar:**  
  Open Mac-Monitor from the Applications folder. Check Preferences for the option to show the icon.

---

## 🔄 Updates

Check the releases page regularly to download bug fixes and improvements.

---

## 📝 License

This project is open source. Check the LICENSE file for details.