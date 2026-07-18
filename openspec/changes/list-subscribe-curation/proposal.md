## Why

Derzeit zeigt die `ListDetailView` die Schaltfläche „Subscribe to list" nur für Moderationslisten (`.moderation`) an. Benutzer können sich nicht für Kurationslisten (`.internal`, `.regular`) anmelden, obwohl Bluesky dies unterstützt. Dies schränkt die Funktionalität der App ein, wenn Benutzer Kurationslisten abonnieren möchten, die sie nicht besitzen.

## What Changes

- Die Bedingung in `ListDetailView` wird erweitert, sodass der `ListDetailSubscribeSection` auch für Kurationslisten (`.internal` und `.regular`) angezeigt wird, wenn der Benutzer die Liste nicht besitzt.
- Der existierende Subscribe/Unsubscribe-Mechanismus (`subscribeToModerationList` / `unsubscribeFromModerationList`) wird für alle Listenarten verwendet, da die AT-Protocol-API-Endpunkte (`app.bsky.graph.muteActorList` / `unmuteActorList`) listenartunabhängig funktionieren.
- Die `isSubscribed`-Abfrage (`isSubscribedToModerationList`) wird ebenfalls für Kurationslisten erweitert.
- Der Abfrage-Check beim Laden der Listendetailansicht (`loadSubscriptionState` o.ä.) wird für alle nicht-eigenen Listen durchgeführt, nicht nur für `.moderation`.
- Die Lokalisierungsschlüssel bleiben unverändert, da „Subscribe" / „Unsubscribe" bereits generisch genug sind.
- Die iPad-Variante (`iPadListDetailView` falls existent) wird ebenfalls angepasst.

## Capabilities

### New Capabilities
- `list-subscribe-curation`: Möglichkeit, sich für Kurationslisten (`.internal`, `.regular`) anzumelden und abzumelden, wenn man die Liste nicht besitzt.

### Modified Capabilities
- *Keine* — bestehende Specs werden nicht auf Anforderungsebene geändert.

## Impact

- `Sources/Features/Lists/ListDetailView.swift:455` — Bedingung von `.moderation` auf `!isOwnedList` (alle nicht-eigenen Listen) erweitern
- `Sources/Features/Lists/ListDetailView+Helpers.swift:123,133,135` — `loadSubscriptionState` und verwandte Methoden prüfen/erweitern
- `Sources/Features/Lists/ListDetailSubscribeSection.swift` — unverändert (generisch genug)
- `Sources/Domain/Services/LiveBlueskyClient.swift` — `subscribeToModerationList`/`isSubscribedToModerationList` funktionieren bereits listenartunabhängig; ggf. Methodennamen für Klarheit umbenennen (optional)
- `Sources/Domain/Services/BlueskyListServicing.swift` — Protokoll unverändert (API-Endpunkte sind listenartunabhängig)
- iPad `iPadListDetailView` (falls vorhanden) — gleiche Bedingung anpassen
- Lokalisierungsdateien (16 JSON-Dateien) — keine neuen Schlüssel nötig
