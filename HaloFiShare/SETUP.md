# HaloFiShare — share-extension target setup (one-time, in Xcode)

The extension's source, Info.plist and entitlements are in this folder. Xcode
targets cannot be added safely by editing `project.pbxproj` by hand, so the
target itself is created in Xcode:

1. Open `Halo-fi-IOS.xcodeproj`. File → New → Target… → iOS → **Share Extension**.
   Product Name: `HaloFiShare`. Language: Swift. Embed in `Halo-fi-IOS`.
   Bundle identifier must be `com.Halofiapp.HaloFiShare`. Do NOT activate the
   scheme when asked (not needed).
2. Delete the generated `ShareViewController.swift`, `Info.plist` and
   `MainInterface.storyboard` from the new group. Drag these three files from
   `frontend/HaloFiShare/` into the `HaloFiShare` group, target membership
   **HaloFiShare only**:
   - `ShareViewController.swift`
   - `Info.plist` (set it as the target's Info.plist in Build Settings →
     `INFOPLIST_FILE`, and remove `NSExtensionMainStoryboard` if Xcode added it)
   - `HaloFiShare.entitlements` (Build Settings → `CODE_SIGN_ENTITLEMENTS`)
3. Signing & Capabilities, **both** targets (`Halo-fi-IOS` and `HaloFiShare`):
   add **App Groups** → `group.com.Halofiapp`. The app's entitlements file
   already lists it; Xcode will register the group on the App ID under team
   3TB8D2484F and regenerate the provisioning profiles.
4. Set the extension's deployment target to 18.2 to match the app.
5. Build the app scheme. Then on a device: open Mail → an Uber receipt →
   share the image or PDF → **HaloFi** → the app opens on the Budget tab with
   the log form and the receipt attached.

How it works: the extension has no auth token (the app's keychain items are
`ThisDeviceOnly` with no access group), so it never uploads. It writes the
file to the App Group inbox (`ReceiptInbox/`) and opens
`halofi://receipt?file=<name>`; the app consumes the file, uploads it via
`POST /ssi/receipts`, and opens `SSILogManualDeductionView` with it attached
(see `Services/Receipts/SharedReceiptInbox.swift`).
