# AI Usage Pace

[한국어](README.md) | English

AI Usage Pace is a macOS menu bar app that displays usage for Cursor, Grok, and ChatGPT (Codex). It analyzes your usage patterns to show your current usage pace and estimated depletion time.

## Features

- View usage for Cursor, Grok Bot, Grok CLI, and Codex in one place.
- Analyze monthly and weekly limits according to their respective reset cycles.
- See the confidence level of the usage pace and estimated depletion time as `Low`, `Medium`, or `High`.
- Hover over the usage pace or estimated depletion time to see how it was calculated and why.
- Use the app in Korean or English, with dates and numbers formatted for the selected language.

## Requirements

- macOS 14 or later
- Xcode 16 or later

There are no external Swift Package Manager dependencies.

## Running the App

1. Sign in to the Cursor app, or run `grok login` or `codex login` in the CLI you want to use. You only need to sign in to the services you use.
2. Open `AIUsagePace.xcodeproj` in Xcode.
3. Select the `AIUsagePace` scheme and run the app.

In the menu bar, open `Settings…` and set `Language` to `System Default`, `English`, or `한국어`. The selected language is immediately applied to the menu bar, usage metrics, error messages, settings, dates, and numbers. The selection is stored in `appLanguage`.

When `System Default` is selected, the app uses Korean if the system language is Korean and English for all other system languages.

## Supported Usage

The current version supports only individual accounts whose response structures have been validated with test fixtures.

- Monthly: Cursor Models, Other Models
- Weekly: Grok Bot, Grok CLI, Codex Weekly
- Short session: Codex Session

If you are signed in to only some of Cursor, Grok CLI, and Codex, usage for those services will still be displayed normally. Cursor Models and Other Models remain available even if the app cannot retrieve Grok Bot usage.

## How Predictions Work

Usage pace is the projected usage by the reset time divided by the amount currently remaining. A value of `1.0×` means that, if the current pattern continues, the limit is expected to run out around the reset time.

During the first 24 hours after the app is launched for the first time, it displays a provisional prediction based on average usage since the beginning of the current cycle. To avoid extrapolating a small amount of early data too aggressively across the full cycle, the measured usage pace is blended with a neutral `1.0×` value. The prediction confidence is shown as `Low` during this period.

Once enough history has been collected, the app automatically switches to pattern-based predictions.

- Cursor Models and Other Models use the current month's usage patterns by day of the week and time of day.
- Grok Bot, Grok CLI, and Codex Weekly blend the current week's pattern with up to eight recent weekly cycles when previous history is available. More recent history receives greater weight.
- Projected usage is accumulated in 15-minute intervals until the reset time. The first interval in which the accumulated usage reaches the remaining amount becomes the estimated depletion time.
- Long gaps in observations or large differences in usage between cycles lower the confidence level.

Hover over or click the information icon next to the usage pace or estimated depletion time to see the confidence level, calculation details, observation period, and number of previous cycles included.

The app refreshes usage every 15 minutes. It also refreshes when your Mac wakes from sleep or when you select `Refresh`. Even when refresh intervals are irregular, the app normalizes usage into 15-minute buckets based on elapsed time when making predictions.

The menu bar displays the usage pool with the highest ratio of actual usage pace to recommended pace. If that ratio cannot be calculated, it displays the pool with the highest current usage percentage. The icon identifies the provider of that usage pool: Cursor, Grok, or Codex.

## Unsupported Cases

- Team and enterprise plans, as well as unlimited accounts, are not supported.
- Account types or usage cycles whose response structures have not been validated may not be displayed.
- Prepaid usage, Management API usage, API key usage, credit balances, and spending limits are not displayed.
- If the server does not provide a reset time, the app does not estimate one.
- Short usage cycles may not provide enough data to learn a pattern, so the app may continue to show a low-confidence provisional prediction.
- An in-app sign-in screen and Mac App Store distribution are not supported.

## Privacy

### Authentication Data Read Locally

The app reads only the following local authentication data when refreshing usage.

| Service | File | Values read |
| --- | --- | --- |
| Cursor · Grok Bot | Cursor's `state.vscdb` | `cursorAuth/accessToken` |
| Grok CLI | `~/.grok/auth.json` | `key` or `access_token` |
| Codex | `~/.codex/auth.json` | `tokens.access_token`, `tokens.account_id` |

If `tokens.account_id` is missing for Codex, the app uses the `chatgpt_account_id` claim from the access token. It does not read `tokens.id_token`, `tokens.refresh_token`, or `OPENAI_API_KEY`.

The app also does not read:

- `refreshToken` or `refresh_token`
- Stripe membership information or tracking databases
- Chat or project files
- Email addresses or names

The app does not store authentication tokens separately in Keychain, copy or modify the Cursor database or any `auth.json` file, or refresh authentication tokens itself.

If your Grok CLI session expires, run `grok login` again. If your Codex access token expires, the app displays `Session expired` until the Codex CLI refreshes the token.

### Network Requests

Network requests are restricted to the following endpoints:

```text
GET  https://cursor.com/api/usage-summary
POST https://cursor.com/api/dashboard/get-sand-usage-status
GET  https://cli-chat-proxy.grok.com/v1/billing?format=credits
GET  https://chatgpt.com/backend-api/wham/usage
```

Grok Bot requests use `Cookie: WorkosCursorSessionToken` and `Origin: https://cursor.com`. Codex requests use `Authorization: Bearer` and, when required, `ChatGPT-Account-Id`.

The app enforces HTTPS connections and a host allowlist. Redirect destinations are validated against the allowlist as well. HTTP request and response bodies and headers are not written to logs.

### Usage History

Usage history is stored as JSON Lines at:

```text
~/Library/Application Support/AIUsagePace/history/<fingerprint>.jsonl
```

The `fingerprint` is created by hashing the JWT `sub` value with SHA-256, so it contains neither an email address nor an authentication token. Usage pools belonging to the same account share a `fingerprint`, while history for different accounts is stored in separate files.

## Testing

Run the full test suite with:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project AIUsagePace.xcodeproj -scheme AIUsagePace -destination 'platform=macOS' test
```

If the active developer directory is set to Command Line Tools, set `DEVELOPER_DIR` as shown above.

## Distribution

The project does not currently use App Sandbox and does not support Mac App Store distribution. Debug builds use local ad hoc signing.

Release builds are configured for direct distribution through GitHub Releases after being signed with a `Developer ID Application` certificate and notarized. To create a Release build, configure a distribution certificate in your local environment or CI.

## Troubleshooting

The following messages may appear in the Xcode console:

```text
com.apple.linkd.autoShortcut
Error registering app with intents framework
```

These messages may occur while macOS automatically registers App Intents and shortcuts in a local run environment. AI Usage Pace does not use App Intents. You can ignore these messages if the menu bar features work normally.

## License

This project is licensed under the [MIT License](LICENSE).
