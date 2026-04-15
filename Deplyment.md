Here is the complete process from start to finish.

***

## Prerequisites

You need an **Apple Developer Program membership** ($99/year) at [developer.apple.com](https://developer.apple.com). This is required to obtain a Developer ID certificate and use notarization services. [developer.apple](https://developer.apple.com/developer-id/)

***

## Step 1: Create a Developer ID Certificate

1. Log into [developer.apple.com](https://developer.apple.com) → **Certificates, IDs & Profiles** → **Certificates** → click **+**
2. Select **Developer ID Application** (this is for signing app bundles; not the same as the Mac App Store certificate) [lcfmlessons.livecode](https://lcfmlessons.livecode.com/a/1966576-signing-and-notarizing-your-app-mac)
3. Follow the CSR generation flow — Xcode can do this automatically if you let it manage signing
4. Alternatively, in **Xcode → Settings → Accounts**, sign in with your Apple ID and click **Manage Certificates → + → Developer ID Application** — Xcode will create and install the certificate into your Keychain automatically [gist.github](https://gist.github.com/rsms/929c9c2fec231f0cf843a1a746a416f5)

***

## Step 2: Xcode Project Configuration

### Signing & Capabilities tab

- Set **Team** to your developer account team
- Set **Signing Certificate** to **Developer ID Application**
- **Uncheck "Automatically manage signing"** if you want explicit control, or leave it checked and Xcode handles certificate selection for you
- Make sure **no App Sandbox** entitlement is enabled — sandboxing is incompatible with your Accessibility usage and is *not* required outside the App Store [developer.apple](https://developer.apple.com/forums/thread/716727)

### Hardened Runtime

Enable **Hardened Runtime** — it is **mandatory** for notarization. In Xcode: [wiki.freepascal](https://wiki.freepascal.org/Hardened_runtime_for_macOS)

- Go to **Signing & Capabilities** → click **+ Capability** → add **Hardened Runtime**

Since your app uses Accessibility APIs under Hardened Runtime, you must explicitly declare an entitlement. Add this to your `.entitlements` file: [jano](https://jano.dev/apple/macos/swift/2025/01/08/Accessibility-Permission.html)

```xml
<key>com.apple.security.cs.disable-library-validation</key>
<false/>
```

Hardened Runtime on its own does not block Accessibility usage — the Accessibility permission is a user-granted TCC (Transparency, Consent & Control) permission, not an entitlement. But you do need to add to `Info.plist`:

```xml
<key>NSAccessibilityUsageDescription</key>
<string>WindowMate needs accessibility access to move and resize windows from other applications.</string>
```

This string appears in the system permission prompt shown to the user. [jano](https://jano.dev/apple/macos/swift/2025/01/08/Accessibility-Permission.html)

### Build Settings

- Set **Deployment Target** to the minimum macOS version you support
- Ensure **Code Signing Style** is set to **Manual** or **Automatic** consistently — mixing them causes signing failures at archive time

***

## Step 3: Archive the App

In Xcode:

1. Select **Any Mac (Apple Silicon, Intel)** or a specific architecture as the run destination — not a simulator
2. **Product → Archive**
3. Xcode builds a release archive and opens the **Organizer** window

***

## Step 4: Export with Developer ID

In the Organizer:

1. Select your archive → **Distribute App**
2. Choose **Direct Distribution** (previously called "Developer ID")
3. Choose **Upload** if you want Xcode to notarize automatically (recommended), or **Export** if you want to notarize manually via CLI
4. Confirm signing identity is **Developer ID Application**
5. Xcode uploads the binary to Apple's notarization service and waits for approval — this typically takes **a few minutes** [lessons.livecode](https://lessons.livecode.com/a/1653720-code-signing-and-notarizing-your-lc-standalone-for-distribution-outside-the-mac-appstore-with-xcode-13-and-up)
6. Once approved, Xcode staples the notarization ticket to your `.app` bundle automatically

***

## Step 5: Manual Notarization (CLI Alternative)

If you export the app and notarize manually, use `notarytool` (part of Xcode command-line tools). `altool` was deprecated in November 2023. [docs.unity3d](https://docs.unity3d.com/2022.3/Documentation/Manual/macosnotarizationxcode.html)

**First, store your credentials once (saves them to Keychain):**

```bash
xcrun notarytool store-credentials "notarytool-profile" \
  --apple-id "your@apple-id.com" \
  --team-id "YOUR_TEAM_ID" \
  --password "app-specific-password"
```

The `app-specific-password` is generated at [appleid.apple.com](https://appleid.apple.com) — it is *not* your normal Apple ID password. [iridium-works](https://www.iridium-works.com/en/blog-post/making-macos-app-bundles-signing-notarizing)

**Zip the app and submit:**

```bash
ditto -c -k --keepParent MyApp.app MyApp.zip

xcrun notarytool submit MyApp.zip \
  --keychain-profile "notarytool-profile" \
  --wait
```

The `--wait` flag blocks until Apple responds (usually under 5 minutes). [lessons.livecode](https://lessons.livecode.com/a/1653720-code-signing-and-notarizing-your-lc-standalone-for-distribution-outside-the-mac-appstore-with-xcode-13-and-up)

**Staple the ticket to the app** so it passes Gatekeeper checks even offline:

```bash
xcrun stapler staple MyApp.app
```

**Verify everything is correct:**

```bash
spctl --assess --type execute --verbose MyApp.app
# Should output: MyApp.app: accepted (source=Notarized Developer ID)
```

***

## Step 6: Package for Distribution

You have two standard options:

| Package Type | Use case | Signing cert needed |
|---|---|---|
| **DMG** | Drag-to-Applications style install | Developer ID Application (sign the DMG too) |
| **PKG installer** | Scripted install, Launch Agent setup | Developer ID Installer |

For a simple drag-install DMG, create the disk image, then sign and notarize it the same way as the `.app`:

```bash
codesign --sign "Developer ID Application: Your Name (TEAMID)" MyApp.dmg
xcrun notarytool submit MyApp.dmg --keychain-profile "notarytool-profile" --wait
xcrun stapler staple MyApp.dmg
```

***

## Step 7: Handling the Accessibility Permission at Runtime

Since your app requires Accessibility access, prompt the user clearly on first launch. The correct pattern in Swift:

```swift
let trusted = AXIsProcessTrustedWithOptions(
    [kAXTrustedCheckOptionPrompt: true] as CFDictionary
)
if !trusted {
    // Show your own onboarding UI explaining why it's needed,
    // then open System Settings directly:
    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    NSWorkspace.shared.open(url)
}
```

**Recommendation:** Don't rely solely on the system prompt. Build an onboarding screen that explains the permission in plain language before calling `AXIsProcessTrustedWithOptions`. Monitor for the permission being granted by polling with a short timer, then dismiss the onboarding automatically when access is confirmed. [jano](https://jano.dev/apple/macos/swift/2025/01/08/Accessibility-Permission.html)

***

## Step 8: Updates

For future updates, repeat Steps 3–6 for each new version. Since you sign with a stable Developer ID certificate, **macOS recognizes your app as the same identity across updates** — users do not lose their Accessibility permission grant when they update. You are responsible for distributing updates yourself (e.g., via [Sparkle](https://sparkle-project.org/), a popular open-source auto-update framework used by most non-App Store Mac apps). [jano](https://jano.dev/apple/macos/swift/2025/01/08/Accessibility-Permission.html)
