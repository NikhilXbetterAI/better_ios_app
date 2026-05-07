# Memory Efficiency Issues - Investigation Report

## Critical Issues Found

### 1. **Unbounded Data Fetches in LocalDataRepository**

**File:** `Better/Core/Repositories/LocalDataRepository.swift`

#### Issue 1a: `fetchDataInventory()` - Line 551
```swift
let sessions = try modelContext.fetch(sessionDescriptor)
```
**Problem:** Fetches ALL sleep sessions without limit just to count them. For users with 60+ days of data (180+ sessions), this loads the entire dataset into memory.

**Impact:** HIGH - Called from Privacy/Settings view, and repeatedly during data operations.

**Fix:** Use `fetchCount()` instead of fetching all objects.

#### Issue 1b: `fetchAvailableSleepDates()` - Line 68-84
```swift
return try modelContext.fetch(descriptor).map { stored in
    SleepDaySummary(...)
}
```
**Problem:** Fetches ALL sessions for an entire month just to extract summaries. No pagination or batch limits.

**Impact:** HIGH - Called every time user navigates to a new month. For a user with 3-5 sessions per day, loading 90+ sessions into memory is unnecessary.

**Fix:** Refactor to use database aggregation or paginate in batches.

#### Issue 1c: `migrateToEncryptedStorage()` - Lines 517-542
```swift
for session in try modelContext.fetch(FetchDescriptor<StoredSleepSession>()) {
    // ... processes each in sequence
}
```
**Problem:** Fetches ALL sessions, ALL summaries, and ALL profiles into memory without limits. For users with years of data, this is catastrophic.

**Impact:** CRITICAL - Runs on app launch. Can cause immediate OOM crash on first run after update.

**Fix:** Fetch and process in batches (e.g., 500 sessions at a time).

---

### 2. **Unlimited Historical Data Loading in ViewModels**

**File:** `Better/Features/Protocol/ProtocolComparisonDashboardViewModel.swift`

#### Issue 2a: `loadData()` - Lines 102-103
```swift
let sessions = try await localRepository.fetchCachedSessions(from: startDate, to: now)
let adherence = try await localRepository.fetchAdherence(from: startDate, to: now)
```
**Problem:** Fetches 60 days of ALL sessions and adherence records at once with zero limits.

**Impact:** HIGH - For active users with multiple sessions per night, this could be 180+ sessions + 180+ adherence records all loaded simultaneously.

**Fix:** 
- Add `fetchLimit` to the FetchDescriptor in `fetchCachedSessions`
- Or refactor to compute analysis on a rolling window instead of loading everything upfront

---

### 3. **No Pagination or Memory Management in Sleep Dashboard**

**File:** `Better/Features/Sleep/SleepDashboardViewModel.swift`

#### Issue 3a: `buildSleepInsights()` - Lines 235-239
```swift
let start = calendar.date(byAdding: .day, value: -29, to: selectedDate) ?? ...
let end = calendar.date(byAdding: .day, value: 1, to: selectedDate) ?? ...
let comparisonSessions = try await localRepository.fetchCachedSessions(from: start, to: end)
```
**Problem:** Loads 30 days of sessions into memory every time insights are built. Combined with adherence fetch, this is multiple arrays of potentially 100+ items.

**Impact:** MEDIUM - Happens on every tab switch to Sleep or date selection.

---

## Summary of Memory Leaks/Issues

| Issue | File | Line(s) | Severity | Impact |
|-------|------|---------|----------|--------|
| fetchDataInventory loads all sessions | LocalDataRepository | 551 | CRITICAL | App crash on privacy operations |
| migrateToEncryptedStorage no pagination | LocalDataRepository | 517-542 | CRITICAL | App crash on app launch (post-update) |
| fetchAvailableSleepDates unbounded | LocalDataRepository | 68-84 | HIGH | Month view OOM |
| ProtocolComparison loads 60 days unbound | ProtocolComparisonDashboardViewModel | 102-103 | HIGH | Dashboard tab crash with large history |
| buildSleepInsights loads 30 days unbound | SleepDashboardViewModel | 235-239 | MEDIUM | Sleep tab slowdown/memory spikes |

---

## Recommended Fixes (Priority Order)

### 🔴 CRITICAL - Fix First (Causes Crashes)

1. **Fix `migrateToEncryptedStorage()` - Add batch processing**
   - Fetch and process in chunks of 500 records
   - Add `Task.yield()` between batches (already present but needs larger batches)
   - This prevents OOM on first app launch after update

2. **Fix `fetchDataInventory()` - Use count instead of fetch all**
   - Replace `modelContext.fetch()` with `modelContext.fetchCount()`
   - Dramatically faster and zero memory overhead

### 🟠 HIGH - Fix Second (Causes Hangs/Jank)

3. **Add fetch limits to `fetchAvailableSleepDates()`**
   - Add `descriptor.fetchLimit = 500` to cap monthly data
   - If more sessions exist, fetch summaries from database layer instead
   - Or refactor repository to provide pre-aggregated month summaries

4. **Add pagination to Protocol Comparison**
   - Limit `fetchCachedSessions()` results with a fetch cap
   - Refactor analysis service to work on 30-day rolling windows incrementally
   - Cache computed results instead of re-computing entire 60-day window each time

### 🟡 MEDIUM - Fix Third (Improves Responsiveness)

5. **Optimize Sleep Dashboard insights building**
   - Cache the 30-day session/adherence data instead of re-fetching
   - Use `.task()` modifier correctly to avoid re-running on view refreshes
   - Debounce rapid date selections

---

## Verification Steps

1. **Memory profiling** - Use Xcode's Memory Graph Debugger:
   - Open app, navigate to Protocol Comparison
   - Let it load, then take a memory snapshot
   - Should show hundreds of SleepSession objects in memory

2. **Stress test** - Create a test with 100+ sleep sessions:
   - Verify app doesn't crash during migration
   - Check memory usage stays under 50MB

3. **Regression test** - Verify fixes:
   - App should use <30MB on Sleep tab
   - Month navigation should be instant
   - Protocol Comparison should not spike memory on load
