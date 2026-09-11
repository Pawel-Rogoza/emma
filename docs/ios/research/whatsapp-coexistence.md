# WhatsApp Cloud API + WhatsApp Business App Coexistence — Provider Research

Scope: connecting a law firm's EXISTING WhatsApp Business App number to the WhatsApp Cloud API **without** unregistering/deleting/migrating that number. All facts below are from Meta official documentation unless marked **unverified**.

Method note: Meta's developer docs are client-rendered; raw Markdown is retrievable by appending `.md/` to a `/documentation/...` URL.

---

## 1. Coexistence: official support and onboarding

### Official Meta documentation pages

| Purpose | URL |
|---|---|
| Primary coexistence page ("Onboard WhatsApp Business app users") — onboarding flow, requirements, limitations, webhooks | https://developers.facebook.com/documentation/business-messaging/whatsapp/embedded-signup/onboarding-business-app-users/ |
| Reconnect / offboarded coexistence clients | https://developers.facebook.com/documentation/business-messaging/whatsapp/embedded-signup/reconnect-offboarded-coexistence-clients/ |
| Embedded Signup versions (v2 → v4 upgrade path) | https://developers.facebook.com/documentation/business-messaging/whatsapp/embedded-signup/versions/ |
| Embedded Signup overview | https://developers.facebook.com/documentation/business-messaging/whatsapp/embedded-signup/overview |
| Coexistence "custom flow" page (listed in search results) | https://developers.facebook.com/documentation/business-messaging/whatsapp/embedded-signup/coexistence/ — **page returned HTTP 200 but rendered no body content via two independent fetchers; its text is unverified** |

**Official confirmation of support (quote):** "You can configure Embedded Signup to allow business customers to onboard using their existing WhatsApp Business app account and phone number. After a business customer chooses this option and onboards successfully, they can use your app to send high volumes of messages. They can still send messages on a one-to-one basis using the WhatsApp Business app, and WhatsApp keeps messaging history between both apps in sync."

The page also states: "This feature is sometimes referred to as 'Coexistence' in support channels and Partner documentation." — i.e. **"coexistence" is not the official doc title**; the official title is "Onboard WhatsApp Business app users".

### Onboarding flow steps (as documented)

1. Partner configures Embedded Signup with feature type `whatsapp_business_app_onboarding` (via the `extras` object). Documented values: `featureType: "whatsapp_business_app_onboarding"` (see Versions page).
2. Business customer enters their WhatsApp Business app phone number in the Embedded Signup flow.
3. WhatsApp presents a verification code inside the WhatsApp Business app.
4. Business taps **Connect** in the message from the official Facebook Business Account.
5. Business taps **Connect to the Business Platform**.
6. Business taps **Confirm** to opt in (or out) of sharing chat history.
7. Business pastes the verification code.
8. Flow returns asset IDs and an exchangeable token code; the session event sets `event` to `FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING`.
9. Partner onboards the customer **but skips the phone number registration step** — "as the number is already registered".
10. Within **24 hours** the partner must synchronize contacts and message history, otherwise the customer must be offboarded and must complete the flow again.
11. Sync steps: (a) `POST /<BUSINESS_PHONE_NUMBER_ID>/smb_app_data` with `{"messaging_product":"whatsapp","sync_type":"smb_app_state_sync"}` for contacts; (b) same endpoint with `"sync_type":"history"` for message history. **Each of these can only be performed once**; repeating requires offboarding and redoing Embedded Signup.
12. Optional verification: `GET https://graph.facebook.com/v25.0/<PHONE_NUMBER_ID>?fields=is_on_biz_app,platform_type` — `is_on_biz_app: true` + `platform_type: "CLOUD_API"` confirms dual use.

### Prerequisites (official "Requirements" list, quoted)

- "The business customer must use WhatsApp Business app version **2.24.17** or higher."
- "You must already be a **Solution Partner** or **Tech Provider**."
- "You must know how to use Cloud API."
- "Your webhook callback must be able to successfully accept and digest webhooks."
- "You must use Embedded Signup with **session logging**."

Additional platform-level prerequisites:

