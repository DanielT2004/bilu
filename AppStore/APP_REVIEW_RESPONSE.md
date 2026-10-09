# App Review response — ads-only build

Do not send this response until the production AdMob IDs are configured, the
new build is uploaded, and the physical-device recording is attached.

---

Thank you for the opportunity to provide the requested information.

1. Physical-device recording

Attached: `Bilu-physical-device-review.mov`, recorded on [DEVICE MODEL] running
iOS [VERSION]. The recording begins from a cold launch and demonstrates location
permission/manual location, Explore preferences, personalized recommendations,
restaurant details, Search, saving a restaurant, Profile, the daily free
discovery, and the optional rewarded-ad flow.

2. Purpose and intended audience

Bilu helps adults discover nearby restaurants that match an occasion, cuisine,
budget, dietary needs, desired atmosphere, and location. It is intended for
general restaurant customers. It is not designed for children.

3. Setup and access

No account, login, invitation, subscription, or special hardware is required.
Reviewers can allow location access or enter a city manually. All app features
can be reviewed immediately after launch. Saved restaurants and preferences are
stored on the device.

4. External services

Bilu uses Supabase for the application backend, Google Gemini for restaurant
recommendation generation, Google Places and Apple MapKit/Core Location for
place and location information, and Google AdMob with Google's User Messaging
Platform for optional rewarded ads. Public restaurant-related TikTok data may
be used to improve discovery relevance; users do not sign in to TikTok through
Bilu.

Monetization is ads-only. Each user receives one free discovery per UTC day.
After it is used, the user may voluntarily watch one rewarded ad to unlock
exactly one additional discovery. Bilu has no banner, interstitial, app-open, or
interrupting ads. Bilu has no in-app purchases, subscriptions, paid digital
content, or external purchase links. The app does not request App Tracking
Transparency permission; AdMob ad eligibility and privacy choices are handled
through Google's User Messaging Platform.

5. Regional differences

Core functionality is the same in all supported regions. Restaurant coverage,
place details, public social content, and ad availability may vary based on the
availability of third-party data and advertising inventory. If an ad is not
available, the app displays a retry message and does not charge the user.

6. Regulated or protected material

Bilu does not provide regulated services, gambling, financial services,
healthcare, cannabis sales, or licensed streaming content. It displays public
restaurant information and links to third-party websites when available. No
authorization documentation is required.

Additional review notes

- The recommendations feed only publishes restaurants after a live Google
  Places status check confirms that the restaurant is open. Closed or unknown
  results are excluded.
- Bilu has no user-generated content, registration, or account deletion flow.
- Reward completion is verified server-side before an additional discovery is
  granted.

---

## Before sending

- Replace both bracketed recording placeholders.
- Attach a continuous recording made on a physical iPhone running the latest
  available iOS, beginning at cold launch.
- Use the production AdMob application ID and rewarded ad-unit ID.
- Configure and test AdMob server-side verification.
- Confirm no subscription products or legacy paywall screenshots are attached
  to the version being reviewed.
- Upload the matching release build to TestFlight and select it for the version.
- Verify App Privacy answers include data processed by Google Mobile Ads.
