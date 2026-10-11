# K Guard (NFC Patrol Check-in)

Security guards check in at each patrol point by scanning an NFC tag with their phone. Check-in records are stored on the phone and sent to the owner via a Telegram Bot.

## Features
- **Check-in**: Select the guard on duty → tap **Scan checkpoint** → hold the phone near the tag. Today's patrol progress is shown (which points have been patrolled and which haven't). Scanning the same point again within 1 minute is not recorded twice.
- **Records**: View check-in records by month, and tap **Send this month to owners** to send them manually.
- **Monthly auto-send**: After the 1st of each month, the first time the app is opened (or returns to the foreground) it automatically sends last month's report to the owner. If there is no network, it retries the next time the app is opened.
- **Report contents**: A summary message (check-ins per patrol point, check-ins per guard, points not patrolled this month) plus a CSV attachment (opens directly in Excel).
- **Optional**: Notify the owner instantly on every check-in.
- **Admin settings** (protected by a Settings PIN, default `1234`): property name, checkpoint registration (scan a tag and name it), guard list, Telegram settings, change PIN.

## Installation
1. Run `sudo xcodebuild -license` once in the terminal and accept the Xcode license (otherwise `flutter` commands will fail).
2. Run `./setup.sh` to generate the Android / iOS projects and add NFC permissions.
3. Connect an Android phone to the computer and run `flutter run`, or build an APK with `flutter build apk --release`.

## Telegram Setup
1. In Telegram, find **@BotFather** and send `/newbot` to create a bot. You will get a **Bot Token**.
2. Have the owner open the bot in Telegram and tap **Start**.
3. In the app, go to Settings → enter the token under **Bot Token** → for **Owner Chat ID**, tap auto-detect and select the owner.
4. Tap **Send test message to all owners** to confirm the owner receives it.

> To send to a group: add the bot to the group, send a message in the group, then use auto-detect and select that group.

## Registering Checkpoints
Stick an NFC tag at each patrol location (NTAG213/215/216 are the most common and cheapest) → Settings → **Checkpoints** → **Scan to add** → enter a name.
