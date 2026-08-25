import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Section("Refresh") {
                Text("Usage is refreshed every 15 minutes, when the Mac wakes, and when you click Refresh.")
            }
            Section("Cursor") {
                Text("Cursor Models and Other Models come from GET https://cursor.com/api/usage-summary using Cursor’s local accessToken in state.vscdb.")
                Text("Grok Bot is a separate weekly allowance on the same Cursor account. It is read from POST https://cursor.com/api/dashboard/get-sand-usage-status with the same Cursor session cookie. It is not Grok CLI usage.")
            }
            Section("Grok CLI") {
                Text("Grok CLI weekly usage comes from ~/.grok/auth.json (`key` or `access_token`) and GET https://cli-chat-proxy.grok.com/v1/billing?format=credits. It does not use the Cursor account.")
            }
            Section("Privacy") {
                Text("This app reads only Cursor’s local accessToken from state.vscdb and Grok CLI’s access token (`key`) from ~/.grok/auth.json. It does not read refresh tokens, copy those files, or store credentials.")
                Text("Usage history is percent values in Application Support, keyed by a hash of the account id—not email or the token.")
            }
            Section("Distribution") {
                Text("App Sandbox is off, so this build is not for the Mac App Store. Distribute with Developer ID signing and notarization.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 520)
    }
}
