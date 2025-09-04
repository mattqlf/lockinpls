import SwiftUI
import CoreGraphics
import UserNotifications
import Foundation
import AppKit
import ScreenCaptureKit
import AVFoundation
import UniformTypeIdentifiers
import ApplicationServices

class AudioManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    var audioPlayer: AVAudioPlayer?
    var onFinish: (() -> Void)?
    
    func play(data: Data, onFinish: @escaping () -> Void) {
        // print("DEBUG: AudioManager - Starting audio playback, data size: \(data.count) bytes")
        self.onFinish = onFinish
        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.play()
            isPlaying = true
            // print("DEBUG: AudioManager - Audio started successfully, duration: \(audioPlayer?.duration ?? 0) seconds")
        } catch {
            // print("DEBUG: AudioManager - Failed to play audio: \(error)")
            onFinish()
        }
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        // print("DEBUG: AudioManager - Audio finished playing, success: \(flag)")
        isPlaying = false
        onFinish?()
    }
}

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    
    private override init() {
        super.init()
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, 
                               willPresent notification: UNNotification, 
                               withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // print("DEBUG: NotificationDelegate - Notification received while app is in foreground")
        // Show notification even when app is in foreground
        completionHandler([.alert, .sound, .badge])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, 
                               didReceive response: UNNotificationResponse, 
                               withCompletionHandler completionHandler: @escaping () -> Void) {
        // print("DEBUG: NotificationDelegate - User interacted with notification: \(response.actionIdentifier)")
        completionHandler()
    }
}

struct ContentView: View {
    @State var timerMinutes = 25
    @State var screenshotInterval = 30
    @State var workInstruction = ""
    @State var aiPersonality = "Be encouraging but firm."
    @State var isRunning = false
    @State var timeRemaining: TimeInterval = 0
    @State var focusedCount = 0
    @State var distractedCount = 0
    @State var isDarkMode = false
    @State var enableTTS = true
    
    @StateObject var audioManager = AudioManager()
    @State var overlayWindow: NSWindow?
    @State var localMonitor: Any?
    @State var globalMonitor: Any?
    @State var restingImagePath: String = ""
    @State var talkingImagePath: String = ""
    
    private var defaultRestingImagePath: String {
        Bundle.main.path(forResource: "asuka-resting", ofType: "png") ?? ""
    }
    
    private var defaultTalkingImagePath: String {
        Bundle.main.path(forResource: "asuka-talking", ofType: "png") ?? ""
    }
    
    private var isUsingDefaultRestingImage: Bool {
        restingImagePath == defaultRestingImagePath
    }
    
    private var isUsingDefaultTalkingImage: Bool {
        talkingImagePath == defaultTalkingImagePath
    }
    
    private func restingImageDisplayName() -> String {
        if isUsingDefaultRestingImage {
            return "Default"
        } else if restingImagePath.isEmpty {
            return "None"
        } else {
            return URL(fileURLWithPath: restingImagePath).lastPathComponent
        }
    }
    
    private func talkingImageDisplayName() -> String {
        if isUsingDefaultTalkingImage {
            return "Default"
        } else if talkingImagePath.isEmpty {
            return "None"
        } else {
            return URL(fileURLWithPath: talkingImagePath).lastPathComponent
        }
    }
    @State var enableVisualAssistant = true
    @State var toggleShortcutModifiers: NSEvent.ModifierFlags = [.command, .option]
    @State var toggleShortcutKey: UInt16 = 9 // V key
    @State var isRecordingShortcut = false
    @State var recordingTimer: Timer?
    @State var shortcutJustRecorded = false
    @State var selectedVoiceId = "CwhRBWXzGAHq8TQ4Fs17" // Default to Man 1
    
    let voiceOptions = [
        ("Man 1", "CwhRBWXzGAHq8TQ4Fs17"),
        ("Woman 1", "4NejU5DwQjevnR6mh3mb"), 
        ("Man 2", "UgBBYS2sOqTuMpoF3BR0"),
        ("Woman 2", "TbMNBJ27fH2U0VgpSNko")
    ]
    
    @State var startTime = Date()
    @State var endTime = Date()
    @State var screenshotTimer: Timer?
    @State var countdownTimer: Timer?
    
    enum Field: Hashable {
        case timerMinutes, screenshotInterval, workInstruction, aiPersonality
    }
    @FocusState private var focusedField: Field?
    
