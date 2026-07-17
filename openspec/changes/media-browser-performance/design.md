## Context

`MediaBrowserViewModel.rebuildDerivedState()` wird bei jedem `appendItems`-Aufruf (pro Seite) und jedem `filter`-Wechsel ausgeführt. Bei N geladenen Items:

```swift
func rebuildDerivedState() {
    imageCount = items.reduce(into: 0) { count, item in   // O(N)
        if item.type == .image { count += 1 }
    }
    videoCount = items.count - imageCount
    filteredItems = items.filter { $0.type == .image }     // O(N)
    // ...
}
```

Das sind 2 vollständige Array-Scans pro Seitenladung. Bei 10 Seiten à 100 Items = 2000 Scans über wachsende Arrays (1+2+...+1000 Items = ~500k Element-Vergleiche). Auf dem Main Thread.

Zusätzlich ist `availableFilters` eine computed property:
```swift
var availableFilters: [MediaFilter] {
    if items.contains(where: { $0.type == .image }) { ... }  // O(N) jedes Mal
    if items.contains(where: { $0.type == .video }) { ... }  // O(N) jedes Mal
}
```
Diese wird bei **jedem** SwiftUI Body-Render ausgewertet — mehrmals pro Frame.

## Goals / Non-Goals

**Goals:**
- `appendItems` in O(k) statt O(N+k) — nur die neuen Items scannen
- `availableFilters` in O(1) — gecachter Wert
- `filteredItems` nur bei echten Änderungen neu berechnen

**Non-Goals:**
- Änderungen an `ThumbnailImageView` (arbeitet bereits effizient)
- Änderungen am Paginierungsmechanismus
- Virtualisierung der Grid-Darstellung (LazyVGrid handled das)

## Decisions

### Decision 1: Inkrementelle Zähler in `appendItems`

**Ansatz:** Statt `reduce` über alle Items werden nur die neu angehängten Items gezählt:

```swift
private func appendItems(_ newItems: [MediaItem]) {
    guard !newItems.isEmpty else { return }
    for item in newItems {
        if item.type == .image { imageCount += 1 } else { videoCount += 1 }
    }
    items = Self.sortedItems(items + newItems)
    rebuildFilteredItems()
}
```

`replaceItems` macht weiterhin einen Single-Pass-Scan (korrekt, da alter Zustand verworfen wird).

### Decision 2: `availableFilters` als stored property

**Ansatz:** `@Published private(set) var availableFilters: [MediaFilter] = []` — wird beim ersten Image/Video auf `[.images]` bzw. `[.images, .videos]` gesetzt. Nie zurückgesetzt (einmal gefunden, bleibt verfügbar).

```swift
private func appendItems(_ newItems: [MediaItem]) {
    ...
    if availableFilters.count < 2 {
        if newItems.contains(where: { $0.type == .video }), !availableFilters.contains(.videos) {
            availableFilters.append(.videos)
        }
    }
}
```

Da `availableFilters` nur wachsen kann (nie schrumpfen), ist der Check der neuen Items ausreichend.

### Decision 3: `rebuildDerivedState` in zwei Methoden aufteilen

**Ansatz:**
- `rebuildFilteredItems()` — nur `filteredItems` neu berechnen (O(N), aber nur bei echten Änderungen)
- `rebuildDerivedState()` — ruft `rebuildFilteredItems()` + setzt `summaryText`

Der `filter.didSet`-Observer ruft nur `rebuildFilteredItems()` auf. `appendItems`/`replaceItems` rufen `rebuildFilteredItems()` auf (Zähler werden bereits inkrementell aktualisiert).

## Risks / Trade-offs

- **[Risk] Inkrementelle Zähler geraten außer Sync** → `replaceItems` macht Full-Scan als Ground-Truth-Reset → jede neue Suche/Refresh korrigiert etwaige Diskrepanzen
- **[Trade-off] `availableFilters` schrumpft nie** → Wenn alle Videos entfernt würden (nicht möglich im aktuellen Design, da Items nur wachsen), bliebe `.videos` in der Liste → akzeptabel, Filter auf leere Liste ist harmlos

## Migration Plan

1. `rebuildDerivedState()` aufspalten
2. `appendItems` und `replaceItems` anpassen
3. `availableFilters` von computed auf stored umbauen
4. Build + manueller Test mit großem Account

Keine Daten-Migration, keine API-Änderungen.
