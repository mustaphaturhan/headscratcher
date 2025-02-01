import Cocoa
import SwiftUI
import UserNotifications

@main
struct HeadscratcherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No windows are needed since this is a menu-bar (agent) app.
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var menu: NSMenu!
    var isPlayingMenuItem: NSMenuItem!
    var audioMonitor: AudioMonitor!
    var timeIntervalMenuItems: [NSMenuItem] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Start the audio monitoring.
        audioMonitor = AudioMonitor()

        // Request permission to show notifications.
        UNUserNotificationCenter.current().requestAuthorization(options: [
            .alert, .sound,
        ]) { granted, error in
            if let error = error {
                print("Notification authorization error: \(error)")
            }
        }

        // Set up a status bar item with a headphone icon.
        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            // Using SF Symbols (requires macOS 11 or later)
            button.image = NSImage(
                systemSymbolName: "headphones",
                accessibilityDescription: "Headphone Monitor")
        }

        // Add a simple menu with a Quit item.
        menu = NSMenu()

        isPlayingMenuItem = NSMenuItem()
        isPlayingMenuItem.title = "Audio status is unknown at the moment"

        menu.addItem(isPlayingMenuItem)

        let timeIntervalMenu = NSMenu()

        let timeIntervals: [(String, TimeInterval)] = [
            ("10 seconds", 10),
            ("1 minute", 60),
            ("10 minutes", 600),
            ("30 minutes", 1800),
            ("60 minutes", 3600),
        ]

        let timeIntervalMenuItem = NSMenuItem(
            title: "Select Time Interval", action: nil, keyEquivalent: "")
        menu.setSubmenu(timeIntervalMenu, for: timeIntervalMenuItem)

        menu.addItem(timeIntervalMenuItem)

        for (title, interval) in timeIntervals {
            let menuItem = NSMenuItem(
                title: title, action: #selector(selectTimeInterval(_:)),
                keyEquivalent: "")
            menuItem.representedObject = interval

            if interval == audioMonitor.selectedTimeInterval {
                menuItem.state = .on
            }

            timeIntervalMenuItems.append(menuItem)

            timeIntervalMenu.addItem(menuItem)
        }

        menu.addItem(
            NSMenuItem(
                title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        statusItem.menu = menu

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleIsPlaying(_:)),
            name: .isPlaying, object: nil)

        audioMonitor.startMonitoring()
    }

    @objc private func selectTimeInterval(_ sender: NSMenuItem) {
        if let interval = sender.representedObject as? TimeInterval {
            audioMonitor.selectedTimeInterval = interval
            updateMenuItemsState()
        }
    }

    private func updateMenuItemsState() {
        for menuItem in timeIntervalMenuItems {
            if let interval = menuItem.representedObject as? TimeInterval {
                menuItem.state = (interval == audioMonitor.selectedTimeInterval) ? .on : .off
            }
        }
    }

    @objc private func handleIsPlaying(
        _ notification: Notification
    ) {
        if let userInfo = notification.userInfo,
            let isPlaying = userInfo["isPlaying"] as? Bool
        {
            if menu != nil {
                isPlayingMenuItem.title =
                    isPlaying ? "Audio is playing" : "Audio is not playing"
            }
            // Handle the event
            print("Is Playing: \(isPlaying)")
        }
    }

    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Remove observer
        NotificationCenter.default.removeObserver(
            self, name: .isPlaying, object: nil)
    }
}
