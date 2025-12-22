# Agent Conversation System

## Overview

HaloFi uses a unified, voice-first conversational interface designed for visually impaired users. The system combines voice and text interaction into a single screen with one mental model: "I am talking to my financial assistant."

## Architecture

### Core Principles

1. **One Session, One Timeline, One Transport**
   - Single `sessionId` owned by the coordinator
   - Single connection lifecycle
   - Single event stream for all conversation activity
   - Mutual exclusion: recording OR speaking OR typing (never overlapping)

2. **Event-Based Model**
   - Raw events (`ConversationEvent`) are the source of truth
   - Transcript entries are derived for rendering
   - Enables streaming, partials, and status messages

3. **Voice is Primary, Text is Secondary**
   - Large mic button is the primary input
   - Text input is always available but not emphasized
   - Agent responses are spoken (unless muted or VoiceOver is active)

### File Structure

```
Features/Conversation/
├── Views/
│   ├── ConversationView.swift              # Main unified view
│   └── TranscriptView.swift                # Scrollable transcript
├── Components/
│   ├── TranscriptBlock.swift               # Individual entry (NOT chat bubble)
│   ├── ConversationHeader.swift            # Status + mute toggle + more
│   ├── MicButton.swift                     # Large 120pt mic with dynamic label
│   └── TextInputArea.swift                 # Inline expandable text input
├── ViewModels/
│   └── ConversationViewModel.swift         # UI state, owns coordinator + store
└── Models/
    ├── ConversationState.swift             # Lifecycle state enum
    ├── InteractionMode.swift               # Voice vs Text mode
    └── ConversationEvent.swift             # Event types with delta/final separation

Services/Conversation/
├── ConversationCoordinator.swift           # THE authority - owns session, connection, events
├── ConversationTranscriptStore.swift       # Append-only event store, derives entries
├── AudioFeedbackService.swift              # Earcons + haptics
└── SpeechSynthesisService.swift            # TTS for agent responses
```

### State Machine

```swift
enum ConversationState {
    case idle               // Ready, not connected
    case connecting         // Establishing connection
    case listening          // Mic active, recording
    case processing         // Awaiting server response
    case speaking           // Agent response playing
    case disconnected       // Connection dropped
    case permissionNeeded   // Mic permission not granted
    case error(String)      // Error with message
}
```

**Rules:**
- When speaking → not listening
- When listening → not speaking
- Typing → pauses listening
- Audio session transitions owned by coordinator only

### Event Types

```swift
enum ConversationEvent {
    // User events
    case userText(id:, text:, timestamp:)
    case userSpeechDelta(id:, delta:, timestamp:)
    case userSpeechFinal(id:, text:, timestamp:)

    // Agent events (delta/final separation prevents overwrite bugs)
    case agentTextDelta(id:, delta:, timestamp:)
    case agentTextFinal(id:, text:, timestamp:)

    // Tool events
    case toolCallStarted(id:, name:, timestamp:)
    case toolCallFinished(id:, name:, summary:, timestamp:)

    // System events
    case systemStatus(id:, message:, timestamp:)
    case error(id:, message:, timestamp:)
}
```

---

## Quick Start

1. **Launch**: Tap the voice button on the Home screen
2. **Connect**: The view auto-connects when appearing
3. **Speak or Type**:
   - Tap the mic to start speaking
   - Or tap "Type instead" to switch to text input
4. **View Responses**: Transcript shows all messages in large, accessible blocks

---

## Accessibility Features

### VoiceOver Support
- Each transcript block is a single accessible element
- `accessibilityLabel`: "Halo said" / "You said"
- `accessibilityValue`: Message content
- `accessibilityHint`: "Double tap to copy"
- State changes announced via `UIAccessibility.post(notification:)`

### Dynamic Type
- Supports `.medium` to `.accessibility5`
- Transcript uses `.title3` font for readability
- All UI scales appropriately

### Haptic Feedback
- Start listening: Medium impact
- Processing: Light impact
- Error: Error notification haptic

### Audio Feedback
- Earcon support for: start listening, stop listening, error
- TTS for agent responses (disabled when VoiceOver is active)
- Audio ducking when speaking

---

## Integration Guide

### Using the Coordinator

```swift
// Get the shared coordinator
let coordinator = ConversationCoordinator.shared

// Connect to backend
await coordinator.connect()

// Start listening (voice mode)
await coordinator.startListening()

// Send text message
await coordinator.sendText("What's my balance?")

// Handle events
coordinator.onEvent = { event in
    switch event {
    case .agentTextFinal(_, let text, _):
        print("Agent said: \(text)")
    default:
        break
    }
}
```

### Wiring to UI

```swift
@Observable
class MyViewModel {
    let coordinator = ConversationCoordinator.shared
    let store = ConversationTranscriptStore()

    init() {
        // Wire events to store
        coordinator.onEvent = { [weak store] event in
            store?.append(event)
        }
    }
}
```

---

## Testing

### Example Messages

```
What is my account balance?
Show me my recent transactions
How much did I spend this month?
What's my spending trend?
```

### Testing Different Scenarios

| Scenario | How to Test | Expected Behavior |
|----------|-------------|-------------------|
| Voice input | Tap mic, speak | Text appears in transcript |
| Text input | Tap "Type instead", type message | Same conversation flow |
| Streaming | Ask complex question | Text appears progressively |
| Error handling | Disconnect network | Error message in transcript |
| Privacy mode | Toggle in More menu | TTS disabled, haptics only |
| VoiceOver + TTS | Enable VoiceOver | TTS auto-disabled |

### Connection Flow

1. `coordinator.connect()` → State: `.connecting`
2. WebSocket connected → State: `.idle`
3. `connection_ack` received → Session ID stored
4. User speaks/types → State: `.processing`
5. Agent responds → State: `.speaking` (if TTS) or `.idle`

---

## Troubleshooting

### Can't Connect
- Check login status (JWT required)
- Verify backend is running
- Check network connectivity
- Look for error events in transcript

### Voice Not Working
- Check microphone permission
- State should be `.permissionNeeded` if denied
- Verify audio session configuration

### TTS Not Speaking
- Check if VoiceOver is enabled (TTS disabled by default)
- Verify privacy mode is off
- Check `SpeechSynthesisService.isMuted`

### Streaming Not Updating
- Verify `agentTextDelta` events have same `id`
- Check `TranscriptStore.hasStreamingAgentEntry`
- Look for `agentTextFinal` to close stream

---

## Code Locations

| Component | Location |
|-----------|----------|
| Main View | `Features/Conversation/Views/ConversationView.swift` |
| Coordinator | `Services/Conversation/ConversationCoordinator.swift` |
| Transcript Store | `Services/Conversation/ConversationTranscriptStore.swift` |
| Events | `Features/Conversation/Models/ConversationEvent.swift` |
| TTS | `Services/Conversation/SpeechSynthesisService.swift` |
| Haptics | `Services/Conversation/AudioFeedbackService.swift` |
| Voice Service | `Services/VoiceService.swift` |
| Agent WebSocket | `Services/WebSocket/AgentWebSocketManager.swift` |

---

## Milestone 2 (Future)

- [ ] Streaming partial agent text with visual indicator
- [ ] Voice capture with real-time transcription display
- [ ] Smart VoiceOver/TTS behavior (detect and adapt)
- [ ] Robust reconnect with retry prompts
- [ ] Privacy mode toggle in header
- [ ] Proper earcon sound files
- [ ] "Jump to latest" button when scrolled
