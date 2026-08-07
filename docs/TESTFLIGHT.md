# Getting Rerack onto your phone via TestFlight

Written for the first upload. After the first one, only steps 5–7 repeat.

## What I can and can't do for you

**I can't** complete this end to end. Three of these steps require authenticating to your Apple Developer account, which I have no credentials for and shouldn't have. Specifically: registering the App ID, creating the App Store Connect record, and the upload itself.

**What I've done:** made sure the project archives cleanly, versioning is set up, and the entitlements are correct so none of the below fails halfway through for a reason you'd have to debug.

**Time:** ~15 minutes the first time, ~3 minutes for every build after.

---

## Step 0 — What you need

- Your paid Apple Developer Program membership (you have this)
- Xcode signed in to that Apple ID: **Xcode → Settings → Accounts** → confirm your account is listed and shows your team

---

## Step 1 — Register the App ID

Bundle ID: **`com.mudit.logbook`**

Xcode can do this automatically (Step 3 handles it), but doing it manually first avoids a confusing mid-archive failure:

1. [developer.apple.com/account/resources/identifiers](https://developer.apple.com/account/resources/identifiers) → **+**
2. **App IDs** → **App** → Continue
3. Description: `Rerack`. Bundle ID: **Explicit** → `com.mudit.logbook`
4. Under Capabilities, tick **App Groups**
5. Register

## Step 2 — Register the App Group

This one bites if skipped — the app stores its database in a shared App Group container so the future Live Activity widget (M6) can read it. Without this registered, archiving fails on an entitlement error.

1. [developer.apple.com/account/resources/identifiers](https://developer.apple.com/account/resources/identifiers) → **+** → **App Groups**
2. Description: `Rerack Shared`. Identifier: **`group.com.mudit.logbook`**
3. Register
4. Go back to your App ID from Step 1 → edit → **App Groups** → Configure → tick `group.com.mudit.logbook` → Save

## Step 3 — Set your team in Xcode

```bash
cd "/Users/mudit/Developer/iOS APPS/01. Weight Tracking" && xcodegen generate && open Rerack.xcodeproj
```

In Xcode: select the **Rerack** target → **Signing & Capabilities** → tick **Automatically manage signing** → pick your **Team** from the dropdown.

Xcode will generate the provisioning profile. If it shows an error about the App Group, click **Try Again** — it usually resolves once Steps 1–2 are done.

> Once you know your Team ID, tell me and I'll add it to `project.yml` so this step stops being manual on future regenerations.

## Step 4 — Create the App Store Connect record

1. [appstoreconnect.apple.com/apps](https://appstoreconnect.apple.com/apps) → **+** → **New App**
2. Platform: **iOS**
3. Name: `Rerack` — ⚠️ this must be globally unique across the App Store. If it's taken, pick another from **PRD Appendix A.2** (Ironclad, Whetstone, Sinew, Pig Iron, Sisyphus all came back clear). The *display* name is trivially changeable later (Appendix A.0) — only the bundle ID is permanent.
4. Primary Language: English
5. Bundle ID: select **`com.mudit.logbook`**
6. SKU: `rerack-001` (internal only, never shown to anyone)
7. Create

---

## Step 5 — Archive

In Xcode:

1. Set the run destination to **Any iOS Device (arm64)** — *not* a simulator. Archive is greyed out otherwise, which is the single most common "why can't I archive" moment.
2. **Product → Archive**
3. Wait for the build. The Organizer window opens when it's done.

## Step 6 — Upload

In the Organizer:

1. Select the archive → **Distribute App**
2. **TestFlight & App Store** → Next
3. **Upload** → Next
4. Accept the defaults for signing/symbols → **Upload**

Processing on Apple's side takes ~5–15 minutes. You'll get an email when it's ready.

## Step 7 — Install on your phone

1. Install **TestFlight** from the App Store on your iPhone
2. In App Store Connect → your app → **TestFlight** tab
3. Under **Internal Testing**, create a group and add yourself (you're already a team member, so no review needed and it's available immediately)
4. Open TestFlight on your phone → install

> **Internal testing needs no App Review.** Builds are available within minutes of processing. External testing (other people) does require a review, but you don't need that yet.

---

## For subsequent builds

Only Steps 5 and 6. But bump the build number first or the upload is rejected as a duplicate:

```bash
cd "/Users/mudit/Developer/iOS APPS/01. Weight Tracking" && sed -i '' 's/CURRENT_PROJECT_VERSION: "\([0-9]*\)"/CURRENT_PROJECT_VERSION: "'$(($(grep -o 'CURRENT_PROJECT_VERSION: "[0-9]*"' project.yml | grep -o '[0-9]*')+1))'"/' project.yml && xcodegen generate && grep CURRENT_PROJECT_VERSION project.yml
```

`MARKETING_VERSION` (the user-facing `1.0`) only needs bumping for a meaningful release. `CURRENT_PROJECT_VERSION` must increase on *every* upload.

---

## Things that commonly go wrong

| Symptom | Cause | Fix |
|---|---|---|
| Archive is greyed out | Destination is a simulator | Set to **Any iOS Device (arm64)** |
| `Provisioning profile doesn't include com.apple.security.application-groups` | App Group not registered or not attached to the App ID | Redo Step 2, then in Xcode: Signing & Capabilities → **Try Again** |
| Upload rejected: build already exists | `CURRENT_PROJECT_VERSION` unchanged | Bump it (see above) and re-archive |
| App name already taken | Someone has it on the App Store | Pick from PRD Appendix A.2; only the bundle ID is permanent |
| Xcode has no Team in the dropdown | Not signed in | Xcode → Settings → Accounts → **+** |

---

## Optional: automating this later

If you ever want the upload scripted rather than clicked, create an **App Store Connect API key** ([appstoreconnect.apple.com/access/integrations/api](https://appstoreconnect.apple.com/access/integrations/api), Developer role is enough), save the `.p8` to `~/.appstoreconnect/private_keys/`, and `xcodebuild -exportArchive` plus `xcrun altool` can then run headlessly. Worth doing once you're uploading regularly; not worth it for the first build.