- A **business portfolio** is required: "You must have a business portfolio to use the platform" (About the WhatsApp Business Platform).
- A **WABA** (WhatsApp Business Account) contains phone numbers: "A WhatsApp Business account represents your business and contains phone numbers, usernames, and analytics."
- Webhook subscription must include the extra fields `history`, `smb_app_state_sync`, and `smb_message_echoes`, "in addition to any fields you are already subscribed to as a partner".

**Admin-role prerequisite: UNVERIFIED.** No official statement was found requiring a specific business-portfolio admin role for coexistence onboarding. (Business portfolio admin is documented only for *deleting* phone numbers.)

### Stated limitations (official, quoted)

- "To remain compatible with the WhatsApp Business app, business phone numbers that are in use with both the WhatsApp Business app and Cloud API have a **fixed throughput of 20 mps**."
- "If your business customer worked with a partner in the past and still shares the previous credit line, they may see an error when attempting to switch to a new partner."
- **Embedded Signup versioning:** "Embedded signup v2 will be deprecated on **October 15, 2026**. Migrate your integration to v4 before that date to avoid disruption." Latest ES version is `v4`.
- Offboarding: "You cannot use the **Deregister API** to deregister a business phone number from Cloud API if it is already in use with both Cloud API and the WhatsApp Business app." Disconnection instead happens client-side via WhatsApp Business app → **Settings > Account > Business Platform > Disconnect Account**.
- Offboard triggers a `PARTNER_REMOVED` `account_update` webhook; documented `disconnection_info.reason` values include `PRIMARY_INACTIVITY` ("primary device inactive for approximately 14 days") and `COMPANION_INACTIVITY` ("companion device inactive for approximately 30 days").
- Known error: `unsupported messages` webhook with error code `131060` can occur on first-time messaging or from unsupported companion devices.

### Partner dependency (practical blocker)

Because the documented requirement is "You must already be a Solution Partner or Tech Provider", **coexistence is not documented as a self-serve option for an ordinary Cloud API developer**. Whether Meta now allows a direct/self-serve coexistence onboarding without a BSP is **UNVERIFIED** (only community-forum threads raise this question; no official self-serve procedure was found).

---

## 2. What happens to the existing number and app

**The owner keeps using the Business App.** Official: "They can still send messages on a one-to-one basis using the WhatsApp Business app, and WhatsApp keeps messaging history between both apps in sync." After onboarding, "the WhatsApp Business app will automatically refresh and indicate to the business that their number is now connected to the API".

### Feature comparison table (official, abridged — "Changes to features on the WhatsApp Business App after onboarding")

| Business App feature | Change after onboarding | Supported on Cloud API? |
|---|---|---|
| Individual (1:1) chats | Message Edit/Revoke now supported | Supported. "All chat messages in the **most recent 6 months** can be synchronized." "Messages sent and received are **mirrored** between the Cloud API and WhatsApp Business app." |
| Contacts | No change | Supported. "**All contacts with a WhatsApp number** can be synchronized." |
| Group chats | No change | **Not supported.** "Group chats will not be synchronized." |
| Disappearing messages | "Disappearing messages will be **turned off** for all individual (1:1) chats" | Not supported |
| View once | "disabled for all individual (1:1) chats" | Not supported |
| Live location | "disabled for all individual (1:1) chats" | Not supported |
| Broadcast lists | "**Broadcast lists will be disabled.** Business will not be able to create new Broadcast lists. Existing Broadcast lists will become **read-only**." | Not supported |
| Voice and video calls | No change | Not supported |
| Business tools (catalog, orders, status) | No change | **Not supported** |
| Messaging tools (marketing/greeting/away messages, quick replies, labels) | No change | Not supported |
| Business profile | No change | Not supported |
| Channels | No change | Not supported |

Catalog specifics beyond "Business tools (for example, catalog, orders, status) … No change [in the Business App] / Not supported [on Cloud API]": **UNVERIFIED**.

### Message history sync/import scope (official)

- Overall: "All chat messages in the most recent **6 months** can be synchronized."
- History webhooks: describe "all messages sent or received **within 180 days** of the time when the business was onboarded onto Cloud API."
- Group-chat messages "will not be included".
- Media: "media messages **will not include media asset IDs**; instead, additional history webhooks containing media message asset IDs will be sent separately, but only for media messages sent **within 14 days of onboarding**."
- Phases: phase 0 = day 0–1; phase 1 = day 1–90; phase 2 = day 90–180. Controls: `chunk_order`, `phase` (2 = phase complete), `progress` (100 = sync complete).
- If the business declines sharing: a `history` webhook with **error code 2593109** ("History sync is turned off by the business from the WhatsApp Business App") is sent.
- Deadline: sync must start and finish within **24 hours** of onboarding or the customer must be offboarded and redo the flow.

