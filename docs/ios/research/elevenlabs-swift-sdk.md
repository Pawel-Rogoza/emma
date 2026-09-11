# ElevenLabs Swift SDK + Conversational AI auth — factual provider research

Research date context: project docs written 2026-09-11. Every external fact below carries a source link.
All SDK symbol claims were verified against the **`v3.3.1` git tag**, not `main` (README and `Documentation/Usage.md` at `main` are byte-identical to the `v3.3.1` tag as of this research).

---

## 1. Repo and pinning

| Item | Value | Source |
|---|---|---|
| Repository | `https://github.com/elevenlabs/elevenlabs-swift-sdk` (README uses the `.git` clone URL) | [README](https://github.com/elevenlabs/elevenlabs-swift-sdk/blob/v3.3.1/README.md) |
| Package manager | Swift Package Manager — `Package.swift` present, product/library `ElevenLabs`, consumed as `import ElevenLabs` | [Package.swift @v3.3.1](https://github.com/elevenlabs/elevenlabs-swift-sdk/blob/v3.3.1/Package.swift) |
| Latest **stable** release | **`v3.3.1`**, published **2026-09-08T08:24:20Z** | [releases/latest](https://api.github.com/repos/elevenlabs/elevenlabs-swift-sdk/releases/latest), [release page](https://github.com/elevenlabs/elevenlabs-swift-sdk/releases/tag/v3.3.1) |
| Pre-release (do not use) | `v4.0.0-alpha.1`, published 2026-09-01, flagged `prerelease: true` | [releases list](https://api.github.com/repos/elevenlabs/elevenlabs-swift-sdk/releases?per_page=10) |
| Platform requirement (spec) | `.iOS(.v13)`, `.macOS(.v10_15)`, `.macCatalyst(.v14)`, `.visionOS(.v1)`, `.tvOS(.v17)`; `swift-tools-version:5.9` | [Package.swift @v3.3.1](https://github.com/elevenlabs/elevenlabs-swift-sdk/blob/v3.3.1/Package.swift) |
| Platform requirement (README) | iOS 13.0+ · macOS 10.15+ · macCatalyst 14.0+ · visionOS 1.0+ · tvOS 17.0+; Xcode 15.0+ · Swift 5.9+ | [README @v3.3.1](https://github.com/elevenlabs/elevenlabs-swift-sdk/blob/v3.3.1/README.md) |

**Conflict to be aware of:** the official docs page for the Swift SDK states *"The SDK requires iOS 14.0+ / macOS 11.0+ and Swift 5.9+"* and shows `from: "2.0.0"` — that page is **stale** relative to `v3.3.1`. Prefer `Package.swift` / the tagged README ([docs page](https://elevenlabs.io/docs/eleven-agents/libraries/swift)).

### Third-party transitive dependency

`Package.swift @v3.3.1` declares exactly one dependency:

```swift
.package(url: "https://github.com/livekit/client-sdk-swift.git", from: "2.10.0")
```

- Product used: `.product(name: "LiveKit", package: "client-sdk-swift")`. ([Package.swift](https://github.com/elevenlabs/elevenlabs-swift-sdk/blob/v3.3.1/Package.swift))
- Latest LiveKit 2.x release: **`2.16.0`**, published **2026-08-04** ([release](https://github.com/livekit/client-sdk-swift/releases/tag/2.16.0)).
- LiveKit 2.16.0's own dependencies: `livekit/webrtc-xcframework` `exact: "144.7559.11"`, `livekit/livekit-uniffi-xcframework` `exact: "0.0.6"`, `apple/swift-protobuf` `from: "1.31.0"` ([LiveKit Package.swift @2.16.0](https://github.com/livekit/client-sdk-swift/blob/2.16.0/Package.swift)).
- **Toolchain trap (verified):** LiveKit's declared tools version jumps from `5.9` (2.10.0, 2.13.0) to `6.0` (2.14.0/2.14.1) to `6.1` (2.15.0+). Because ElevenLabs uses a floating `from: "2.10.0"`, a fresh resolve today lands on a LiveKit that requires a Swift 6.x toolchain, even though ElevenLabs claims Xcode 15.0+ ([2.10.0](https://github.com/livekit/client-sdk-swift/blob/2.10.0/Package.swift), [2.13.0](https://github.com/livekit/client-sdk-swift/blob/2.13.0/Package.swift), [2.14.0](https://github.com/livekit/client-sdk-swift/blob/2.14.0/Package.swift), [2.15.0](https://github.com/livekit/client-sdk-swift/blob/2.15.0/Package.swift)).

### Exact pin a consumer would write

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/elevenlabs/elevenlabs-swift-sdk.git", exact: "3.3.1"),

    // Strongly recommended: also pin LiveKit, otherwise the transitive
    // "from: 2.10.0" range floats to the newest 2.x (2.16.0, needs Swift 6.1 tools).
    .package(url: "https://github.com/livekit/client-sdk-swift.git", exact: "2.16.0")
]
```

The no-`v` spelling `"3.3.1"` is the form the README itself uses (`from: "3.3.1"`), matching tag `v3.3.1`. The README's own snippet is a **range** pin, not an exact pin ([README](https://github.com/elevenlabs/elevenlabs-swift-sdk/blob/v3.3.1/README.md)).

---

## 2. Public API surface (verified against v3.3.1 source)

### Entry point

`public enum ElevenLabs` is the namespace. It also exposes `public static let version = "3.3.1"` and `@MainActor public static func configure(_ configuration: Configuration)` ([ElevenLabs.swift](https://github.com/elevenlabs/elevenlabs-swift-sdk/blob/v3.3.1/Sources/ElevenLabs/Public/ElevenLabs/ElevenLabs.swift)).

Five `@MainActor public static func startConversation(...) async throws -> Conversation` overloads exist:

| Overload (exact labels) | Use |
|---|---|
| `startConversation(agentId:config:onAgentReady:onDisconnect:)` | public agent, no credential |
| `startConversation(conversationToken:config:onAgentReady:onDisconnect:)` | **private agent, backend-issued conversation token (WebRTC)** |
| `startConversation(tokenProvider:config:onAgentReady:onDisconnect:)` | `@escaping @Sendable () async throws -> String` closure returning a conversation token |
| `startConversation(signedWebSocketURL:config:onAgentReady:onDisconnect:)` | text-only; **forces `conversationOverrides.textOnly = true`** |
| `startConversation(auth:config:)` | lowest-level, takes an `ElevenLabsConfiguration` |

([ElevenLabs.swift](https://github.com/elevenlabs/elevenlabs-swift-sdk/blob/v3.3.1/Sources/ElevenLabs/Public/ElevenLabs/ElevenLabs.swift))

Auth factory symbols on `public struct ElevenLabsConfiguration`:
`ElevenLabsConfiguration.publicAgent(id:participantName:environment:)`, `.conversationToken(_:participantName:environment:)`, `.signedWebSocketURL(_:participantName:) throws`, `.customTokenProvider(...)`
([ElevenLabsConfiguration.swift](https://github.com/elevenlabs/elevenlabs-swift-sdk/blob/v3.3.1/Sources/ElevenLabs/Public/ElevenLabs/ElevenLabsConfiguration.swift)).

> Note: the marketing docs page shows a *different* spelling, `ElevenLabs.startConversation(auth: .conversationToken(token), ...)`. That matches source only via `ElevenLabsConfiguration.conversationToken(_:...)`, not via the label `conversationToken:` on the top-level method. Use the `conversationToken:` label form from the tagged README/source ([docs](https://elevenlabs.io/docs/eleven-agents/libraries/swift)).

### The `Conversation` object

`@MainActor public final class Conversation: ObservableObject` — Combine-observable, all state via `@Published`.

**Published state** (`public internal(set)`): `state`, `startupState`, `startupMetrics`, `messages`, `agentState`, `isMuted`, `pendingToolCalls`, `conversationMetadata`, `mcpToolCalls`, `mcpConnectionStatus`, `latestAudioAlignment`, `latestAudioEvent`, `audioDevices`, `selectedAudioDeviceID` ([Conversation.swift](https://github.com/elevenlabs/elevenlabs-swift-sdk/blob/v3.3.1/Sources/ElevenLabs/Public/Conversation/Conversation.swift)).

**Public methods:** `startConversation(with:options:)`, `startConversation(auth:options:)`, `endConversation()`, `sendMessage(_:)`, `toggleMute()`, `setMuted(_:)`, `setMicrophoneMuted(_:)`, `interruptAgent()`, `updateContext(_:)`, `sendFeedback(_:eventId:)`, `sendMCPToolApproval(toolCallId:isApproved:)`, `sendToolResult(for:result:isError:errorType:)` (3 overloads: `some Encodable`, `String`, and a deprecated `Any`), `markToolCallCompleted(_:)` ([Conversation.swift](https://github.com/elevenlabs/elevenlabs-swift-sdk/blob/v3.3.1/Sources/ElevenLabs/Public/Conversation/Conversation.swift)).

### Callbacks — `ConversationConfig` (non-reactive path)

Verified properties (`@Sendable` closures) ([ConversationConfig.swift](https://github.com/elevenlabs/elevenlabs-swift-sdk/blob/v3.3.1/Sources/ElevenLabs/Public/Conversation/ConversationConfig.swift)):

| Concern | Symbol |
|---|---|
| Connection state | `$state` / `conversation.state`; also `onStartupStateChange`, `startupConfiguration`, `startupState` |
| Connection lifecycle | `onAgentReady: () -> Void`, `onDisconnect: (DisconnectionReason) -> Void`, `onError: (ConversationError) -> Void` |
| User transcript | `onUserTranscript: (_ text: String, _ eventId: Int) -> Void`; also `messages: [Message]` with `Message{id, role, content, timestamp, eventId?}` and `Role` `.user`/`.agent` |
| Agent response text | `onAgentResponse: (_ text: String, _ eventId: Int) -> Void`, `onAgentResponseCorrection`, `onAgentResponseMetadata` |
| Agent audio playback state | `agentState: ElevenLabs.AgentState` (`.listening` / `.speaking` / `.thinking`) + `onAgentStateChange`; `onSpeechActivity: (SpeechActivityEvent) -> Void` (LiveKit type re-exported as `ElevenLabs.SpeechActivityEvent`); `latestAudioEvent`, `latestAudioAlignment`, `onAudioAlignment` |
| Interruption | `onInterruption: (_ eventId: Int) -> Void`; outbound barge-in via `conversation.interruptAgent()` |
| Tool calls | `onUnhandledClientToolCall: (ClientToolCallEvent) -> Void`, `onAgentToolRequest`, `onAgentToolResponse` |
| User voice activity | `onVadScore: (_ score: Double) -> Void` |

Sibling event types on the incoming-event enum: `UserTranscriptEvent`, `TentativeUserTranscriptEvent`, `AgentResponseEvent`, `AgentResponseCorrectionEvent`, `AgentResponseMetadataEvent`, `AgentChatResponsePartEvent`, `AudioAlignment`, `AudioEvent`, `InterruptionEvent`, `TentativeAgentResponseEvent`, `ConversationMetadataEvent`, `VadScoreEvent`, `PingEvent`, `ClientToolCallEvent`, `AgentToolRequestEvent`, `AgentToolResponseEvent` ([IncomingEvents.swift](https://github.com/elevenlabs/elevenlabs-swift-sdk/blob/v3.3.1/Sources/ElevenLabs/Public/ElevenLabs/Events/IncomingEvents.swift)).

`ConversationState` = `.idle | .connecting | .active(CallInfo) | .ended(reason: EndReason) | .error(ConversationError)` ([ConversationState.swift](https://github.com/elevenlabs/elevenlabs-swift-sdk/blob/v3.3.1/Sources/ElevenLabs/Public/Conversation/ConversationState.swift)).

Audio tracks for custom playback/visualisation: `conversation.inputTrack: LocalAudioTrack?`, `conversation.agentAudioTrack: RemoteAudioTrack?` ([Conversation.swift](https://github.com/elevenlabs/elevenlabs-swift-sdk/blob/v3.3.1/Sources/ElevenLabs/Public/Conversation/Conversation.swift)).

---

## 3. Authentication

### The two mechanisms

| | WebRTC **conversation token** | **Signed URL** |
|---|---|---|
| Endpoint | `GET https://api.elevenlabs.io/v1/convai/conversation/token` | `GET https://api.elevenlabs.io/v1/convai/conversation/get-signed-url` (legacy alias `/get_signed_url` also present) |
| Required query | `agent_id` | `agent_id` |
| Optional query | `participant_name`, `branch_id`, `version_id`, `environment`, `debug_events_request` | `include_conversation_id`, `branch_id`, `version_id`, `environment`, `debug_events_request` |
| Response | `{"token": "...", "conversation_id": "..."}` | `{"signed_url": "..."}` |
| What the client does with it | LiveKit/WebRTC room join | WebSocket connect to `wss://api.elevenlabs.io/v1/convai/conversation?agent_id=...&<signature>` |
| Swift SDK support | **Voice conversations** | **Text-only conversations** |

Sources: [Get conversation token](https://elevenlabs.io/docs/eleven-agents/api-reference/conversations/get-webrtc-token), [Get signed URL](https://elevenlabs.io/docs/eleven-agents/api-reference/conversations/get-signed-url), [OpenAPI spec](https://api.elevenlabs.io/openapi.json).

Regional hosts for both: `https://api.elevenlabs.io`, `https://api.us.elevenlabs.io`, `https://api.eu.residency.elevenlabs.io`, `https://api.in.residency.elevenlabs.io`, `https://api.sg.residency.elevenlabs.io` ([token ref](https://elevenlabs.io/docs/eleven-agents/api-reference/conversations/get-webrtc-token)).

### Auth header for the backend call

All API requests carry the API key in an **`xi-api-key`** header ([API Authentication](https://elevenlabs.io/docs/api-reference/authentication)). The signed-URL guide shows it explicitly:

```bash
curl -X GET "https://api.elevenlabs.io/v1/convai/conversation/get-signed-url?agent_id=<agent-id>" \
     -H "xi-api-key: <your-api-key>"
```

([Agent authentication](https://elevenlabs.io/docs/eleven-agents/customization/authentication), [WebSocket docs](https://elevenlabs.io/docs/eleven-agents/libraries/web-sockets))

Caveat: the `/v1/convai/conversation/token` entry in the OpenAPI spec declares `security: null` and its API-reference examples show **no** auth header, so the `xi-api-key` requirement for *that specific endpoint* is not formally declared in the published spec — only implied by the global API-key policy. Treat "GET /token without a key returns 401" as **unverified**.

### Signed URL format — inconsistent between two official pages

- `{"signed_url": "wss://api.elevenlabs.io/v1/convai/conversation?agent_id=...&conversation_signature=your-token"}` ([Agent authentication](https://elevenlabs.io/docs/eleven-agents/customization/authentication))
- `{"signed_url": "wss://api.elevenlabs.io/v1/convai/conversation?agent_id=<id>&token=<token>"}` ([WebSocket docs](https://elevenlabs.io/docs/eleven-agents/libraries/web-sockets))

Do not pattern-match the query-parameter name; treat the whole URL as opaque.

Documented expiry: **the signed URL expires after 15 minutes** ([Agent authentication](https://elevenlabs.io/docs/eleven-agents/customization/authentication)). The conversation token's TTL is **not documented on the endpoint page — unverified**.

### Which one the Swift SDK requires (source-verified)

`Sources/ElevenLabs/Internal/Authorization/ConnectionConstants.swift`:

```swift
static let voiceConversationUrl = "wss://livekit.rtc.elevenlabs.io"
static let textConversationUrl  = "wss://api.elevenlabs.io/v1/convai/conversation"
static let tokenUrl             = "https://api.elevenlabs.io/v1/convai/conversation/token"
```

([ConnectionConstants.swift](https://github.com/elevenlabs/elevenlabs-swift-sdk/blob/v3.3.1/Sources/ElevenLabs/Internal/Authorization/ConnectionConstants.swift))

- **Voice:** `TokenService.fetchConnectionDetails` takes the `token` string and returns it as LiveKit's `participantToken`, with `serverUrl = wss://livekit.rtc.elevenlabs.io` (room name and participant name left empty because "LiveKit extracts them from the JWT"). So for a voice conversation your backend must return the **`token` field of `GET /v1/convai/conversation/token`** ([TokenService.swift](https://github.com/elevenlabs/elevenlabs-swift-sdk/blob/v3.3.1/Sources/ElevenLabs/Public/Authorization/TokenService.swift), [WebRTCConnectionManager.swift](https://github.com/elevenlabs/elevenlabs-swift-sdk/blob/v3.3.1/Sources/ElevenLabs/Internal/Networking/WebRTCConnectionManager.swift)).
- **Signed URL is rejected for voice:** passing `.signedWebSocketURL` throws `ConversationError.authenticationFailed("Signed WebSocket URLs are only supported for text-only conversations.")` ([TokenService.swift](https://github.com/elevenlabs/elevenlabs-swift-sdk/blob/v3.3.1/Sources/ElevenLabs/Public/Authorization/TokenService.swift)).
- **Text-only:** `startConversation(signedWebSocketURL:)` is the only path that uses the WebSocket transport.

**Confirmation that the client never needs an API key:** the `xi-api-key` header is only set inside `#if DEBUG`, from an opt-in `debugApiKey` initializer parameter that does not exist in release builds ([TokenService.swift](https://github.com/elevenlabs/elevenlabs-swift-sdk/blob/v3.3.1/Sources/ElevenLabs/Public/Authorization/TokenService.swift)). The SDK's own client-side token fetch (used for public agents) sends only `agent_id`, `source=swift_sdk`, `version=3.3.1`, and optional `environment` — no key.

**Verified quirk:** `ElevenLabsConfiguration.participantName` (default `"user"`) is stored but **never forwarded** — it does not appear in the token request query and `ConnectionDetails.participantName` is hard-coded to `""`. The `/token` endpoint's optional `participant_name` parameter is therefore unreachable through this SDK in v3.3.1.

Session binding: the SDK sends `conversation_initiation_client_data` **after** the room connects, carrying `user_id`, `dynamic_variables`, `custom_llm_extra_body`, `branch_id`, `environment`, and `source_info{source, version}` (with `swift_sdk` as an allowed source value) ([agent.asyncapi.yaml](https://github.com/elevenlabs/elevenlabs-swift-sdk/blob/v3.3.1/Sources/ElevenLabs/Internal/Protocol/schemas/agent.asyncapi.yaml), [WebRTCConnectionManager.swift](https://github.com/elevenlabs/elevenlabs-swift-sdk/blob/v3.3.1/Sources/ElevenLabs/Internal/Networking/WebRTCConnectionManager.swift)).

---

## 4. Custom LLM

### Format expected

ElevenLabs expects an **OpenAI-compatible** endpoint, one of ([Custom LLM docs](https://elevenlabs.io/docs/eleven-agents/customization/llm/custom-llm)):

- Chat Completions — `POST /v1/chat/completions`
- Responses API — `POST /v1/responses`
- (`api_type` enum in the spec also allows `"websocket"`; the docs guide only covers the two HTTP forms)

**Streaming SSE is mandatory:** `Content-Type: text/event-stream`.

- Chat Completions: every chunk `data: {json}\n\n`, stream terminated by `data: [DONE]\n\n`. The documented request shape includes `messages`, `model`, `temperature`, `max_tokens`, `stream`, and `user_id`. ([docs](https://elevenlabs.io/docs/eleven-agents/customization/llm/custom-llm))
- Responses API: chunks `event: {type}\ndata: {json}\n\n`, minimum required events `response.output_text.delta` and `response.completed`, terminated by `data: [DONE]\n\n`. ([docs](https://elevenlabs.io/docs/eleven-agents/customization/llm/custom-llm))

**Tool calls / function calling:** supported and expressed in standard OpenAI `tools` format. If system tools are configured, they arrive in the request's `tools` array; documented system tools are `end_call`, `language_detection`, `transfer_to_agent`, `transfer_to_number`, `skip_turn`, `voicemail_detection`, each with `{"type":"function","function":{"name":...,"arguments":"<json string>"}}`. Your model must be able to emit OpenAI-format function calls to use them. ([docs](https://elevenlabs.io/docs/eleven-agents/customization/llm/custom-llm))

**Reasoning** must be returned separately from the answer (Chat Completions: `reasoning` or `reasoning_content` delta field; Responses API: a `reasoning` output item with `summary`). ([docs](https://elevenlabs.io/docs/eleven-agents/customization/llm/custom-llm))

### Agent-side configuration schema (authoritative field names)

From the published spec, `CustomLLM` ([OpenAPI](https://api.elevenlabs.io/openapi.json)):

- `url` (required) — "The URL of the Chat Completions compatible endpoint"
- `model_id` (optional)
- `api_key` — either `{"secret_id": "..."}` (workspace secret) or `{"env_var_label": "..."}` (env var)
- `auth_connection` — "Only auth connections that produce an **Authorization Bearer** token are supported; Basic auth, mTLS, custom header, and URL secret auth connections are not supported."
- `request_headers` — arbitrary headers, values may be a literal string, a secret locator, a dynamic-variable reference, or an env-var locator
- `api_version`
- `api_type` — `chat_completions` (default) | `responses` | `websocket`

### Authentication it sends

**What is documented:** the `api_key` secret and `request_headers` are configurable; `auth_connection` explicitly produces an `Authorization: Bearer` token.

**What is NOT documented:** the exact header name/prefix that the `api_key` secret is injected as. Every official custom-LLM provider guide (Groq, Together AI, Cloudflare) uses `Authorization: Bearer <key>` in its own curl example and then instructs you to select that key in the dashboard's "API key" dropdown, which strongly implies Bearer — but ElevenLabs never states it in prose ([Groq guide](https://elevenlabs.io/docs/eleven-agents/customization/llm/custom-llm/groq-cloud), [Together AI guide](https://elevenlabs.io/docs/eleven-agents/customization/llm/custom-llm/together-ai), [Cloudflare guide](https://elevenlabs.io/docs/eleven-agents/customization/llm/custom-llm/cloudflare)). **Treat the exact header as unverified — verify empirically with a request-inspecting endpoint before building on it.**

### Is the request bound to the end-user session?

Partially, and verifiably so:

1. **`user_id`** is present in the custom-LLM request body. The docs' sample request model declares `user_id: Optional[str]` and the example request body shows a `user_id`. This value originates from the client's conversation init (`user_id` field in `conversation_initiation_client_data`, or `ConversationConfig.userId` in Swift). ([Custom LLM docs](https://elevenlabs.io/docs/eleven-agents/customization/llm/custom-llm), [agent.asyncapi.yaml](https://github.com/elevenlabs/elevenlabs-swift-sdk/blob/v3.3.1/Sources/ElevenLabs/Internal/Protocol/schemas/agent.asyncapi.yaml))
2. **`elevenlabs_extra_body`** is the real session-binding channel. Anything the client puts in `custom_llm_extra_body` at conversation-init time is delivered to your custom LLM in the request body under `elevenlabs_extra_body`. In Swift this is `ConversationConfig.customLlmExtraBody: [String: String]?` ([ConversationConfig.swift](https://github.com/elevenlabs/elevenlabs-swift-sdk/blob/v3.3.1/Sources/ElevenLabs/Public/Conversation/ConversationConfig.swift), [Custom LLM docs](https://elevenlabs.io/docs/eleven-agents/customization/llm/custom-llm)).
   - Verified chain: Swift config → init event field `custom_llm_extra_body` (AsyncAPI schema) → request body field `elevenlabs_extra_body` (docs example). The field *rename* between init and LLM request is shown only by example, not stated normatively.
   - Practical consequence: your backend can hand the app an opaque, signed session identifier to place in `customLlmExtraBody`; the custom LLM then sees it on every turn and can validate/scope the request. **There is no documented ElevenLabs-generated signature or HMAC on the custom-LLM request**, so the binding is only as trustworthy as whatever you put in there plus whatever auth header you configured.
3. Note the docs describe `custom_llm_extra_body` as client-overridable conversation config; a hostile client could supply its own value. Do not treat it as an authentication primitive by itself — validate it server-side against the credential your own backend issued.

---

## 5. Tool calling

### Client tools on iOS (SDK v3.3.1)

1. **The tool must exist server-side first.** Create it in the ElevenLabs dashboard with Tool Type = **Client**, or via CLI (`elevenlabs tools add "logMessage" --type "client" ...`) / API (`tool_config.type = "client"`), then reference its ID from `conversation_config.agent.prompt.tool_ids`. ([Client tools](https://elevenlabs.io/docs/eleven-agents/customization/tools/client-tools))
2. **Delivery on the wire:** the server sends a `client_tool_call` message with `{tool_name, tool_call_id, parameters, event_id, expects_response}`. Over WebRTC (voice) it travels on the LiveKit reliable data channel — the Swift manager publishes with `room.localParticipant.publish(data:options: reliableDataPublishOptions)`. Over WebSocket (text-only) it uses the same event JSON. ([agent.asyncapi.yaml](https://github.com/elevenlabs/elevenlabs-swift-sdk/blob/v3.3.1/Sources/ElevenLabs/Internal/Protocol/schemas/agent.asyncapi.yaml), [WebRTCConnectionManager.swift](https://github.com/elevenlabs/elevenlabs-swift-sdk/blob/v3.3.1/Sources/ElevenLabs/Internal/Networking/WebRTCConnectionManager.swift))
3. **Handling on iOS:**

```swift
for await calls in conversation.$pendingToolCalls.values {
    for call in calls {                       // ClientToolCallEvent
        let params = (try? call.getParameters()) ?? [:]   // [String: Any]
        switch call.toolName {
        case "logMessage": print(params["message"] ?? "")
        default: break
        }
        if call.expectsResponse {
            try? await conversation.sendToolResult(for: call.toolCallId, result: ["status": "ok"])
        } else {
            conversation.markToolCallCompleted(call.toolCallId)
        }
    }
}
```

Symbols: `conversation.$pendingToolCalls` / `Conversation.pendingToolCalls`, `ClientToolCallEvent{toolName, toolCallId, parametersData, eventId, expectsResponse}` + `getParameters() throws -> [String: Any]`, `Conversation.sendToolResult(for:result:isError:errorType:)`, `Conversation.markToolCallCompleted(_:)`, `ConversationConfig.onUnhandledClientToolCall`, and the outbound `client_tool_result{tool_call_id, result, is_error}` message ([Conversation.swift](https://github.com/elevenlabs/elevenlabs-swift-sdk/blob/v3.3.1/Sources/ElevenLabs/Public/Conversation/Conversation.swift), [IncomingEvents.swift](https://github.com/elevenlabs/elevenlabs-swift-sdk/blob/v3.3.1/Sources/ElevenLabs/Public/ElevenLabs/Events/IncomingEvents.swift), [agent.asyncapi.yaml](https://github.com/elevenlabs/elevenlabs-swift-sdk/blob/v3.3.1/Sources/ElevenLabs/Internal/Protocol/schemas/agent.asyncapi.yaml)).

> **Stale documentation warning:** the official client-tools page still shows a pre-3.x Swift API — `var clientTools = ElevenLabsSDK.ClientTools()` and `ElevenLabsSDK.ClientToolError.invalidParameters` — which is the v1 SDK surface with a `ClientTools` registry. **v3.3.1 has no such registration API**; the `ClientToolCallEvent` observer pattern above is what the tagged README and `Documentation/Usage.md` document. Do not copy the docs-page Swift snippet ([client-tools docs](https://elevenlabs.io/docs/eleven-agents/customization/tools/client-tools), [README](https://github.com/elevenlabs/elevenlabs-swift-sdk/blob/v3.3.1/README.md), [Usage.md](https://github.com/elevenlabs/elevenlabs-swift-sdk/blob/v3.3.1/Documentation/Usage.md)).

**Limits (documented or source-verified):**

- The tool must be pre-registered in the agent config before the app can ever receive it; the client cannot propose new tools at runtime. Tool and parameter names are **case-sensitive** and must match the agent configuration exactly. ([client-tools docs](https://elevenlabs.io/docs/eleven-agents/customization/tools/client-tools))
- Client tools only fire while a conversation is active; with no observer they surface through `onUnhandledClientToolCall`.
- `expects_response: false` tools must be acknowledged with `markToolCallCompleted(_:)` rather than a result.
- The deprecated `sendToolResult(for:result: Any, ...)` overload is annotated *"the Any overload can send a result the agent can't parse"* — use the `some Encodable` or `String` overloads ([Conversation.swift](https://github.com/elevenlabs/elevenlabs-swift-sdk/blob/v3.3.1/Sources/ElevenLabs/Public/Conversation/Conversation.swift)).
- **No documented timeout** for how long the agent waits for a client tool result — **unverified**.
- Behaviour when several clients are attached to the same conversation (fan-out vs. single delivery) is **not documented** on any page I could reach — **unverified**.

### Server-side (webhook) tool calls

- Configured entirely in the agent: URL, headers, path parameters (`{id}` syntax), body parameters, query parameters, content type (JSON default, or `application/x-www-form-urlencoded`), dynamic-variable assignment from the response, and auth via custom headers or auth connections. ElevenLabs calls your endpoint **server to server**; the iOS client never sees the request or the credentials. ([Webhook tools](https://elevenlabs.io/docs/eleven-agents/customization/tools/webhook-tools), [Custom LLM auth/`api_key` schema](https://api.elevenlabs.io/openapi.json))
- The iOS SDK does surface informational events about them — `AgentToolRequestEvent{toolName, toolCallId, toolType, eventId}` (via `onAgentToolRequest`) and `AgentToolResponseEvent{toolName, toolCallId, toolType, isError, eventId}` (via `onAgentToolResponse`) — but these are notifications, not a dispatch/handling mechanism ([IncomingEvents.swift](https://github.com/elevenlabs/elevenlabs-swift-sdk/blob/v3.3.1/Sources/ElevenLabs/Public/ElevenLabs/Events/IncomingEvents.swift)).
- Third mechanism: **MCP** tools, surfaced to the app for approval via `conversation.mcpToolCalls` (`MCPToolCallEvent` with state `.awaitingApproval`) and answered with `sendMCPToolApproval(toolCallId:isApproved:)` ([Usage.md](https://github.com/elevenlabs/elevenlabs-swift-sdk/blob/v3.3.1/Documentation/Usage.md)).

---

## 6. Claims I could NOT verify

1. **Custom LLM auth header name/prefix.** The schema exposes `api_key` and `request_headers`, and `auth_connection` is documented as Bearer-only, but no ElevenLabs page states which header the `api_key` secret is injected as. `Authorization: Bearer <key>` is a strong inference from the provider guides, not a verified statement. ([OpenAPI](https://api.elevenlabs.io/openapi.json), [Custom LLM docs](https://elevenlabs.io/docs/eleven-agents/customization/llm/custom-llm))
2. **WebRTC conversation-token TTL/expiry.** Not stated on the `/token` endpoint page or in the agent-authentication guide (only the signed URL's 15-minute expiry is documented). ([token ref](https://elevenlabs.io/docs/eleven-agents/api-reference/conversations/get-webrtc-token))
3. **Whether `GET /v1/convai/conversation/token` requires `xi-api-key`.** The OpenAPI entry declares `security: null` and its examples omit the header; the requirement is inferred from the global API-key policy only.
4. **Which query parameter the signed URL uses** (`conversation_signature` vs `token`) — the two official pages disagree.
5. **The LiveKit version a fresh `swift package resolve` will actually pick.** Only inferable: the constraint is `from: "2.10.0"` and the newest 2.x is 2.16.0; I did not run a resolve, so the resolved pin and any lockfile outcome are unconfirmed.
6. **Whether the SDK forwards `participantName` anywhere useful.** Source shows it is stored but unused and not sent to `/token`; I could not find any docs describing its effect. Documented as observed-in-source, not as an ElevenLabs statement.
7. **Client-tool call timeout / retry semantics.** No documented wait window for a client tool result, and no documented behaviour if the client never replies.
8. **Multi-client client-tool delivery semantics.** Whether a `client_tool_call` is fanned out to every connected client or delivered to one is not documented on the client-tools page or the JS/Python/WebSocket library pages.
9. **Normative status of the `custom_llm_extra_body` → `elevenlabs_extra_body` rename.** Shown by example in docs and by the AsyncAPI schema field name; not stated as a contract.
10. **`api_type: "websocket"` custom LLM behaviour.** Present in the OpenAPI `CustomLLMAPIType` enum but not described by any documentation page I could reach.
11. **`latestAudioEvent` / `latestAudioAlignment` / `agentState` transition semantics** (timing, guarantees, whether `.thinking` is emitted for every tool call) — the properties exist in source but their behavioural contract is not documented.
12. **v4.0.0-alpha.1 API differences.** It is a prerelease (tagged 2026-09-01) adding an `ElevenLabsWidget` library in `Package.swift`; I did not diff its public API surface. Do not pin it.

### Tooling limitation for this research

The `web_search` tool was unavailable in this session (the search endpoint returned `HTTP 401 Authentication Fails`). All findings above come from direct `web_fetch`/HTTP retrieval of primary sources: the GitHub REST API, `raw.githubusercontent.com` at the `v3.3.1` tag, `https://api.elevenlabs.io/openapi.json`, and the Fern-hosted docs `.md` variants under `https://elevenlabs.io/docs/...`. Claims that would have required general web search (community reports, issue threads) are listed as unverified above rather than guessed.
