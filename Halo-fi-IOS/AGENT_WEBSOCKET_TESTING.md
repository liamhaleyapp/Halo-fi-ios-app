# Agent WebSocket Testing Guide

## Quick Start

1. **Access the Test View**: 
   - In DEBUG builds, you'll see a "Test Agent Chat" button on the Home screen
   - Tap it to open the Agent Chat view

2. **Connection**:
   - The view automatically connects when it appears
   - You'll see a connection status bar at the top (green = connected, red = disconnected)
   - A connection acknowledgment message will appear when connected

3. **Send Messages**:
   - Type your message in the text field at the bottom
   - Tap the send button (arrow icon)
   - Messages appear in the chat as you send and receive them

## Example Messages to Test

### Basic Questions
```
What is my account balance?
Show me my recent transactions
What are my spending categories?
```

### Account Queries
```
How much did I spend this month?
What's my total income this year?
Show me transactions from last week
```

### Financial Advice
```
How can I save more money?
What's my spending trend?
Am I overspending in any category?
```

### Context-Aware Messages
The app automatically includes context like:
- Platform: "ios"
- Timestamp: Current time

You can customize the context in `AgentChatView.swift` in the `sendMessage()` function.

## What to Expect

### Connection Flow
1. **Connection Acknowledgment**: You'll receive a `connection_ack` message with:
   - Connection status message
   - Session ID (for continuing conversations)
   - User ID

2. **Agent Responses**: Two types:
   - **Complete Response**: Full message in one `agent_response`
   - **Streaming Response**: Multiple `stream` chunks that build up the message

3. **Errors**: If something goes wrong, you'll see:
   - Error message
   - Error code (AUTH_ERROR, VALIDATION_ERROR, etc.)

## Testing Different Scenarios

### Test Streaming
Send a message that might generate a long response. You should see:
- Text appearing character by character or chunk by chunk
- A "complete" flag when streaming finishes

### Test Error Handling
- Disconnect your internet and try sending a message
- Send an empty message (should be prevented by UI)
- Try connecting without being logged in (should show auth error)

### Test Session Continuity
- Send multiple messages in sequence
- Check that the session ID remains the same
- Verify context is maintained across messages

## Debug Information

The chat view shows:
- **Connection Status**: Green/red indicator
- **Session ID**: First 8 characters of the session
- **Message Timestamps**: When each message was sent/received
- **System Messages**: Connection events and errors

## Troubleshooting

### Can't Connect
- Check that you're logged in (JWT token required)
- Verify the backend is running
- Check network connectivity
- Look for error messages in the chat

### No Responses
- Check the connection status indicator
- Verify messages are being sent (they appear in chat)
- Check backend logs for incoming messages
- Look for error messages in the chat

### Streaming Not Working
- Some responses may come as complete messages instead of streams
- Check if `complete: true` flag appears in stream chunks
- Verify the backend supports streaming

## Code Location

- **Manager**: `Services/WebSocket/AgentWebSocketManager.swift`
- **Messages**: `Shared/Networking/AgentWebSocketMessages.swift`
- **Test View**: `Features/Voice/Views/AgentChatView.swift`
- **Example Usage**: `Services/WebSocket/AgentWebSocketExample.swift`

## Next Steps

Once testing is complete, you can:
1. Integrate the Agent WebSocket into your main app flow
2. Customize the UI to match your app's design
3. Add more context to messages (user preferences, account data, etc.)
4. Implement conversation history persistence
5. Add typing indicators and better loading states