### Messages SENT from the phone (echo events)

- Documented webhook field **`smb_message_echoes`**: "Describes a message sent by a business customer to a WhatsApp user with the WhatsApp Business app or supported companion device."
- Trigger: "A business customer uses the WhatsApp Business app or supported companion device to message a WhatsApp user."
- Payload path: `entry[].changes[].value.message_echoes[]` with `from` (business number), `to` (user number), `id` (wamid), `timestamp`, `type`, and a type-keyed contents object.
- Requirement: "Each time a business sends a message with one of these apps, it triggers an `smb_message_echoes` webhook, which you must digest and display in the contact message thread history in your app."
- Caveat: messages from an unsupported companion client "will not trigger `messages` webhooks, so the business won't be able to mirror the message in their own app."

### Linked devices

- Up to four companion clients are allowed; all are supported **except WhatsApp for Windows and WhatsApp for WearOS**.
- "Once a business customer onboards to Cloud API with an existing WhatsApp Business app account and number, **all companion apps will be unlinked** from the account, and the business can then re-link any supported companion apps."
- Messages viewed on an unsupported companion device "will appear with placeholder text".

### Offboarding risk to be aware of (device change)

"When a client onboarded via coexistence changes devices or re-registers their WhatsApp Business app, their **Cloud API companion is automatically offboarded**." Reonboarding is automatic if the client does not opt out of the pre-checked opt-in, "typically completes within a few minutes". During reonboarding: Cloud API messaging is **suspended**, WhatsApp Business app messaging is "briefly unavailable", and "Chat history: Not synced during reonboarding". Other companion devices "must be manually re-linked by your client".

---

## 3. If coexistence is NOT available for a given number

**Official alternatives found:**

