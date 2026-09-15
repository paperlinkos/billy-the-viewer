# Phase 11 – Location‑Based Contextual Ad Matching

**Goal**: Augment the existing visual‑only scanner with a lightweight, location‑aware pre‑filter that quickly determines the *type* of surface being scanned (billboard, flyer, screen/TV) and narrows the candidate set to the most plausible ads registered for that physical location.

---

## 1. High‑level Architecture

```
+-------------------+        +-------------------+        +-------------------+
|   Camera Stream  |  --->  |  Frame Processor  |  --->  |   Context Engine  |
+-------------------+        +-------------------+        +-------------------+
        |                              |                       |
        |                              |   +-------------------+   |
        |                              +-->|   Geo‑Provider    |   |
        |                              |   +-------------------+   |
        |                              |   +-------------------+   |
        +-------------------------->---|   Light Sensor    |   |
                                       +-------------------+   |
                                       +-------------------+   |
                                       |   Size/Shape Est. |   |
                                       +-------------------+   |
                                                |          |
                                                v          v
                                        +---------------------------+
                                        |   Candidate Selector      |
                                        +---------------------------+
                                                |
                                                v
                                        +---------------------------+
                                        |   Continuous‑Recognition  |
                                        +---------------------------+
                                                |
                                                v
                                        +---------------------------+
                                        |   UI / Result Dispatcher  |
                                        +---------------------------+
```

* **Geo‑Provider** – Uses device GPS (via `geolocator`), optional Wi‑Fi/cell‑tower fallback, and a cached map of ad‑owner locations (provided by advertisers).  
* **Light Sensor** – Reads ambient‑light level (`sensor_plugin`) to differentiate indoor screens vs. outdoor billboards.  
* **Size/Shape Estimator** – Leverages ARCore/ARKit (or a simple perspective‑size heuristic) to approximate physical dimensions of the scanned rectangle.  
* **Candidate Selector** – Queries a local SQLite DB (`sqflite`) populated with ad metadata (latitude/longitude, radius, expected size range, media‑type).  
* **Continuous‑Recognition** – The existing rolling‑window recogniser (Phase 10) runs **only on the filtered candidate set**; if the candidate set is empty we fall back to the generic Y‑plane matcher.

---

## 2. Data Model (SQLite table `ad_candidates`)
```sql
CREATE TABLE ad_candidates (
  id TEXT PRIMARY KEY,               -- campaign UUID
  lat REAL NOT NULL,                 -- centre of ad placement
  lng REAL NOT NULL,
  radius_meters REAL NOT NULL,       -- searchable radius
  media_type TEXT NOT NULL,          -- 'billboard' | 'flyer' | 'screen'
  min_width_cm REAL NOT NULL,        -- expected physical width range
  max_width_cm REAL NOT NULL,
  min_height_cm REAL NOT NULL,
  max_height_cm REAL NOT NULL,
  signature BLOB NOT NULL            -- pre‑computed Y‑plane feature vector
);
```
Advertisers will upload *placement metadata* through the existing advertiser dashboard (new UI screens can be added later). For now we will pre‑populate the table with a handful of dummy entries for testing.

---

