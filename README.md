# WithU

**Travel solo, together.**

WithU is an iPhone app for solo travellers in Italy. Plan a trip on the map, share moments with the people you choose, and know that someone has your back if something feels wrong. Safety is built in, but stays in the background until it's needed.

> Built by team **5 O'Clock**: Fauzan, Salma, Mehek, Djay and Mounsef.

---

## Features

### Map
- Full-screen map of Italy with Liquid Glass controls and the familiar blue location dot.
- **Pick a destination by tapping the map.** Tap a café, station or shop to pick it by name, or tap any other spot to pick its street address.
- **Search** is the round icon at the right of the tab bar. It opens a search sheet with the field at the top, then your saved places, then recent places.
- **Home, Work and Gym**: tag a place from the small tag button on the trip sheet. Tagged places become one-tap chips in Search.
- Walk, Drive, Cycle or Transit is picked in the trip sheet.
- Each way of travelling draws its own route as a simple solid line, like Apple Maps. For transit, WithU shows the walk to the station, **Get on** and **Get off** pins and plain steps ("Walk 4 min to Vanvitelli, take the metro, get off at Toledo"). Apple Maps doesn't give apps the metro track, so the ride isn't drawn; **Lines in Maps** opens Apple Maps for the exact lines.
- **Busy Routes** (Settings): for walking, prefers a route past more shops, cafés and stations when it's at most 30% slower than the fastest.
- A short trip sheet shows the time, distance, circle and **Start**, with the close button at the top right.
- Settings is the gear button at the top right of the map.

### Trips
- The trip timer comes from the Apple Maps arrival estimate.
- Live location is shared with your circle **only during a trip**.
- Arrival is detected automatically and sharing stops.
- Live Activity on the Lock Screen and in the Dynamic Island.
- **Action button**: assign the **Alert My Circle** shortcut to alert your circle with a press and hold.

### Moments
- **Share a Moment** opens the iPhone camera (or your photo library), then you add a short note.
- During a trip, the photo chip next to Share a Moment shows the moments you've taken.
- The place is found automatically, and you can tap it to hide the location.
- You choose who sees each moment: **Only Me** or one or more circles.
- Location data is removed from photos before saving.
- You can change who can see a moment, or delete it, later.

### Journal
- All your moments and finished trips, kept for 30 days.
- **Trip Recap**: time, distance, a map of your moments and a shareable card.

### Safety (in the background)
- **Long stop**: after 15 minutes stopped, WithU asks "Found something nice?" with **I'm Fine**, **Remind Me Later** and **I Need Help**.
  - **Remind Me Later** asks again 15 minutes later. That second check-in can't be put off, and no reply to it alerts the circle.
  - Moving on cancels the reminder.
- **Check-ins** if you leave your route, move unexpectedly fast, run out of time or aren't home by a set time. You have **15 or 20 minutes** to reply (Settings), with a reminder 5 minutes before. You can answer straight from the notification.
- **Closing the app doesn't skip a check-in.** The countdown is saved with the trip and picks up when WithU opens again; if the time ran out while it was closed, the circle is alerted then.
- **No reply?** The whole circle is told at once, with the **last place your phone was seen**, when that was, and your **battery**. Your location keeps updating for them every minute.
- **Get Help** and **I Need Help** tell the whole circle straight away.
- **I'm On It**: a contact can reply so you know help is coming.
- Only your **Face ID or Safety PIN** can cancel an alert, end a trip or say **I've Arrived**.

### Circles
- Each circle is a card showing everyone in it, with their avatar and first name.
- Create a circle with a name and people in one form.
- Swipe a circle to rename or delete it; open it to set the alert order.
- **Can See My Stories** can be turned off for a safety-only circle.

---

## Project structure

```
WithU/
├── App/            AppModel (root state), TripManager (trip & safety logic)
├── Models/         Core types, Story & Journey
├── Services/       Location, routing (Italy only), notifications, places,
│                   stories, iCloud sync, Live Activity, authentication
├── Views/
│   ├── Home/       MapScreen, search, route lines
│   ├── Trip/       Active trip, stop prompt, check-in, alert, PIN, arrival
│   ├── Stories/    Composer, camera, audience picker, story views
│   ├── Journal/    Journal and trip recap
│   ├── Circle/     Circles, new circle form, contact picker, incoming alert
│   ├── Main/       Tab bar and search icon
│   ├── Settings/   Settings and Safety PIN
│   └── Onboarding/ Welcome and permissions
├── Theme/          Colours and Liquid Glass components
└── Intents/        Action button "Alert My Circle"
WithUWidgets/       Live Activity widget
```

**Tech:** SwiftUI, MapKit, Core Location, AVFoundation, ActivityKit, App Intents, UserNotifications, LocalAuthentication, ContactsUI, CloudKit.

---

## Requirements

- Xcode 27 or later
- iOS 27.2 or later
- An iPhone with a camera and GPS

---

## Getting started

1. Clone the repo and open `WithU.xcodeproj`.
2. In **Signing & Capabilities**, choose your team for the **WithU** and **WithUWidgetsExtension** targets.
3. Build and run on an iPhone.

### Turning on sharing between phones

Sharing moments, trips and alerts between phones uses **iCloud (CloudKit)** and needs a **paid Apple Developer account**.

1. Add the **iCloud** capability with **CloudKit** and the default container.
2. Add the **Push Notifications** and **Time Sensitive Notifications** capabilities.
3. Set `WithUCloudSyncEnabled` to `true` in `WithU/Info.plist`.
4. Run the app once, then deploy the schema to production in the CloudKit Console.

Until then, moments are saved on your phone only, and trips and alerts aren't sent to other phones.

---

## Privacy

- No sign-up or accounts.
- Location is used only during a trip, and to name a spot you tap on the map.
- Moments are shared only with the circles you pick, and photo location data is removed.
- The contact picker shares only the people you choose; WithU never reads your whole address book.
- The Safety PIN is stored in the Keychain.
- The trip route is deleted when the trip ends. Only a summary is kept in the Journal.

---

## Known limits

- After the app is **force-quit**, iOS doesn't let WithU run, so a missed check-in can only alert the circle once WithU is opened again. Scheduled check-in notifications still arrive while it's closed.
- Time Sensitive and Critical Alerts need entitlements from a paid developer team; without them, check-ins arrive as normal notifications.

---

## Status

Work in progress.

- ✅ Map, trips, check-ins, alerts, moments, journal and circles work on one iPhone.
- 🔜 Sharing between phones (iCloud), TestFlight, Time Sensitive and Critical Alerts.
