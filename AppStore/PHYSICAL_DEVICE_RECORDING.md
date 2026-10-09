# Physical-device review recording

Apple requested one continuous recording made on a physical device running the
latest available iOS. Do not use a Simulator recording.

## Before recording

- Install the exact TestFlight build selected for App Review.
- Confirm the production rewarded ad loads and server-side verification grants
  one discovery.
- Set the iPhone clock and status bar normally; do not expose notifications,
  passwords, API keys, or personal messages.
- Reset Bilu's local data or record after the UTC daily allowance resets so the
  free-discovery flow is visible.
- In iOS Control Center, start Screen Recording with the microphone off.

## Continuous shot list

1. Start on the Home Screen and cold-launch Bilu.
2. Show the location choice. Allow location or enter a city manually.
3. Complete the Explore preferences and request the free daily discovery.
4. Wait for recommendations; show that every visible card says the restaurant
   is open, then open a restaurant detail.
5. Show Search, enter a query, open a result, and save it.
6. Show the saved restaurant in Profile.
7. Return to Explore and request another discovery so the rewarded-ad screen
   appears.
8. Tap **Watch ad to continue**, let the ad finish, close it, and show that one
   additional discovery is unlocked.
9. Open Profile > Privacy Choices if the row is available, then return to the
   app.

Save the unedited result as `Bilu-physical-device-review.mov`. The recording
should begin before launch and should not contain cuts, speed changes, overlays,
or background music.