## 3. New Packages (add to `pubspec.yaml`)
```yaml
dependencies:
  geolocator: ^10.0.0          # GPS / location
  sensor_plugin: ^0.5.0        # Ambient light (iOS/Android)
  sqflite: ^2.2.0               # Local DB for candidate metadata
  path_provider: ^2.0.0        # DB path
  arcore_flutter_plugin: ^0.0.5   # Android ARCore (optional)
  arkit_plugin: ^0.6.0            # iOS ARKit (optional)
```
(AR packages are optional – we provide a fallback that uses the camera's focal length and reported image size to estimate physical size.)

---

## 4. Core Classes (files to add)
| File | Responsibility |
|------|----------------|
| `lib/services/location_context.dart` | Retrieves GPS, computes distance to stored ad locations, returns a list of *nearby* candidates. |
| `lib/services/light_sensor.dart` | Reads ambient‑light level, normalises to a 0‑1 range, provides `isOutdoor()` heuristic. |
| `lib/services/size_estimator.dart` | Uses ARCore/ARKit (or fallback) to estimate physical width/height of the detected rectangle in centimetres. |
| `lib/services/candidate_selector.dart` | Combines geo, light, size to query `ad_candidates` and returns a filtered list. |
| `lib/services/continuous_recognition.dart` (updated) | Accepts optional `List<AdCandidate>`; if non‑empty, only computes similarity against those signatures. |
| `tool/populate_dummy_candidates.dart` | CLI script that inserts a few rows into the SQLite DB for quick local testing. |

---

## 5. Integration points
1. **`home_screen.dart`** – When the user presses **SCAN**, instantiate `LocationContext`, `LightSensor`, and `SizeEstimator`. Pass their combined result into `ContinuousRecognition.start(candidates)`. The UI shows a small “📍 Billboard detected” badge if the context predicts a billboard.
2. **`recognition_benchmark`** – No change; the benchmark continues to use the generic matcher (offline fallback).  
3. **`advertiser dashboard`** – (future) add a screen to define placement metadata (lat/lng, radius, expected size).  
4. **Testing** – New unit tests for each service; integration test that mocks GPS + light and verifies that the candidate selector returns the expected subset.

---

## 6. Performance & Battery considerations
* GPS is obtained **once** when the scan starts and cached for the session (≈ 5 s to acquire).  
* Light sensor sampling is passive, no wake‑lock required.  
* Size estimation runs on the GPU (ARCore) and is only active while the camera preview is visible.  
* The SQLite query is O(log N) and negligible (< 1 ms) even with thousands of ads.

---

## 7. Verification Plan
| Test | Expected outcome |
|------|-------------------|
| **Unit** `location_context_test.dart` | Mock location = (37.7749,‑122.4194); DB contains a billboard at 100 m radius → selector returns it. |
| **Unit** `light_sensor_test.dart` | Simulated lux = 8000 → `isOutdoor()` = true; low lux → false. |
| **Integration** on device (Android) | Place a printed flyer on a table, point the phone – UI shows **Flyer** badge, match occurs within 1 s. |
| **Integration** on device (outdoor billboard) | Scan a real billboard – UI shows **Billboard** badge and match succeeds within 1 s. |
| **Performance** profile `flutter run --profile` | CPU < 20 % during recognition, battery impact < 2 %/hour. |

---

## 8. Open Questions (need your input)
> [!IMPORTANT]
> - **AR vs. fallback**: Do you want to ship ARCore/ARKit now (adds native SDKs) or rely on the geometric fallback for the MVP?  
> - **Radius granularity**: How far should the scanner look for candidates (e.g., 200 m for billboards, 30 m for flyers)?  
> - **Privacy**: Should we ask the user for location permission only when they tap **SCAN**, or request it on first launch?  
> - **Advertiser data ingestion**: For the prototype, we can seed the DB manually. Do you anticipate a server‑side sync later, or will all data stay on‑device?  

---

## 9. Proposed Timeline (one dev – you as lead)
| Week | Milestone |
|------|-----------|
| 1 | Add dependencies, implement `LocationContext` & `LightSensor`. |
| 2 | Implement `SizeEstimator` (fallback geometry first). |
| 3 | Build SQLite schema, write `populate_dummy_candidates.dart`, add `CandidateSelector`. |
| 4 | Refactor `ContinuousRecognition` to accept candidate list, integrate into UI. |
| 5 | Write unit & integration tests, run performance profiling on Android & iOS. |
| 6 | Bug‑fixes, documentation, optional AR integration if approved. |

---

**Once you confirm the open questions**, I will start creating the new files and wiring everything up.

---

*This implementation plan is stored in `implementation_plan.md` (user‑facing, request_feedback = true).*
