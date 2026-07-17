## 1. Inkrementelle Zähler

- [ ] 1.1 `appendItems` umschreiben: `imageCount`/`videoCount` inkrementell aus `newItems` hochzählen statt `rebuildDerivedState()`-Full-Scan
- [ ] 1.2 `replaceItems` umschreiben: Zähler aus neuem Array per Single-Pass berechnen statt `rebuildDerivedState()`-Full-Scan

## 2. Gecachte availableFilters

- [ ] 2.1 `availableFilters` von computed property zu `@Published private(set) var` ändern
- [ ] 2.2 In `appendItems`: `availableFilters` aktualisieren wenn erstes Video erscheint
- [ ] 2.3 In `replaceItems`: `availableFilters` aus neuem Array initial setzen

## 3. filteredItems-Logik straffen

- [ ] 3.1 `rebuildDerivedState()` umbenennen/aufspalten: `rebuildFilteredItems()` extrahieren
- [ ] 3.2 `filter.didSet` ruft nur `rebuildFilteredItems()` auf (nicht das komplette `rebuildDerivedState`)
- [ ] 3.3 `rebuildDerivedState()` entfernen oder zu Lightweight-Methoden reduzieren

## 4. Validierung

- [ ] 4.1 Build mit `make build`
- [ ] 4.2 Lint mit `swiftformat --lint` auf `MediaBrowserViewModel.swift`
- [ ] 4.3 Manueller Test: Account mit 1000+ Medien → Scrollen, Filter wechseln, Select/All — UI muss flüssig bleiben
