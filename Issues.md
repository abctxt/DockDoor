# Issues and Performance Recommendations

This document summarizes potential performance problems I found in the codebase, the reason they're risky, and concrete, prioritized remediation steps with example snippets you can apply immediately.

---

## Summary (high-priority highlights)
- **Blocking sleeps on the main thread** (HIGH): `WindowInfo.bringToFront()` uses `usleep(50000)` and can block the main thread, causing UI jank.
- **Repeated NumberFormatter allocation in SwiftUI views** (MEDIUM): Views create `NumberFormatter()` inside view bodies repeatedly.
- **High-frequency @Published image updates from live streams** (MEDIUM/HIGH): `WindowLiveCapture` publishes every frame and can saturate the main thread.
- **Potentially heavy string matching / edit distance usage** (LOW/MEDIUM): `StringMatchingUtil.fuzzyMatch` and `levenshteinDistance` may be expensive in tight loops or search-as-you-type.
- **Bitmap / resizing work done often on main thread** (MEDIUM): Image resizing and average color calculations are expensive and sometimes done frequently.

---

## Detailed issues and suggested fixes

### 1) Blocking sleeps in `WindowInfo.bringToFront()` — HIGH ⚠️
- Files: `DockDoor/Utilities/Window Management/WindowInfo.swift`
- Problem: The retry loop uses `usleep(50000)` which blocks the (likely main) thread.
- Why it's bad: Blocking main thread stalls UI, inhibits responsiveness, and compounds under load.
- Suggestion: Change to an asynchronous retry with `Task.sleep(...)` or run retries off-main and execute AX calls on the main actor when needed.

Example (conceptual) replacement:
```swift
// Make an async variant:
func bringToFrontAsync() async {
  let maxRetries = 3
  for attempt in 1...maxRetries {
    let success = await attemptActivation() // implement to run AX calls on MainActor as needed
    if success { WindowUtil.updateTimestampOptimistically(for: self); return }
    if attempt < maxRetries { try? await Task.sleep(nanoseconds: 50_000_000) }
  }
}
```
- Implementation notes: Keep AX calls on the main actor (`@MainActor`) but avoid `usleep` and synchronous blocking; callers that must remain synchronous can call `Task { await bringToFrontAsync() }`.

---

### 2) Repeated `NumberFormatter()` allocations in view bodies — MEDIUM ⚠️
- Files: `DockDoor/Views/Settings/*.swift` (several places instantiate `let f = NumberFormatter()` inside view code)
- Problem: `NumberFormatter` is expensive to construct and view bodies are evaluated often.
- Suggestion: Use shared static formatters or central reusable formatters.
- Implementation:
  - Use existing helpers in `Extensions/Formatters/NumberFormatter+Convenience.swift`, e.g. `NumberFormatter.oneDecimalFormatter` or `percentFormatter`.
  - For custom variants, add static cached instances rather than allocate on every body evaluation.

Example replacement:
```swift
// Replace
let f = NumberFormatter()
// With
let f = NumberFormatter.oneDecimalFormatter
```

---

### 3) High-frequency `@Published` updates from live capture — MEDIUM/HIGH ⚠️
- Files: `DockDoor/Utilities/Window Management/LiveWindowCapture.swift`
- Problem: `StreamOutput` calls `onFrame(image)` for every frame; `WindowLiveCapture` writes `@Published var capturedImage` at full frame rate.
- Why it's bad: Frequent main-thread publishes lead to continuous UI re-renders and high CPU.
- Suggestion: Throttle updates (e.g., publish <= 10 FPS), or coalesce frame updates and update UI on a timer. Alternatively, publish frames to a background queue and only update the main actor occasionally.

Example (conceptual) throttling snippet in `WindowLiveCapture`:
```swift
private var lastPublished = Date.distantPast
private let minInterval: TimeInterval = 1.0 / 10.0 // 10 FPS
// In the stream handler onMainActor:
let now = Date()
if now.timeIntervalSince(lastPublished) >= minInterval {
  self.capturedImage = image
  self.lastPublished = now
} else {
  self.lastFrame = image // store latest, but don't trigger UI
}
```

---

### 4) Repeated slow AX queries inside loops — MEDIUM
- Files: `DockDoor/Utilities/Window Management/WindowUtil.swift`
- Problem: `findWindow(...)` and `isValidElement(...)` repeatedly call `title()`, `position()`, `size()` etc. inside loops.
- Suggestion: Cache repeated property reads locally where safe (read `axWindow.title()` once and re-use it in the loop) or prefetch properties before iterating.

Example:
```swift
// Bad:
for ax in axWindows {
  if try? ax.title() == window.title { ... }
}
// Better:
for ax in axWindows {
  let t = (try? ax.title()) ?? ""
  if t == window.title { ... }
}
```

---

### 5) Heavy string matching / levenshtein in hot paths — LOW/MEDIUM
- Files: `DockDoor/Utilities/StringMatchingUtil.swift`, `DockDoor/Models/MediaInfo.swift`
- Problem: `fuzzyMatch` and `levenshteinDistance` are O(n*m) and can be expensive when run often (e.g., search-as-you-type over many items).
- Suggestion:
  - Add debounce on search inputs (avoid matching for each keystroke), and avoid running heavy algorithms when query is short.
  - Consider memoization of target preprocessing (lowercased arrays) or use more efficient heuristics for fuzzy matching.

Quick optimizations:
```swift
// Early return for very short query
if query.count <= 1 { return target.contains(query) }
```

---

### 6) Image resizing / average color work — MEDIUM
- Files: `WindowUtil.captureWindowImage`, `Extensions/NSImage.swift`
- Problem: Context drawing + resizing is CPU-intensive when performed frequently.
- Suggested fixes:
  - Cache resized images with a cache lifespan (there is already caching in `captureWindowImage` — ensure it's used consistently).
  - Move heavy CG drawing off the main thread (perform in a background task and publish result to main once ready).

---

### 7) Misc / scheduling bursts — LOW
- Files: many places use `DispatchQueue.main.asyncAfter` for short delays (0.08s–0.2s); fine in many cases but can create bursts.
- Suggestion: Use cancelable `Task` flows where possible, coalesce, and avoid scheduling during rapid input events.

---

_Last scanned: January 11, 2026_
