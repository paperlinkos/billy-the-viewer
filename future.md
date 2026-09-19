# Billy The Viewer — Product Architecture & Feature Roadmap

This document outlines the architectural feasibility, technical design, data flows, and phased execution plan for Billy The Viewer based on core business and product goals.

---

## 1. UI Simplification: Photo-First Mode (Immediate Priority)

### User Requirement
> *"i want to remove scan mode and leave just photo for now then we add that later"*

### Architectural Feasibility: **High (Trivially Achievable & Clean)**
- **Current State**: The camera interface offers two capture modes:
  1. Live video frame scanning (`InlineCameraView` stream running in real time).
  2. Still photo capture (`MultiScalePhotoAnalyzer` multi-scale, multi-crop analysis).
- **Execution Strategy**:
  - Make still photo capture the default and sole primary interaction on `HomeScreen`.
  - The live video stream continues to display the camera preview inside the viewfinder, but continuous automated background frame matching is bypassed.
  - Recognition executes only when the user taps the center capture shutter / photo button.
  - **Benefits**:
    1. Eliminates battery and thermal drain from continuous per-frame inferencing.
    2. Guarantees maximum resolution and sharp OCR text extraction from `MultiScalePhotoAnalyzer`.
    3. Streamlines the viewer's mental model: point, tap, discover.
- **Future Reintroduction**: Live continuous scanning can be toggled in settings once cloud candidate pre-filtering is active.

---

## 2. Unregistered Ad Fallback: Smart URL Scraping & Navigation

### User Requirement
> *"also i want to have the scraper feature that if the image has a url and the ad is not registered we can take you there (thats the second flow not the first) but tell you they arent registered with us and have you onboard them so they can start advertising with us"*

### Architectural Feasibility: **Very High (Leveraging ML Kit OCR Engine)**
- **Current State**:
  - ML Kit OCR (`OcrService`) already extracts text blocks, lines, and tokens from captured photos.
  - If visual and text matching against registered campaigns falls below threshold, the system displays `NO_MATCH`.
- **Proposed Flow & Mechanism**:
  1. **Primary Match (Registered)**: Check local vector database / Supabase candidates. If similarity exceeds threshold $\to$ display official Interactive Billy Campaign card (actions, reward points, direct buttons).
  2. **Secondary Match (Unregistered with URL / Domain)**:
     - If no registered campaign matches, run regex extraction on OCR text blocks:
       ```regexp
       (?:https?:\/\/)?(?:www\.)?([a-zA-Z0-9-]+\.[a-zA-Z]{2,})(?:\/[^\s]*)?
       ```
     - Also parse Twitter/X handles (`@brand`), Instagram tags, and QR codes visible in the photo.
  3. **Editorial Result Card (Unregistered Ad Detected)**:
     - Headline: `DETECTED DESTINATION: [brand.com]`
     - Sub-badge: `UNOFFICIAL // UNREGISTERED ADVERTISER`
     - Action 1: **`VISIT WEBSITE`** $\to$ Opens detected URL in in-app webview or external browser.
     - Action 2: **`ONBOARD THIS BRAND`** $\to$ Launches Community Lead Generation Flow (see Section 3).

---

## 3. Viral Viewer-Driven Advertiser Referral Engine (Community Onboarding)

### User Requirement
> *"also lets have a user onboarding advertisers system? so i mean if they check out a product or ad and its not there they should be able to contact them maybe tag them on twitter to tell them about us and what we do and if they do [earn rewards]"*

### Architectural Feasibility: **High (Viral Growth Loop)**
- **How It Works**:
  1. When an unregistered ad or brand is scanned, the user is presented with a **`TAG THIS BRAND`** or **`INVITE BRAND TO BILLY`** button.
  2. **Twitter/X Deep Link / Web Intent**:
     - Pre-populates a tweet intent:
       > *"Hey @[BrandHandle]! I just scanned your billboard with @BillyViewer. Register your creative on Billy so viewers can claim rewards and direct offers instantly! #BillyTheViewer"*
  3. **Referral Attribution & Reward Loop**:
     - Every viewer account has a unique referral code / deep link (`billy.app/r/{viewer_id}`).
     - When an advertiser subsequently signs up using that referral link or domain claim:
       - The viewer who tagged them is awarded **bounty points / scanning credits**.
       - The domain or handle is logged in Supabase under `prospective_advertisers` for the sales team.

---

## 4. Medium & Location Sensor Filtering (Billboards, Screens, Flyers)

### User Requirement
> *"location based sensor for billboards so the scanner will quickly tell based on distance and shape and size and light whether its a billboard, flyer, or screen... only search among those most likely match based on location, and similar parameters for tv and flyers"*

### Architectural Feasibility: **High (Tiered Context Filtering)**
- **Problem**: Querying thousands of campaigns globally across all mediums causes latency and false positives.
- **Solution (3-Tier Context Filtering)**:

```
[Camera Capture]
       │
       ├─► Device Sensors (GPS Lat/Lng, Compass Heading)
       ├─► Optical Telemetry (ARKit/ARCore scene depth, aspect ratio, luminance)
       │
       ▼
[Context Engine: Medium Classifier]
       │
       ├─► Physical Billboard: High altitude/angle, outdoor GPS match, far distance
       ├─► Digital Screen/TV: 16:9 aspect ratio, high backlight luminance, indoor/stationary
       └─► Print Flyer/Magazine: Close-up depth (<0.5m), ambient reflected light, hand tremors
       │
       ▼
[Targeted Supabase Spatial Query]
       SELECT * FROM active_recognition_candidates
       WHERE medium = detected_medium
         AND ST_DWithin(geom, ST_SetSRID(ST_Point(lng, lat), 4326), radius_meters)
       LIMIT 25;
```

