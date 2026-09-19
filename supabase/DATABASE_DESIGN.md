# Billy The Viewer — Database Domain Mapping & Design Specification

This document defines the authoritative mapping between the active Flutter/Dart recognition codebase and the PostgreSQL / Supabase persistence layer.

---

## 1. Domain Mapping: Dart Application Concept ➔ Supabase Database

| Current Dart Concept | File / Model | Supabase Table | Supabase Column | Authority / Scope | How Recognition Uses It |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`Account.id`** | [`account.dart`](file:///Users/christembassyabujazone1/projects/billy-the-viewer/lib/models/account.dart) | `advertiser_profiles` | `created_by` (FK `auth.users`) | Authoritative (Supabase Auth) | Associates who created the profile. |
| **`Account.displayName`** | [`account.dart`](file:///Users/christembassyabujazone1/projects/billy-the-viewer/lib/models/account.dart) | `advertiser_profiles` | `display_name` | Authoritative | Fallback display name for brand. |
| **`AccountRole.advertiser`** | [`account.dart`](file:///Users/christembassyabujazone1/projects/billy-the-viewer/lib/models/account.dart) | `advertiser_profiles` | `account_type` (`individual` \| `organization`) | Authoritative | Explicitly discriminates solo advertisers from companies. |
| **`Campaign.id`** | [`campaign.dart`](file:///Users/christembassyabujazone1/projects/billy-the-viewer/lib/models/campaign.dart) | `campaigns` | `id` (UUID) | Authoritative | Primary identifier for matching result binding. |
| **`Campaign.ownerAccountId`** | [`campaign.dart`](file:///Users/christembassyabujazone1/projects/billy-the-viewer/lib/models/campaign.dart) | `campaigns` | `advertiser_id` (FK `advertiser_profiles`) | Authoritative | Multi-tenant isolation & ownership. |
| **`Campaign.adName`** | [`campaign.dart`](file:///Users/christembassyabujazone1/projects/billy-the-viewer/lib/models/campaign.dart) | `campaigns` | `ad_name` | Authoritative | Title displayed on recognized Ad Card. |
| **`Campaign.brandName`** | [`campaign.dart`](file:///Users/christembassyabujazone1/projects/billy-the-viewer/lib/models/campaign.dart) | `campaigns` | `brand_name` | Authoritative | Brand label displayed on recognized Ad Card. |
| **`Campaign.destinationUrl`** | [`campaign.dart`](file:///Users/christembassyabujazone1/projects/billy-the-viewer/lib/models/campaign.dart) | `campaigns` | `destination_url` | Authoritative | Click-through link launched on "VIEW" tap. |
| **`Campaign.status`** | [`campaign.dart`](file:///Users/christembassyabujazone1/projects/billy-the-viewer/lib/models/campaign.dart) | `campaigns` | `status` (ENUM) | Authoritative | Filter: Only `active` campaigns are recognized. |
| **`Campaign.startAt`** | [`campaign.dart`](file:///Users/christembassyabujazone1/projects/billy-the-viewer/lib/models/campaign.dart) | `campaigns` | `start_at` | Authoritative | Filter: Excludes campaigns where `now() < start_at`. |
| **`Campaign.endAt`** | [`campaign.dart`](file:///Users/christembassyabujazone1/projects/billy-the-viewer/lib/models/campaign.dart) | `campaigns` | `end_at` | Authoritative | Filter: Excludes campaigns where `now() > end_at`. |
| **`Campaign.mediumType`** | [`campaign.dart`](file:///Users/christembassyabujazone1/projects/billy-the-viewer/lib/models/campaign.dart) | `campaigns` | `medium_type` (ENUM) | Authoritative | ContextEngine pre-filter (billboard, print, screen). |
| **`Campaign.location`** | [`campaign.dart`](file:///Users/christembassyabujazone1/projects/billy-the-viewer/lib/models/campaign.dart) | `campaign_locations` | `latitude`, `longitude`, `radius_meters` | Authoritative | Geofencing pre-filter before matching. |
| **`Campaign.creativeBytes`** | [`campaign.dart`](file:///Users/christembassyabujazone1/projects/billy-the-viewer/lib/models/campaign.dart) | `creatives` | Supabase Storage (`ad-creatives`) | Authoritative (Storage) / Local Cache | Creative image file downloaded & rendered on match card. |
| **`RecognitionSignature.perceptualFeatures`** | [`recognition_signature.dart`](file:///Users/christembassyabujazone1/projects/billy-the-viewer/lib/models/recognition_signature.dart) | `recognition_signatures` | `visual_vector` (`vector(192)`) | Authoritative (Synced locally) | Primary visual embedding compared via Cosine Similarity. |
| **`RecognitionSignature.normalizedOcrText`** | [`recognition_signature.dart`](file:///Users/christembassyabujazone1/projects/billy-the-viewer/lib/models/recognition_signature.dart) | `recognition_signatures` | `normalized_ocr_text` | Authoritative (Synced locally) | Fuzzy token & phrase matching in `MatchingEngine`. |
| **`RecognitionSignature.ocrMetadata`** | [`recognition_signature.dart`](file:///Users/christembassyabujazone1/projects/billy-the-viewer/lib/models/recognition_signature.dart) | `recognition_signatures` | `extracted_words`, `metadata` | Authoritative | GIN indexable tokens; diagnostic audit. |
| **`AdTarget`** | [`ad_target.dart`](file:///Users/christembassyabujazone1/projects/billy-the-viewer/lib/models/ad_target.dart) | *(Client-Side Runtime Projection)* | *(Derived)* | Device-Local Projection | Ephemeral struct fed into `MatchingEngine.matchCandidate()`. |

---

## 2. Field Classification & Preservation Rules

### A. Authoritative in Supabase
- Account/Advertiser credentials and profiles
- Campaign configurations, flight dates (`start_at`, `end_at`), and lifecycle status (`draft`, `processing`, `active`, `paused`, `expired`)
- Creative asset files (in `ad-creatives` Storage bucket) and CDN URLs
- Invariant visual signature vectors (`vector(192)`) and normalized OCR strings
- Registered geofences and placement locations

### B. Cached Locally on Device
- Active campaign catalog (`List<AdTarget>`) for offline or zero-latency scanning
- Cached creative thumbnails for instant UI presentation
- Bundled demo campaign assets (`assets/campaigns/demo_ad.jpg`)

### C. Purely Derived / Ephemeral Client-Side
- Live camera embeddings generated at 60fps
- Temporary crop embeddings (`center_75`, `center_1_5x`, `center_2x`, etc.)
- Cosine similarity scores, separation margins, and ambiguity flags
- `AdTarget` objects constructed in memory via `Campaign.toAdTarget()`

### D. Fields that Must NEVER Be Changed
- **`perceptualFeatures` dimensionality (192)**: Changing this breaks `VisionService` and invalidates all existing benchmarks.
- **Scoring thresholds**: Global threshold remains `0.60`, separation margin remains `0.08`, visual plausibility remains `0.10`.
- **Normalization rules in `OcrService`**: Lowercase alphanumeric trimming must remain identical.

---

## 3. Advertiser Ownership Model: Individual vs. Organization

The architecture prevents duplicating campaigns, signatures, or matching logic by introducing `advertiser_profiles`:

```
User (auth.users)
 ├── Individual Profile (1:1 with user)
 │     └── Campaigns ──► Creatives ──► Signatures
 └── Organization Profile (1:N with users via advertiser_members)
       ├── Owner / Admins / Campaign Managers
       └── Campaigns ──► Creatives ──► Signatures
```

1. **Individual Advertisers:**
   - Designed for personal sellers, freelancers, and sole proprietors.
   - Profile `account_type = 'individual'`.
   - Directly linked to `created_by`. No team members required.
2. **Organizations:**
   - Designed for brands, agencies, and institutions.
   - Profile `account_type = 'organization'`.
   - Allows multiple team members (`advertiser_members`) with roles: `owner`, `admin`, `campaign_manager`, `analyst`.
   - Features corporate fields: `legal_name`, `tax_or_business_id`, `verification_status`.
3. **Campaign Ownership Unification:**
   - `campaigns.advertiser_id` always references `advertiser_profiles.id`.
   - The recognition engine, signature extraction, and viewer experiences behave 100% identically for both types.

---

## 4. Recognition Candidate Synchronization & Ingestion Flow

To maintain **zero-latency (60fps) camera scanning** and **full offline reliability**, recognition does NOT perform network roundtrips during frame processing:

```
[Advertiser Portal]
       │
       ▼
Uploads Creative & Registers Campaign
       │
       ▼
Creative saved to Supabase Storage ("ad-creatives")
Visual Signature (192-dim) + OCR generated & saved to "recognition_signatures"
Campaign marked status = 'active'
       │
═══════╪═══════════════════════════════════════════════════════════════
       │ (Asynchronous sync on app launch or foreground)
       ▼
[Billy Viewer Mobile Device]
       │
       ▼
Downloads only active, unexpired campaigns via `active_recognition_candidates` View
Populates local in-memory/cached candidate pool
       │
       ▼
[Live Scan / Photo Scan Loop]
       │
       ├── Reads camera frame (0ms network latency)
       ├── VisionService extracts live 192-dim vector
       ├── MatchingEngine compares against cached AdTargets
       └── MatchResult returned instantly
```
