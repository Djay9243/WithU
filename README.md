# WithU

**Travel solo, together.**

WithU is an iPhone app for solo travellers in Italy. Plan a trip on the map, share moments with the people you choose, and know that someone has your back if something feels wrong. Safety is built in, but stays in the background until it's needed.

> Built by team **5 O'Clock**: Fauzan, Salma, Mehek, Djay and Mounsef.

---

## Features

### Map
- Full-screen map of Italy with Liquid Glass controls.
- **Where to?** search, limited to places in Italy.
- Travel mode panel: Walk, Drive, Cycle or Transit.
- Recent places: a recent place and **Start** is two taps.
- A short trip sheet shows the time, distance, circle and **Start**.
- Settings is the gear button at the top right.

### Trips
- The trip timer comes from the Apple Maps arrival estimate.
- Live location is shared with your circle **only during a trip**.
- Arrival is detected automatically and sharing stops.
- Live Activity on the Lock Screen and in the Dynamic Island.
- Siri and Shortcuts: "Start a trip with WithU".

### Moments
- **Share a Moment** opens the camera, then you add a short note.
- The place is found automatically, and you can tap it to hide the location.
- You choose who sees each moment: **Only Me** or one or more circles.
- Location data is removed from photos before saving.
- You can change who can see a moment, or delete it, later.

### Journal
- All your moments and finished trips.
- **Trip Recap**: time, distance, a map of your moments and a shareable card.

### Safety (in the background)
- **Stop prompt**: after a long stop, WithU asks "Found something nice?" with Share a Moment, All Good or I Need Help.
- **Check-ins** if you leave your route, move unexpectedly fast, run out of time or aren't home by a set time.
- **Alerts** go to your first contact, then the whole circle, with your last location and battery.
- **I'm On It**: a contact can reply so you know help is coming.
- Only your **Face ID or Safety PIN** can cancel an alert or end a trip.

### Circles
- Create a circle with a name and people in one form.
- Set the alert order.
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
│   ├── Home/       MapScreen, destination search
│   ├── Trip/       Active trip, stop prompt, check-in, alert, PIN, arrival
│   ├── Stories/    Composer, camera, audience picker, story views
│   ├── Journal/    Journal and trip recap
│   ├── Circle/     Circles, new circle form, incoming alert
│   ├── Settings/   Settings and Safety PIN
│   └── Onboarding/ Welcome and permissions
├── Theme/          Colours and Liquid Glass components
└── Intents/        Siri & Shortcuts
WithUWidgets/       Live Activity widget
```

**Tech:** SwiftUI, MapKit, Core Location, AVFoundation, ActivityKit, App Intents, UserNotifications, LocalAuthentication, CloudKit.

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
- Location is used only during a trip.
- Moments are shared only with the circles you pick, and photo location data is removed.
- The Safety PIN is stored in the Keychain.
- The trip route is deleted when the trip ends. Only a summary is kept in the Journal.

---

## Status

Work in progress for the mid-term review.

- ✅ Map, trips, check-ins, alerts, moments, journal and circles work on one iPhone.
- 🔜 Sharing between phones (iCloud), TestFlight, Time Sensitive and Critical Alerts.