- **Technical Implementation Details**:
  1. **Geo-Location Pruning**: Advertisers register their billboard GPS coordinate or geofence boundary (e.g. `500m radius around billboard at Lekki Toll Gate`). When a user scans with GPS active, only local candidates are evaluated.
  2. **Optical Medium Heuristics**:
     - `AspectRatio`: Billboards are often extreme widescreen (3:1, 4:1) or vertical format; screens are 16:9; flyers are A4/letter (1.41:1).
     - `Luminance/Histogram`: Screens emit directional light; billboards reflect ambient daylight/spotlights.
     - `Distance/Depth`: AR depth sensors (iOS LiDAR or Android Depth API) provide distance estimates to differentiate a sheet in hand from a poster 20 meters away.

---

## 5. Advertiser Multi-Campaign Catalog & Life-Cycle Management

### User Requirement
> *"advertiser should be able to several ads and have a catalogue were they can manage them, stop add new ones, categorize them and so on"*

### Architectural Feasibility: **Ready (Supabase Schema Already Supports This)**
- **Current Database Architecture**:
  - `advertiser_profiles` links directly to `campaigns` via `advertiser_id`.
  - `campaigns` table already includes `status` (`draft`, `active`, `paused`, `archived`, `completed`).
  - `creatives` table handles multiple assets per campaign.
- **Frontend Dashboard to Build in Phase 2B**:
  - **Campaign Catalog View**: A tabbed list for the advertiser (`Active`, `Paused`, `Drafts`).
  - **Quick Controls**:
    - Toggle switch: `PAUSE CAMPAIGN` / `ACTIVATE CAMPAIGN` (instantly updates Supabase, updating recognition candidate pool).
    - Categorization tag selector (`Automotive`, `Fashion`, `Tech`, `FMCG`).
    - Performance metrics: Scans counter, CTR, viewer interactions.

---

## 6. Advertiser KYC Verification (BVN, Phone, Email Verification)

### User Requirement
> *"there needs to be a kyc onboarding for advertisers, we can start with name and phone number and email and bvn"*

### Architectural Feasibility: **High (Enterprise Compliance Flow)**
- **Security & Regulatory Requirements (Nigeria / Financial Data)**:
  - **BVN (Bank Verification Number)** is strictly sensitive PII regulated by the CBN and NDPR.
  - Direct raw storage of BVNs is a compliance liability.
- **Recommended Architecture**:
  1. **Verification via Trusted Provider (Dojah / Smile Identity / Paystack Identity)**:
     - User inputs: Legal Name, Phone Number, Work Email, and BVN.
     - Backend edge function calls identity provider:
       ```
       POST https://api.dojah.io/api/v1/kyc/bvn/verify
       Payload: { bvn: "22222222222", firstName: "...", lastName: "...", dob: "..." }
       ```
     - The provider checks if the name matches the BVN record.
  2. **Storage in Supabase**:
     - Do **NOT** save raw BVN.
     - Save: `bvn_verified: true`, `bvn_masked: "******1234"`, `kyc_reference_id`, `verification_status: "verified"`.
  3. **Advertiser Status Gates**:
     - `kyc_pending` $\to$ Can create drafts and test scanning.
     - `kyc_approved` $\to$ Can publish live public campaigns across the national network.

---

## 7. Viewer Monetization: Free Tier & Subscription Metering

### User Requirement
> *"for users we will have it free for now unlimited then they'd have to subscribe to get more than 3 scans or so a day"*

### Architectural Feasibility: **Standard & Scalable**
- **Architecture**:
  1. **Local + Remote Scan Counter**:
     - Stored locally in `SharedPreferences` for offline enforcement (`daily_scan_count`, `last_scan_date`).
     - Synced to Supabase `viewer_profiles.scans_today` on every successful match.
  2. **Freemium Policy**:
     - **Phase A (Current Growth Launch)**: Unlimited free scans to maximize viral adoption and scan data gathering.
     - **Phase B (Monetization Rollout)**:
       - Free Tier: 3 scans per 24-hour cycle.
       - Scan 4+: Triggers paywall modal: *"You've discovered 3 ads today. Upgrade to Billy Pro for unlimited discoveries & double reward points."*
       - Integrated via In-App Purchases (RevenueCat / Apple StoreKit & Google Play Billing) or local recurring payment (Paystack/Flutterwave).

---

## Summary Implementation Sequence

| Phase | Milestone | Core Impact |
| :--- | :--- | :--- |
| **Phase 1** | **Photo-First Mode** | Simplify UI to still photo shutter; eliminate continuous video scan load. |
| **Phase 2** | **URL Scraper & Unregistered Ad Card** | Extract URLs from uncataloged ads with "Visit Site" and "Onboard Brand". |
| **Phase 3** | **Brand Referral / Tagging Engine** | Enable users to tweet/tag brands and earn bounties when brands onboard. |
| **Phase 4** | **Advertiser Catalog & KYC Portal** | Multi-ad dashboard, pause/resume toggles, and BVN identity verification. |
| **Phase 5** | **Spatial & Medium Context Engine** | GPS billboard radius filters, aspect ratio & sensor medium classifiers. |
| **Phase 6** | **Usage Metering & Subscriptions** | Daily scan quota enforcement and Billy Pro tier activation. |
