# ClipShelf CloudKit Setup

ClipShelf uses private CloudKit container:

`iCloud.com.nicebro.ClipShelf`

## One-time setup (Apple Developer)

1. Open `ClipShelf.xcodeproj` in Xcode.
2. Select the **ClipShelf** target → **Signing & Capabilities**.
3. Choose your **Team** (paid Apple Developer program).
4. Ensure **Automatically manage signing** is on.
5. Confirm capability **iCloud** is present with:
   - CloudKit checked
   - Container `iCloud.com.nicebro.ClipShelf`
6. If the container is missing, click **+** under Containers and create:
   `iCloud.com.nicebro.ClipShelf`
7. Run the app from Xcode once on this Mac while signed into iCloud.
8. First successful upload creates the Development schema (`ClipboardHistory` zone + `ClipboardItem` records).
9. In [CloudKit Dashboard](https://icloud.developer.apple.com/), promote Development schema to Production before release builds.

## Local unsigned / ad-hoc builds

Ad-hoc or `CODE_SIGNING_ALLOWED=NO` builds cannot carry Apple-restricted iCloud entitlements. In that mode the Sync toggle shows a clear setup message instead of a bare entitlement error.

## Environment variable for CLI builds

```bash
export CLIPSHELF_DEVELOPMENT_TEAM=YOUR_TEAM_ID
xcodegen generate
xcodebuild -project ClipShelf.xcodeproj -scheme ClipShelf -configuration Debug build
```

Team ID is the 10-character id from [developer.apple.com/account](https://developer.apple.com/account) → Membership.
