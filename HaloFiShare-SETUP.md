# HaloFiShare — share extension

The `HaloFiShare` target is in `Halo-fi-IOS.xcodeproj` (product type
app-extension, bundle id `com.Halofiapp.HaloFiShare`, embedded in the app
target, App Group `group.com.Halofiapp` on both targets, deployment target
18.2). This folder is its synchronized source group; `Info.plist`,
`HaloFiShare.entitlements` and this file are excluded from compilation.

First device build: automatic signing registers the extension App ID and
the App Group on team 3TB8D2484F and regenerates both provisioning
profiles (`-allowProvisioningUpdates` from the command line, or Xcode).

How it works: the extension has no auth token (the app's keychain items are
`ThisDeviceOnly` with no access group), so it never uploads. It writes the
shared image or PDF to the App Group inbox (`ReceiptInbox/`) and opens
`halofi://receipt?file=<name>`; the app consumes the file, uploads it via
`POST /ssi/receipts`, and opens the work-expense log with it attached
(`Services/Receipts/SharedReceiptInbox.swift`, `WorkExpensesView`).

Device test: Mail → an Uber receipt → share the image or PDF → **HaloFi** →
the app opens on Benefits → Work expenses with the receipt attached.
