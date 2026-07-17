## Why

Der Media Browser wird bei einer großen Anzahl geladener Medien (1000+ Items) träge. Jeder Seitenabruf triggert `rebuildDerivedState()`, das zwei O(n)-Scans über das gesamte `items`-Array durchführt: einen `reduce(into:)` zum Zählen von Bildern/Videos und ein `filter` zum Neuerstellen der gefilterten Liste. Zusätzlich scannt `availableFilters` bei jedem Body-Render alle Items. Diese synchronen Hauptthread-Operationen blockieren die UI bei wachsender Item-Anzahl zunehmend.

## What Changes

- **Inkrementelle Zähler**: `imageCount` und `videoCount` werden beim Anhängen von Items inkrementell aktualisiert statt per vollständigem `reduce`-Scan
- **Gecachte `availableFilters`**: Wird als `@Published`-Property gecacht und nur bei Änderung neu berechnet (wenn erstes Image/Video erscheint)
- **Lazy `filteredItems`**: Neuberechnung nur bei `items`- oder `filter`-Änderung, nicht bei jedem `rebuildDerivedState`-Aufruf (der bereits durch `didSet` getriggert wird)
- `rebuildDerivedState()` wird schlanker und schneller

## Capabilities

### New Capabilities
- `media-browser-performance`: Inkrementelle Zähler und gecachte Derivationen für flüssige UI bei großen Medienmengen

### Modified Capabilities
- *Keine*

## Impact

- `Sources/Features/Lists/Profile/MediaBrowserViewModel.swift` — `rebuildDerivedState`, `appendItems`, `replaceItems`, `availableFilters`
- Keine View-Änderungen, keine API-Änderungen