1. **Separate test number (recommended for development without touching the live number).** When you complete the Get Started steps, "a **test** business phone number is generated and registered for you automatically". Test WABAs/numbers "have relaxed messaging limits and don't require a payment method on file". Documented at: https://developers.facebook.com/documentation/business-messaging/whatsapp/get-started/ and https://developers.facebook.com/documentation/business-messaging/whatsapp/business-phone-numbers/phone-numbers/
2. **Migrate the number from the Business App to Cloud API only (destructive to the app).** Official statement: "Numbers already in use with WhatsApp cannot be registered unless they are **deleted** first." — i.e. the standard registration path requires the existing WhatsApp account on that number to be deleted first. This is exactly the outcome the firm wants to avoid. (Note: the same page defines "WhatsApp" as the consumer app — "cannot be used with WhatsApp Messenger ('WhatsApp')" — so the sentence's exact scope relative to the *Business* app is slightly ambiguous; it is quoted verbatim rather than interpreted.) Source: https://developers.facebook.com/documentation/business-messaging/whatsapp/business-phone-numbers/phone-numbers/
3. **Migrate a number between WABAs / between Solution Partners via Embedded Signup** (does not preserve the Business App): https://developers.facebook.com/documentation/business-messaging/whatsapp/solution-providers/support/migrating-phone-numbers-among-solution-partners-via-embedded-signup
4. **Registering a banned number** requires the appeal process: https://faq.whatsapp.com/465883178708358

**What migration does to the existing app (official):** full registration of an in-use number requires deleting the WhatsApp account first; once registered on Cloud API the number "cannot be used with WhatsApp Messenger". Deleting a business phone number is restricted: "Only business portfolio admins can delete business phone numbers, and numbers can't be deleted if they have been used to send paid messages within the last 30 days."

**Whether coexistence can be enabled later, or revoked without offboarding, for a number that was migrated the destructive way: UNVERIFIED.**

---

## 4. Webhook / sending mechanics for a backend

### Incoming messages and status webhooks

Meta does not expose a "read" endpoint for webhooks — **Meta POSTs to your own Callback URL**. "There are no APIs for fetching historical webhook data, so capture and store webhook payloads accordingly."

- Webhook object: `whatsapp_business_account`; relevant field: `messages`. The `messages` webhook "describes messages sent from a WhatsApp user to a business and the status of messages sent by a business to a WhatsApp user."
  - Incoming messages are identifiable by a `messages` array (`entry[].changes[].value.messages[]`).
  - Outgoing status updates are identifiable by a `statuses` array (`entry[].changes[].value.statuses[]`).
- Verification handshake (GET): `GET <CALLBACK_URL>?hub.mode=subscribe&hub.challenge=<HUB.CHALLENGE>&hub.verify_token=<HUB.VERIFY_TOKEN>`; respond HTTP 200 with the `hub.challenge` value.
- Delivery POST shape: `POST <CALLBACK_URL>` with `Content-Type: application/json`, header `X-Hub-Signature-256: sha256=<SHA256_PAYLOAD_HASH>`, `Content-Length`, and the JSON body.
- Batching: "POST requests are aggregated and sent in a batch with a **maximum of 1000 updates**. However, batching cannot be guaranteed so be sure to adjust your servers to handle each POST request individually."
- Retries/dedup: "If any POST request sent to your server fails, delivery is retried immediately, then a few more times with decreasing frequency over the next 7 days. **Your server should handle deduplication in these cases.**" "Unacknowledged responses will be dropped after 7 days."
- TLS: "Your webhook endpoint server must have a valid TLS or SSL digital security certificate… Self-signed certificates are not supported." mTLS is supported (configured per-application, not per-WABA/number).
- Configuration alternative: "you can use the Application Subscriptions API to configure webhooks… use `whatsapp_business_account` as the object value." Source: https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/overview/ and https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/create-webhook-endpoint/

### Signature verification (exact algorithm)

Official validation procedure (verbatim): "1. Generate an **HMAC-SHA256** hash using the **JSON payload as the message input** and your **app secret as the secret key**. 2. Compare your generated hash to the hash assigned to the `X-Hub-Signature-256` header (**everything after `sha256=`**). If the hashes match, the payload is valid… If they do not match, consider the payload invalid."

Intent is also stated in Graph API webhooks docs: "We sign all Event Notification payloads with a SHA256 signature and include the signature in the request's `X-Hub-Signature-256` header, preceded with `sha256=`." (https://developers.facebook.com/docs/graph-api/webhooks/getting-started/)

### Business phone number ID in the payload

Both incoming and status webhooks carry it at:

`entry[].changes[].value.metadata.phone_number_id` (sibling: `metadata.display_phone_number`).

Example (official): `"metadata": { "display_phone_number": "15550783881", "phone_number_id": "106540352242922" }`. The WABA id is `entry[].id`.

### Provider message id for deduplication

- Incoming: `entry[].changes[].value.messages[].id` — e.g. `wamid.HBgLMTY1MDM4Nzk0MzkVAgASGBQzQTRBNjU5OUFFRTAzODEwMTQ0RgA=`
- Status: `entry[].changes[].value.statuses[].id` — same `wamid...` value as returned by the send API.
- Send API response returns the same id: `messages[].id`. "This ID appears in associated messages webhooks, such as sent, read, and delivered webhooks."
- Echo: `message_echoes[].id`.

### Message status values (official `<STATUS>` list)

- `sent` — "successfully sent from our servers" (one checkmark)
- `delivered` — "successfully delivered to the WhatsApp user's device" (two checkmarks)
- `failed` — "failure to send or deliver" (red triangle); carries an `errors[]` array
- `read` — "displayed in an open chat thread" (two blue checkmarks)
- `played` — "first time a voice message is played" (blue microphone)

Notes: "each outgoing message can have up to three separate webhooks (one for a status of sent, one for delivered, and one for read)"; a status "is considered read only if it has been delivered", and in some cases the `delivered` webhook is skipped because it is implied.

### 24-hour customer service window (official source)

- Canonical source: https://developers.facebook.com/documentation/business-messaging/whatsapp/messages/send-messages#customer-service-windows
- Rule (verbatim): "When a WhatsApp user messages you or calls you, a **24-hour timer called a customer service window** starts. If the user messages or calls you again before the timer expires, the timer resets to 24 hours. While the window is open, you can send any of the service message types listed below to the user. **When the window closes, you can only send pre-approved template messages.**"
- Templates are "the only type of message that can be sent to WhatsApp users outside of a customer service window."
- Coexistence-specific rule (verbatim): "The **24-hour customer service window restriction applies to messages sent via Cloud API**. Messages sent from the WhatsApp Business app are **not subject to the customer service window** and **do not create, extend, or affect** Cloud API conversation windows or Cloud API pricing."
- Coexistence timing gotcha: "WhatsApp opens a customer service window only when a WhatsApp user messages a business customer who is already onboarded onto Cloud API. If a WhatsApp user messages a business customer just before the business customer is onboarded onto Cloud API, the business customer can only respond with a template message."

### Sending endpoint

`POST https://graph.facebook.com/<API_VERSION>/<WHATSAPP_BUSINESS_PHONE_NUMBER_ID>/messages`

Body: `{"messaging_product":"whatsapp","recipient_type":"individual","to":"<USER_NUMBER>","type":"<TYPE>","<TYPE>":{...}}`. Success response only means the API "successfully accepted your request — it does not indicate successful delivery". Official example uses `v25.0`.

---

## 5. Current documented Graph API version

**`v26.0`** — verified verbatim from the official Versioning guide: "**What is the latest Graph API Version?** The latest Graph API version is `v26.0`".

Source verified at: https://developers.facebook.com/docs/graph-api/guides/versioning/
Changelog index: https://developers.facebook.com/docs/graph-api/changelog/ ; WhatsApp platform changelog: see the "Versions"/changelog section of https://developers.facebook.com/documentation/business-messaging/whatsapp/

Caveat: individual WhatsApp doc pages still show older versions in their copied examples (`v25.0` on the coexistence/phone-number pages, `v23.0` in Get Started). That is example drift, not the current version. Note also that Meta guarantees each version for at least 2 years, and a version becomes unusable 2 years after the *subsequent* version's release.

---

## 6. Claims I could NOT verify

1. **The exact body of the page https://developers.facebook.com/documentation/business-messaging/whatsapp/embedded-signup/coexistence/** — it appears in search results as a Meta page titled "Developer Platform", returns HTTP 200, but no body content could be extracted by two independent fetchers. Its content is unverified; it may be a redirect stub.
2. **Whether an exact business-portfolio *admin role*** is required for coexistence onboarding. Not stated in the coexistence requirements list.
3. **Whether coexistence can be onboarded self-serve (direct developer with no Solution Partner / Tech Provider).** Docs state you *must* be a Solution Partner or Tech Provider; whether Meta offers any non-partner path is unverified (only community threads raise it).
4. **Catalog limits under coexistence.** Docs only state "Business tools (for example, catalog, orders, status) — No change [in Business App] / Not supported [on Cloud API]". No numeric catalog or contact cap was found. (Contact sync is documented only as "All contacts with a WhatsApp number can be synchronized.")
5. **The reconciliation between "most recent 6 months" (feature table) and "within 180 days" (history webhooks).** Both are official; whether they are intended as the same figure or different is stated nowhere I found.
6. **Whether on-premises API supports coexistence** — not investigated/verified; this research is Cloud API only.
7. **Pricing specifics** beyond: "messages sent by the business via the WhatsApp Business app will continue to be free, but messages sent via Cloud API will be subject to Cloud API pricing." A Meta pricing explainer PDF is linked ("API Solutions for WhatsApp Business App Users") but its contents were not fetched.
8. **Behavior of `smb_message_echoes`/`history` for deleted or edited messages, and exact media retrieval flow for the 14-day media window** — payload fields are documented, but end-to-end media retrieval was not verified.
9. **Any official SLA on how long reonboarding takes** — only "typically completes within a few minutes".
10. **Whether the number's OBA status, quality rating, or display name changes** as a result of coexistence onboarding — not stated.

## Session/tooling limitation affecting this research

The `web_search` tool failed in this session with an authentication error (`HTTP 401`), so discovery was done via `web_fetch` against DuckDuckGo Lite (which later began returning a bot-challenge) and direct URL probing. Meta docs were read via the `.md/` Markdown endpoints and, for non-`.md` pages, via the `r.jina.ai` rendering proxy. `curl` from bash is blocked by Meta (HTTP 400) and should not be relied upon for these docs.
