import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Section("Refresh") {
                Text("Usage is refreshed every 15 minutes, when the Mac wakes, and when you click Refresh.")
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
        .frame(width: 420, height: 360)
    }
}
