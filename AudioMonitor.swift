import CoreAudio
import Foundation
import UserNotifications

extension Notification.Name {
    static let isPlaying = Notification.Name("isPlaying")
}

extension UInt32 {
    init(fourCharCode: String) {
        precondition(fourCharCode.count == 4, "Must be exactly 4 characters")
        self = fourCharCode.utf8.reduce(0) { ($0 << 8) + UInt32($1) }
    }
}

let kAudioDevicePropertyIsRunningSomewhere: AudioObjectPropertySelector =
    AudioObjectPropertySelector(UInt32(fourCharCode: "isrs"))

// MARK: - AudioMonitor Class

class AudioMonitor: ObservableObject {
    // Timer fires every 5 seconds to check the device state.
    var timer: Timer?
    // If conditions (headphone connected & no audio) are met, record when they began.
    var conditionMetStartTime: Date?

    private var audioStartTime: Date?
    private var minimumPlayingDuration: TimeInterval = 15  // 15 seconds minimum
    var audioPlayedBefore = false
    @Published var selectedTimeInterval: TimeInterval = 600  // Default to 10 minutes

    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) {
            [weak self] _ in
            self?.checkAudioStatus()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
    }

    func checkAudioStatus() {
        let defaultDeviceID = getDefaultOutputDevice()
        guard defaultDeviceID != kAudioObjectUnknown else {
            print("No default audio device found.")
            resetTimer()
            return
        }

        // Check if the default device appears to be a headphone device.
        if isHeadphoneDevice(deviceID: defaultDeviceID) {
            print("Is audio played before: \(audioPlayedBefore)")
            // Query if the device is active (i.e. audio is playing)
            let playing = isAudioPlaying(deviceID: defaultDeviceID)
            if !playing {
                if audioPlayedBefore {
                    // If audio is not playing, start (or continue) the countdown.
                    if conditionMetStartTime == nil {
                        conditionMetStartTime = Date()
                    } else {
                        let elapsed = Date().timeIntervalSince(
                            conditionMetStartTime!)
                        print(
                            "Elapsed time \(elapsed), selected time interval is \(selectedTimeInterval)"
                        )
                        if elapsed >= selectedTimeInterval {
                            triggerNotification()
                            // Reset so we don’t keep notifying every time the timer fires.
                            conditionMetStartTime = nil
                            // Remove the audio play status
                            audioPlayedBefore = false
                        }
                    }
                }
            } else {
                if audioStartTime == nil {
                    audioStartTime = Date()
                }

                if let startTime = audioStartTime {
                    let playingDuration = Date().timeIntervalSince(startTime)
                    if playingDuration >= minimumPlayingDuration {
                        audioPlayedBefore = true
                    }
                }
                // Audio has resumed; reset the countdown.
                resetTimer()
            }
        } else {
            // Headphones are not connected; reset any countdown.
            resetTimer()
        }
    }

    func resetTimer() {
        conditionMetStartTime = nil
    }

    func triggerNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Hey, you forget something!"
        content.body =
            "Your headphones are connected, but no audio has been playing. Do something."
        content.sound = UNNotificationSound.default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error displaying notification: \(error)")
            }
        }
    }

    // MARK: - Core Audio Helper Functions

    /// Returns the current default output device.
    func getDefaultOutputDevice() -> AudioDeviceID {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID)
        if status != noErr {
            print("Error getting default output device: \(status)")
            return kAudioObjectUnknown
        }
        return deviceID
    }

    /// Checks if audio is currently playing on the given device.
    func isAudioPlaying(deviceID: AudioDeviceID) -> Bool {
        var isRunning: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &isRunning)

        if status != noErr {
            print("Error querying audio activity: \(status)")
            return false
        }

        address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        address.mScope = kAudioObjectPropertyScopeGlobal
        address.mElement = kAudioObjectPropertyElementMain

        NotificationCenter.default.post(
            name: .isPlaying, object: nil,
            userInfo: ["isPlaying": isRunning != 0])

        return isRunning != 0
    }

    func isHeadphoneDevice(deviceID: AudioDeviceID) -> Bool {
        // Check transport type
        var transportType: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &transportType)

        if status == noErr {
            // Check if device is Bluetooth or AirPlay
            if transportType == kAudioDeviceTransportTypeBluetooth
                || transportType == kAudioDeviceTransportTypeAirPlay
            {
                print("Device is bluetooth or airplay type")
                return true
            }
        }

        // Check device type
        var deviceType: [UInt32] = []
        size = UInt32(MemoryLayout<UInt32>.size * 2)
        address.mSelector = kAudioDevicePropertyStreams

        let typeStatus = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &deviceType)

        if typeStatus == noErr {
            // Check if device is headphone type
            if deviceType.contains(where: {
                $0 == kAudioStreamTerminalTypeHeadphones
            }) {
                print("Device is headphone type")
                return true
            }
        }

        // Fall back to name matching if needed
        let name = getDeviceName(deviceID: deviceID)
        print("Device Name: \(name)")

        let audioKeywords = [
            // Generic terms
            "headphone", "airpod", "bluetooth", "wireless", "buds",
            "pods", "earphone",
            // Popular brands
            "sony", "bose", "beats", "jabra", "samsung", "galaxy", "jbl",
            "sennheiser",
            "audio-technica", "skullcandy", "plantronics", "poly", "marshall",
            "jaybird",
            // Common model keywords
            "wh-", "wf-", "quietcomfort", "momentum", "freedompro", "elite",
            "studio",
        ].map { $0.lowercased() }

        return audioKeywords.contains { name.lowercased().contains($0) }
    }

    private func getDeviceName(deviceID: AudioDeviceID) -> String {
        var deviceName: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString?>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &deviceName)

        return status == noErr ? (deviceName as String) : "Unknown Device"
    }
}
