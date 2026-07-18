## 1. iPhone — Bedingung erweitern

- [ ] 1.1 `ListDetailView.swift:455`: Bedingung von `!isOwnedList, currentList.kind == .moderation` auf `!isOwnedList` ändern, sodass `ListDetailSubscribeSection` für alle nicht-eigenen Listen erscheint
- [ ] 1.2 `ListDetailView+Helpers.swift:121`: `loadSubscriptionStateIfNeeded` — Guard von `!isOwnedList, currentList.kind == .moderation` auf `!isOwnedList` ändern, sodass der Subscription-Status für alle nicht-eigenen Listen geladen wird
- [ ] 1.3 `ListDetailView+Helpers.swift:121`: `isSubscribedToModerationList = false` im else-Zweig entfernen, da jetzt alle nicht-eigenen Listen den API-Check durchlaufen

## 2. Gemeinsame Komponente auslagern

- [ ] 2.1 `ListDetailSubscribeSection` aus `ListDetailView`-Extension (`Sources/Features/Lists/ListDetailSubscribeSection.swift`) in eigenständige Datei `Sources/Shared/Components/ListDetailSubscribeSection.swift` verschieben und `public`/`internal`-Zugriff anpassen
- [ ] 2.2 `ListDetailView.swift`: Import der neuen Datei prüfen (gleiches Modul, kein expliziter Import nötig)

## 3. iPad — Subscribe/Unsubscribe integrieren

- [ ] 3.1 `iPadListDetailView.swift`: `@State`-Properties für `isSubscribedToModerationList`, `subscribeError`, `isSubscribing` hinzufügen
- [ ] 3.2 `iPadListDetailView.swift`: `ListDetailSubscribeSection` im `listHeader` (unter der Beschreibung, vor den Action-Buttons) einbauen, nur wenn `!isOwnedList`
- [ ] 3.3 `iPadListDetailView.swift`: `.task`-Block ergänzen, der `isSubscribedToModerationList` via `container.list.isSubscribedToModerationList(...)` abfragt

## 4. Validierung

- [ ] 4.1 Build mit `make build` durchführen und sicherstellen, dass keine Kompilierfehler auftreten
- [ ] 4.2 `make lint` ausführen und ggf. Warnungen beheben
- [ ] 4.3 `make test` ausführen
- [ ] 4.4 Manuell testen: Subscribe/Unsubscribe für eine nicht-eigene `.moderation`-Liste (sollte unverändert funktionieren)
- [ ] 4.5 Manuell testen: Subscribe/Unsubscribe für eine nicht-eigene `.internal`- oder `.regular`-Liste
- [ ] 4.6 Manuell testen: Eigene Liste zeigt keinen Subscribe-Bereich