    // TODO: Remove hardcoded API keys before production - use environment variables instead
    let openAIAPIKey = "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"
    let elevenLabsAPIKey = "sk_1a20e48d8b789886092e640337b1fde79ccee632a3f15051"
    
    var body: some View {
        ZStack {
            // Glass background gradient
            LinearGradient(
                colors: isDarkMode 
                    ? [Color.purple.opacity(0.3), Color.blue.opacity(0.4), Color.indigo.opacity(0.5)]
                    : [Color.cyan.opacity(0.2), Color.blue.opacity(0.3), Color.purple.opacity(0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Background blur effect
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    headerView
                    
                    settingsCard
                    
                    if isRunning {
                        progressCard
                    }
                    
                    actionSection
                    
                    if openAIAPIKey.isEmpty || elevenLabsAPIKey.isEmpty {
                        warningCard
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
        }
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .frame(minWidth: 500, minHeight: 650)
        .task {
            // Only request accessibility permission on app start for keyboard shortcuts
            // Other permissions will be requested when user starts a session
            await requestAccessibilityPermission()
        }
        .onAppear {
            // Set default images if not already set
            if restingImagePath.isEmpty {
                restingImagePath = defaultRestingImagePath
            }
            if talkingImagePath.isEmpty {
                talkingImagePath = defaultTalkingImagePath
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                focusedField = .workInstruction
            }
        }
        .onDisappear {
            if let monitor = localMonitor {
                NSEvent.removeMonitor(monitor)
                localMonitor = nil
            }
            if let monitor = globalMonitor {
                NSEvent.removeMonitor(monitor)
                globalMonitor = nil
            }
        }
    }
    
    var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("LockinPls")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: isDarkMode 
                                ? [Color.white, Color.white.opacity(0.8)]
                                : [Color.primary, Color.primary.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text("AI-powered focus tracker")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(isDarkMode ? .white.opacity(0.7) : .secondary)
            }
            
            Spacer()
            
            Button(action: { 
                withAnimation(.easeInOut(duration: 0.3)) {
                    isDarkMode.toggle()
                }
            }) {
                ZStack {
                    Circle()
                        .fill(.regularMaterial)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: isDarkMode 
                                            ? [Color.white.opacity(0.2), Color.white.opacity(0.05)]
                                            : [Color.white.opacity(0.8), Color.white.opacity(0.3)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    
                    Image(systemName: isDarkMode ? "sun.max.fill" : "moon.fill")
                        .font(.title3)
                        .foregroundColor(isDarkMode ? .yellow : .indigo)
                }
            }
            .buttonStyle(.plain)
            .help("Toggle theme")
        }
        .padding(.bottom, 8)
    }
    
    var settingsCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Session Settings")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(isDarkMode ? .white : .primary)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                settingItem("Timer", value: $timerMinutes, field: .timerMinutes, suffix: "min")
                settingItem("Check Interval", value: $screenshotInterval, field: .screenshotInterval, suffix: "sec")
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Work Task")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(isDarkMode ? .white.opacity(0.8) : .secondary)
                
                TextField("What are you working on?", text: $workInstruction)
                    .textFieldStyle(GlassTextFieldStyle(isDarkMode: isDarkMode))
                    .focused($focusedField, equals: .workInstruction)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("AI Personality")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(isDarkMode ? .white.opacity(0.8) : .secondary)
                
                TextField("How should AI behave?", text: $aiPersonality)
                    .textFieldStyle(GlassTextFieldStyle(isDarkMode: isDarkMode))
                    .focused($focusedField, equals: .aiPersonality)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Voice Reminders")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(isDarkMode ? .white.opacity(0.8) : .secondary)
                    
                    Spacer()
                    
                    Toggle("", isOn: $enableTTS)
                        .toggleStyle(SwitchToggleStyle(tint: .blue))
                }
                
                if enableTTS {
                    HStack {
                        Text("Voice")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.gray)
                        
                        Spacer()
                        
                        Menu {
                            ForEach(voiceOptions, id: \.1) { name, voiceId in
                                Button(name) {
                                    selectedVoiceId = voiceId
                                    // print("DEBUG: Selected voice: \(name) (\(voiceId))")
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(voiceOptions.first(where: { $0.1 == selectedVoiceId })?.0 ?? "Unknown")
                                    .font(.caption)
                                    .foregroundColor(isDarkMode ? .white : .primary)
                                
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                    .fill(Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Visual Assistant")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(isDarkMode ? .white.opacity(0.8) : .secondary)
                    
                    Spacer()
                    
                    Toggle("", isOn: $enableVisualAssistant)
                        .toggleStyle(SwitchToggleStyle(tint: .blue))
                }
                
                if enableVisualAssistant {
                    VStack(alignment: .leading, spacing: 10) {
                        // Status and shortcut in one row
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                if !restingImagePath.isEmpty && !talkingImagePath.isEmpty {
                                    Label("Images loaded", systemImage: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                } else {
                                    Label("Images required", systemImage: "exclamationmark.triangle.fill")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                                
                                Text("Toggle: \(shortcutDisplayString())")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                isRecordingShortcut = true
                                // print("DEBUG: Started recording shortcut")
                                
                                // Cancel any existing timer
                                recordingTimer?.invalidate()
                                
                                // Set up new timer
                                recordingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
                                    if isRecordingShortcut {
                                        isRecordingShortcut = false
                                        // print("DEBUG: Shortcut recording timed out")
                                    }
                                    recordingTimer = nil
                                }
                            }) {
                                Image(systemName: "pencil")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .buttonStyle(.borderless)
                            .help("Click to change shortcut")
                        }
                        
                        // Shortcut conflict warning
                        if let conflict = hasShortcutConflict() {
                            Label("May conflict with: \(conflict)", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(.yellow)
                        }
                        
                        // Shortcut recording state
                        if isRecordingShortcut {
                            Text("Press your desired shortcut keys...")
                                .font(.caption)
                                .foregroundColor(.orange)
                                .italic()
                        }
                        
                        Divider()
                        
                        // Image selection
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Images")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.gray)
                            
                            Text("Recommended: \(Int(NSScreen.main?.frame.width ?? 1920)/4)×\(Int(NSScreen.main?.frame.height ?? 1080)/2)px")
                                .font(.caption)
                                .foregroundColor(.gray.opacity(0.8))
                            
                            VStack(spacing: 12) {
                                HStack(spacing: 12) {
                                    // Resting image button
                                    VStack(spacing: 4) {
                                        Button(action: {
                                            // print("DEBUG: Opening file picker for resting image")
                                            let panel = NSOpenPanel()
                                            panel.allowedContentTypes = [UTType.png]
                                            if panel.runModal() == .OK {
                                                let newPath = panel.url?.path ?? ""
                                                // print("DEBUG: Selected resting image: \(newPath)")
                                                restingImagePath = newPath
                                            } else {
                                                // print("DEBUG: Resting image selection cancelled")
                                            }
                                        }) {
                                            HStack(spacing: 6) {
                                                Image(systemName: !restingImagePath.isEmpty ? "checkmark.circle.fill" : "photo.badge.plus")
                                                    .font(.caption)
                                                    .foregroundColor(!restingImagePath.isEmpty ? .green : .blue)
                                                
                                                Text("Resting")
                                                    .font(.caption)
                                                    .fontWeight(.medium)
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(.regularMaterial)
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 8)
                                                            .stroke(
                                                                LinearGradient(
                                                                    colors: isDarkMode 
                                                                        ? [Color.white.opacity(0.2), Color.white.opacity(0.05)]
                                                                        : [Color.white.opacity(0.8), Color.white.opacity(0.3)],
                                                                    startPoint: .topLeading,
                                                                    endPoint: .bottomTrailing
                                                                ),
                                                                lineWidth: 1
                                                            )
                                                    )
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        
                                        Text(restingImageDisplayName())
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                
                                    // Talking image button  
                                    VStack(spacing: 4) {
                                        Button(action: {
                                            // print("DEBUG: Opening file picker for talking image")
                                            let panel = NSOpenPanel()
                                            panel.allowedContentTypes = [UTType.png]
                                            if panel.runModal() == .OK {
                                                let newPath = panel.url?.path ?? ""
                                                // print("DEBUG: Selected talking image: \(newPath)")
                                                talkingImagePath = newPath
                                            } else {
                                                // print("DEBUG: Talking image selection cancelled")
                                            }
                                        }) {
                                            HStack(spacing: 6) {
                                                Image(systemName: !talkingImagePath.isEmpty ? "checkmark.circle.fill" : "photo.badge.plus")
                                                    .font(.caption)
                                                    .foregroundColor(!talkingImagePath.isEmpty ? .green : .blue)
                                                
                                                Text("Talking")
                                                    .font(.caption)
                                                    .fontWeight(.medium)
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(.regularMaterial)
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 8)
                                                            .stroke(
                                                                LinearGradient(
                                                                    colors: isDarkMode 
                                                                        ? [Color.white.opacity(0.2), Color.white.opacity(0.05)]
                                                                        : [Color.white.opacity(0.8), Color.white.opacity(0.3)],
                                                                    startPoint: .topLeading,
                                                                    endPoint: .bottomTrailing
                                                                ),
                                                                lineWidth: 1
                                                            )
                                                    )
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        
                                        Text(talkingImageDisplayName())
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    
                                    Spacer()
                                }
                                
                                // Reset button
                                HStack {
                                    Spacer()
                                    Button(action: {
                                        // print("DEBUG: Resetting images to defaults")
                                        restingImagePath = defaultRestingImagePath
                                        talkingImagePath = defaultTalkingImagePath
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "arrow.clockwise")
                                                .font(.caption)
                                            Text("Reset to Default")
                                                .font(.caption)
                                        }
                                        .foregroundColor(.blue)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    Spacer()
                                }
                            }
                        }
                    }
                    .padding(.leading, 16)
                }
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.thickMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            LinearGradient(
                                colors: isDarkMode 
                                    ? [Color.white.opacity(0.15), Color.white.opacity(0.02)]
                                    : [Color.white.opacity(0.9), Color.white.opacity(0.4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 8)
        )
    }
    
    var progressCard: some View {
        VStack(spacing: 16) {
            Text("Session Progress")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(isDarkMode ? .white : .primary)
            
            HStack(spacing: 40) {
                VStack {
                    Text(formatTime(timeRemaining))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(isDarkMode ? .white : .primary)
                        .monospacedDigit()
                    Text("Time Remaining")
                        .font(.caption)
                        .foregroundColor(isDarkMode ? .gray : .secondary)
                }
                
                VStack {
                    HStack(spacing: 24) {
                        VStack {
                            Text("\(focusedCount)")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.green)
                            Text("Focused")
                                .font(.caption)
                                .foregroundColor(isDarkMode ? .gray : .secondary)
                        }
                        
                        VStack {
                            Text("\(distractedCount)")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.red)
                            Text("Distracted")
                                .font(.caption)
                                .foregroundColor(isDarkMode ? .gray : .secondary)
                        }
                    }
                }
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.thickMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            LinearGradient(
                                colors: isDarkMode 
                                    ? [Color.white.opacity(0.15), Color.white.opacity(0.02)]
                                    : [Color.white.opacity(0.9), Color.white.opacity(0.4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 8)
        )
    }
    
    var actionSection: some View {
        Button(action: {
            if isRunning {
                stopSession()
            } else {
                startSession()
            }
        }) {
            HStack {
                Image(systemName: isRunning ? "stop.fill" : "play.fill")
                    .font(.title3)
                Text(isRunning ? "STOP SESSION" : "START SESSION")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: isRunning 
                                    ? [Color.red.opacity(0.8), Color.red]
                                    : [Color.blue.opacity(0.8), Color.blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.thinMaterial)
                        .opacity(0.3)
                }
                .shadow(color: (isRunning ? Color.red : Color.blue).opacity(0.3), radius: 12, x: 0, y: 6)
            )
        }
        .buttonStyle(.plain)
        .disabled(workInstruction.isEmpty)
        .opacity(workInstruction.isEmpty ? 0.6 : 1.0)
    }
    
    var warningCard: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            VStack(alignment: .leading) {
                if openAIAPIKey.isEmpty {
                    Text("Set OPENAI_API_KEY environment variable")
                        .font(.subheadline)
                        .foregroundColor(isDarkMode ? .white : .primary)
                }
                if elevenLabsAPIKey.isEmpty {
                    Text("Set ELEVENLABS_API_KEY environment variable")
                        .font(.subheadline)
                        .foregroundColor(isDarkMode ? .white : .primary)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [Color.orange.opacity(0.6), Color.orange.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
                .shadow(color: Color.orange.opacity(0.2), radius: 10, x: 0, y: 4)
        )
    }
    
    func settingItem(_ title: String, value: Binding<Int>, field: Field, suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(isDarkMode ? .white.opacity(0.8) : .secondary)
            
            HStack {
                TextField("", value: value, formatter: NumberFormatter())
                    .textFieldStyle(GlassTextFieldStyle(isDarkMode: isDarkMode))
                    .focused($focusedField, equals: field)
                    .frame(width: 60)
                
                Text(suffix)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(isDarkMode ? .white.opacity(0.7) : .secondary)
            }
        }
    }
    
    
    func requestNotificationPermission() async {
        let notificationCenter = UNUserNotificationCenter.current()
        
        // First check if we already have permission
        let settings = await notificationCenter.notificationSettings()
        
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            // print("DEBUG: Notification permission already granted")
            return
        case .denied:
            // print("DEBUG: Notification permission previously denied - user needs to enable in Settings")
            return
        case .notDetermined:
            // Request permission
            break
        case .ephemeral:
            // print("DEBUG: Ephemeral notification permission")
            return
        @unknown default:
            // print("DEBUG: Unknown notification authorization status")
            return
        }
        
        do {
            // print("DEBUG: Requesting notification authorization with options: alert, sound, badge")
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            // print("DEBUG: Notification permission granted: \(granted)")
            
            if granted {
                // Set up notification delegate for foreground handling
                await MainActor.run {
                    notificationCenter.delegate = NotificationDelegate.shared
                }
            } else {
                // print("DEBUG: Notification permission denied by user")
            }
        } catch {
            // print("DEBUG: Notification permission error: \(error)")
        }
    }
    
    func requestScreenRecordingPermission() async {
        do {
            // This will trigger the screen recording permission prompt
            let _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            // print("DEBUG: Screen recording permission granted")
        } catch {
            // print("DEBUG: Screen recording permission error: \(error)")
        }
    }
    
    func requestAccessibilityPermission() async {
        // Check accessibility permission and show popup if needed
        let trusted = AXIsProcessTrusted()
        if !trusted {
            // print("DEBUG: Accessibility permission not granted, showing system preferences")
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Required"
            alert.informativeText = "LockinPls needs accessibility permission to use global shortcuts. Please grant permission in System Preferences."
            alert.addButton(withTitle: "Open System Preferences")
            alert.addButton(withTitle: "Skip")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                let prefpaneUrl = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                NSWorkspace.shared.open(prefpaneUrl)
            }
        } else {
            // print("DEBUG: Accessibility permission already granted")
        }
        
        // Set up keyboard monitor regardless
        setupKeyboardMonitor()
    }
    
    func startSession() {
        // Request permissions when user first tries to start a session
        Task {
            // print("DEBUG: Requesting permissions before starting session...")
            await requestNotificationPermission()
            await requestScreenRecordingPermission()
            
            await MainActor.run {
                // print("DEBUG: Starting session after permission checks...")
                
                focusedCount = 0
                distractedCount = 0
                startTime = Date()
                endTime = Date().addingTimeInterval(TimeInterval(timerMinutes * 60))
                timeRemaining = TimeInterval(timerMinutes * 60)
                isRunning = true
                
                countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                    timeRemaining = endTime.timeIntervalSince(Date())
                    if timeRemaining <= 0 {
                        stopSession()
                    }
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(screenshotInterval)) {
                    startScreenshotLoop()
                }
                
                // Add visual assistant overlay
                if enableVisualAssistant && !restingImagePath.isEmpty && !talkingImagePath.isEmpty {
                    // print("DEBUG: Starting session with visual assistant enabled")
                    createOverlayWindow(imageName: "resting")
                } else {
                    // print("DEBUG: Visual assistant not starting - enabled: \(enableVisualAssistant), resting: '\(restingImagePath)', talking: '\(talkingImagePath)'")
                }
            }
        }
    }
    
    func stopSession() {
        isRunning = false
        screenshotTimer?.invalidate()
        countdownTimer?.invalidate()
        
        let workingTime = Date().timeIntervalSince(startTime) / 60
        sendNotification(title: "Session Complete!", body: "Focused: \(focusedCount), Distracted: \(distractedCount), Time: \(Int(workingTime)) min")
        
        // Close overlay window and remove keyboard monitor
        if overlayWindow != nil {
            // print("DEBUG: Closing overlay window")
            overlayWindow?.close()
            overlayWindow = nil
        }
        
        if let monitor = localMonitor {
            // print("DEBUG: Removing local keyboard monitor on session stop")
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        if let monitor = globalMonitor {
            // print("DEBUG: Removing global keyboard monitor on session stop")
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
    }
    
    func startScreenshotLoop() {
        guard isRunning else { return }
        screenshotTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(screenshotInterval), repeats: true) { _ in
            guard isRunning else { return }
            takeAndAnalyzeScreenshot()
        }
    }
    
    func takeAndAnalyzeScreenshot() {
        Task {
            guard let screenshot = await captureScreen() else { return }
            analyzeScreenshot(screenshot)
        }
    }
    
    nonisolated func captureScreen() async -> CGImage? {
        do {
            let availableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = availableContent.displays.first else { return nil }
            
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let configuration = SCStreamConfiguration()
            
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            return image
        } catch {
            // print("Screen capture failed: \(error)")
            return nil
        }
    }
    
    func analyzeScreenshot(_ image: CGImage) {
        guard let imageData = convertToJPEG(image) else { return }
        
        let prompt = "Is user focused on: \(workInstruction)? Reply 'All good.' or describe distraction"
        // print("DEBUG: Sending to OpenAI - Prompt: \(prompt)")
        
        sendToOpenAI(imageData: imageData, prompt: prompt) { response in
            // print("DEBUG: OpenAI Response: \(response)")
            DispatchQueue.main.async {
                if response.lowercased().contains("good") {
                    focusedCount += 1
                    // print("DEBUG: User focused. Count: \(focusedCount)")
                } else {
                    distractedCount += 1
                    // print("DEBUG: User distracted. Count: \(distractedCount)")
                    generateDistractionMessage()
                }
            }
        }
    }
    
    func generateDistractionMessage() {
        let prompt = "\(aiPersonality) The user was distracted. Based on your personality, output a sentence or two of reminder to be focused."
        // print("DEBUG: Sending distraction message to OpenAI")
        
        sendToOpenAI(imageData: nil, prompt: prompt) { message in
            // print("DEBUG: Distraction message response: \(message)")
            DispatchQueue.main.async {
                sendNotification(title: "Lock In Pls!", body: message)
                if self.enableTTS {
                    self.playTTS(text: message)
                }
            }
        }
    }
    
    
    nonisolated func sendToOpenAI(imageData: Data?, prompt: String, completion: @escaping (String) -> Void) {
        guard !openAIAPIKey.isEmpty else { 
            // print("DEBUG: OpenAI API key is empty!")
            completion("Error: No API key")
            return 
        }
        
        // print("DEBUG: Making OpenAI API call...")
        
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(openAIAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var messages: [[String: Any]] = []
        
        if let imageData = imageData {
            let base64Image = imageData.base64EncodedString()
            messages.append([
                "role": "user",
                "content": [
                    ["type": "text", "text": prompt],
                    ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64Image)"]]
                ]
            ])
            // print("DEBUG: Sending image + text to OpenAI")
        } else {
            messages.append(["role": "user", "content": prompt])
            // print("DEBUG: Sending text only to OpenAI")
        }
        
        let body: [String: Any] = [
            "model": "gpt-4o",
            "messages": messages,
            "max_tokens": 100
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                // print("DEBUG: Network error: \(error)")
                completion("Error: Network")
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                // print("DEBUG: HTTP Status: \(httpResponse.statusCode)")
            }
            
            guard let data = data else {
                // print("DEBUG: No data received")
                completion("Error: No data")
                return
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                // print("DEBUG: Failed to parse JSON")
                completion("Error: JSON parse")
                return
            }
            
            // print("DEBUG: OpenAI JSON response: \(json)")
            
            guard let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                // print("DEBUG: Failed to extract content from response")
                completion("Error: Response format")
                return
            }
            
            // print("DEBUG: Successfully got OpenAI response")
            completion(content)
        }.resume()
    }
    
    nonisolated func convertToJPEG(_ image: CGImage) -> Data? {
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return mutableData as Data
    }
    
    func playTTS(text: String) {
        createOverlayWindow(imageName: "talking")  // Always show when TTS plays
        
        guard !elevenLabsAPIKey.isEmpty else { 
            // print("DEBUG: ElevenLabs API key is empty!")
            return 
        }
        
        // print("DEBUG: Converting text to speech: \(text)")
        
        var request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(selectedVoiceId)")!)
        request.httpMethod = "POST"
        request.setValue(elevenLabsAPIKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "text": text,
            "model_id": "eleven_flash_v2_5",
            "voice_settings": [
                "stability": 0.5,
                "similarity_boost": 0.75,
                "style": 0.0,
                "use_speaker_boost": true
            ]
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                // print("DEBUG: TTS Network error: \(error)")
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                // print("DEBUG: TTS HTTP Status: \(httpResponse.statusCode)")
            }
            
            guard let data = data else {
                // print("DEBUG: No TTS audio data received")
                return
            }
            
            DispatchQueue.main.async {
                self.playAudioData(data)
            }
        }.resume()
    }
    
    func playAudioData(_ data: Data) {
        // print("DEBUG: playAudioData called with \(data.count) bytes")
        audioManager.play(data: data) {
            // print("DEBUG: Audio finished - switching to resting image")
            DispatchQueue.main.async {
                self.createOverlayWindow(imageName: "resting")
            }
        }
        // print("DEBUG: Playing TTS audio")
    }
    
    func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        
        UNUserNotificationCenter.current().add(request) { _ in }
    }
    
    func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
    
    func createOverlayWindow(imageName: String) {
        // print("DEBUG: createOverlayWindow called with imageName: \(imageName)")
        
        guard enableVisualAssistant else { 
            // print("DEBUG: Visual assistant disabled, skipping overlay creation")
            return 
        }
        
        // Get image path
        let imagePath = (imageName == "talking") ? talkingImagePath : restingImagePath
        // print("DEBUG: Using image path: \(imagePath)")
        
        guard !imagePath.isEmpty, let image = NSImage(contentsOfFile: imagePath) else {
            // print("DEBUG: Image not found or path empty for: \(imageName), path: \(imagePath)")
            return
        }
        
        // print("DEBUG: Successfully loaded image: \(imageName), size: \(image.size)")
        
        // Get active screen
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) else { 
            // print("DEBUG: No active screen found at mouse location")
            return 
        }
        
        // Calculate window position (2 rows × 4 columns grid, bottom-right cell)
        let windowWidth = screen.frame.width / 4
        let windowHeight = screen.frame.height / 2
        let windowRect = NSRect(x: screen.frame.maxX - windowWidth, 
                                y: screen.frame.minY, 
                                width: windowWidth, 
                                height: windowHeight)
        
        // print("DEBUG: Calculated window rect: \(windowRect) on screen: \(screen.frame)")
        
        // Create or show window
        if overlayWindow == nil {
            // print("DEBUG: Creating new overlay window")
            overlayWindow = NSWindow(contentRect: windowRect, styleMask: [.borderless], backing: .buffered, defer: false)
            overlayWindow?.backgroundColor = .clear
            overlayWindow?.level = .floating
            overlayWindow?.ignoresMouseEvents = true
        } else {
            // print("DEBUG: Reusing existing overlay window")
        }
        
        // Update image
        let imageView = NSImageView(frame: NSRect(origin: .zero, size: windowRect.size))
        imageView.image = image
        imageView.imageScaling = .scaleAxesIndependently
        overlayWindow?.contentView = imageView
        overlayWindow?.makeKeyAndOrderFront(nil)  // Always show when called
        
        // print("DEBUG: Overlay window displayed with image: \(imageName)")
    }
    
