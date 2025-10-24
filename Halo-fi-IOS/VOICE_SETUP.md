# Voice Chat WebSocket Integration Setup

## Required Permissions

Add the following permissions to your app's Info.plist or project settings:

### Microphone Permission
```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app needs access to your microphone to enable voice chat with our AI assistant.</string>
```

### Audio Session Configuration
The app is configured to use `.playAndRecord` category with `.defaultToSpeaker` option for optimal voice chat experience.

## WebSocket Endpoint

The app connects to: `wss://halofiapp-production.up.railway.app/ws/voice`

## Features Implemented

### 1. WebSocket Connection Management
- `WebSocketManager`: Handles connection lifecycle
- `WebSocketConnection`: Generic WebSocket wrapper
- Automatic reconnection and error handling

### 2. Voice Service
- `VoiceService`: Manages audio recording and playback
- Real-time audio streaming to WebSocket
- Audio session configuration for voice chat

### 3. Message Types
- **Outgoing**: Voice start, audio data, voice end, ping
- **Incoming**: Voice response, error messages, pong

### 4. UI Integration
- Updated `VoiceConversationView` with real WebSocket connection
- Dynamic animations based on recording/connection state
- Error handling and user feedback

## Usage

1. User taps voice conversation button
2. App requests microphone permission
3. WebSocket connection established
4. Audio recording starts automatically
5. Real-time audio streaming to AI agent
6. AI responses played back to user

## Error Handling

- Microphone permission denied
- WebSocket connection failures
- Audio recording/playback errors
- Network connectivity issues

## Next Steps

1. Add microphone permission to project settings
2. Test WebSocket connection with your backend
3. Implement audio codec optimization
4. Add connection quality indicators
5. Implement reconnection logic