    func toggleOverlay() {
        // print("DEBUG: toggleOverlay called")
        
        if overlayWindow?.isVisible == true {
            // print("DEBUG: Hiding overlay window")
            overlayWindow?.orderOut(nil)  // Hide
        } else if !restingImagePath.isEmpty && !talkingImagePath.isEmpty {
            // print("DEBUG: Showing overlay window with resting image")
            createOverlayWindow(imageName: "resting")  // Show
        } else {
            // print("DEBUG: Cannot toggle overlay - missing image paths. Resting: '\(restingImagePath)', Talking: '\(talkingImagePath)'")
        }
    }
    
    func keyCodeToString(_ keyCode: UInt16) -> String {
        let keyMap: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
            11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2",
            20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8",
            29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J",
            39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
            48: "Tab", 49: "Space", 50: "`", 51: "Delete", 53: "Escape", 36: "Return"
        ]
        return keyMap[keyCode] ?? "Key \(keyCode)"
    }
    
    func modifiersToString(_ modifiers: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if modifiers.contains(.command) { parts.append("⌘") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.control) { parts.append("⌃") }
        return parts.joined()
    }
    
    func shortcutDisplayString() -> String {
        return "\(modifiersToString(toggleShortcutModifiers))\(keyCodeToString(toggleShortcutKey))"
    }
    
    func hasShortcutConflict() -> String? {
        let commonConflicts: [(NSEvent.ModifierFlags, UInt16, String)] = [
            ([.command], 36, "⌘Return - Open selected item"),
            ([.command], 12, "⌘Q - Quit application"),
            ([.command], 13, "⌘W - Close window"),
            ([.command], 31, "⌘O - Open file"),
            ([.command], 1, "⌘S - Save file"),
            ([.command], 6, "⌘Z - Undo"),
            ([.command], 8, "⌘C - Copy"),
            ([.command], 9, "⌘V - Paste"),
            ([.command, .shift], 4, "⌘⇧H - Hide others"),
            ([.command, .shift], 6, "⌘⇧Z - Redo"),
            ([.command], 48, "⌘Tab - Switch applications"),
            ([.command], 49, "⌘Space - Spotlight search")
        ]
        
        for (modifiers, keyCode, description) in commonConflicts {
            if toggleShortcutModifiers == modifiers && toggleShortcutKey == keyCode {
                return description
            }
        }
        return nil
    }
    
    func setupKeyboardMonitor() {
        // Only proceed if accessibility is granted (already handled in requestAccessibilityPermission)
        guard AXIsProcessTrusted() else {
            // print("DEBUG: Accessibility permission not granted, skipping keyboard monitor setup")
            return
        }
        
        // Remove existing monitors if any
        if let monitor = localMonitor {
            // print("DEBUG: Removing existing local monitor")
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        if let monitor = globalMonitor {
            // print("DEBUG: Removing existing global monitor")
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        
        // print("DEBUG: Setting up global keyboard monitor for \(shortcutDisplayString())")
        // print("DEBUG: Looking for modifiers: \(toggleShortcutModifiers), keyCode: \(toggleShortcutKey)")
        // Set up both local (for shortcut recording) and global monitors
        let localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Handle shortcut recording (only works when app has focus)
            if self.isRecordingShortcut {
                // print("DEBUG: Recording shortcut - modifiers: \(event.modifierFlags), keyCode: \(event.keyCode)")
                
                // Require at least one modifier key
                let validModifiers: NSEvent.ModifierFlags = [.command, .option, .shift, .control]
                let pressedModifiers = event.modifierFlags.intersection(validModifiers)
                
                if !pressedModifiers.isEmpty && event.keyCode != 0 {
                    // Cancel the recording timer
                    self.recordingTimer?.invalidate()
                    self.recordingTimer = nil
                    
                    self.toggleShortcutModifiers = pressedModifiers
                    self.toggleShortcutKey = event.keyCode
                    self.isRecordingShortcut = false
                    self.shortcutJustRecorded = true
                    // print("DEBUG: New shortcut recorded: \(self.shortcutDisplayString())")
                    
                    // Clear the "just recorded" flag after a brief delay to prevent immediate trigger
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.shortcutJustRecorded = false
                    }
                }
                return nil // Consume the event while recording
            }
            
            // Handle toggle shortcut when app is in focus
            if !self.shortcutJustRecorded {
                let eventModifiers = event.modifierFlags.intersection([.command, .option, .shift, .control])
                if eventModifiers == self.toggleShortcutModifiers && event.keyCode == self.toggleShortcutKey {
                    // print("DEBUG: Local \(self.shortcutDisplayString()) pressed - toggling overlay")
                    DispatchQueue.main.async {
                        self.toggleOverlay()
                    }
                    return nil // Consume the event
                }
            }
            
            return event
        }
        
        let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            // Check for toggle shortcut globally
            if !self.shortcutJustRecorded {
                let eventModifiers = event.modifierFlags.intersection([.command, .option, .shift, .control])
                if eventModifiers == self.toggleShortcutModifiers && event.keyCode == self.toggleShortcutKey {
                    // print("DEBUG: Global \(self.shortcutDisplayString()) pressed - toggling overlay")
                    DispatchQueue.main.async {
                        self.toggleOverlay()
                    }
                }
            }
        }
        
        // Store both monitors separately
        self.localMonitor = localMonitor
        self.globalMonitor = globalMonitor
    }
}

struct GlassTextFieldStyle: TextFieldStyle {
    let isDarkMode: Bool
    
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                LinearGradient(
                                    colors: isDarkMode 
                                        ? [Color.white.opacity(0.2), Color.white.opacity(0.08)]
                                        : [Color.black.opacity(0.15), Color.black.opacity(0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                isDarkMode 
                                    ? Color.white.opacity(0.08)
                                    : Color.black.opacity(0.05)
                            )
                    )
            )
            .foregroundColor(isDarkMode ? .white : .primary)
    }
}

#Preview {
    ContentView()
}
