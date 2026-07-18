## Context

Die `ListDetailView` (iPhone) zeigt derzeit den `ListDetailSubscribeSection` nur für Moderationslisten an (`currentList.kind == .moderation`). Kurationslisten (`.internal`, `.regular`) bekommen diesen Abschnitt nicht, obwohl die zugrunde liegenden AT-Protocol-Endpunkte (`app.bsky.graph.muteActorList` / `unmuteActorList`) listenartunabhängig arbeiten.

Die iPad-Variante (`iPadListDetailView`) hat überhaupt keine Subscribe/Unsubscribe-Funktionalität.

**Aktueller Code-Flow (iPhone):**
1. `ListDetailView.content()` prüft `!isOwnedList, currentList.kind == .moderation` → zeigt `ListDetailSubscribeSection`
2. `loadSubscriptionStateIfNeeded()` prüft `!isOwnedList, currentList.kind == .moderation` → bricht ab, wenn nicht erfüllt
3. Die API-Methoden `subscribeToModerationList` / `unsubscribeFromModerationList` / `isSubscribedToModerationList` sind bereits generisch

**Aktueller Code-Flow (iPad):**
- `iPadListDetailView` hat keine Subscription-Funktionalität

## Goals / Non-Goals

**Goals:**
- Subscribe/Unsubscribe für alle nicht-eigenen Listen in der iPhone-`ListDetailView` anzeigen
- Subscribe/Unsubscribe in der iPad-`iPadListDetailView` integrieren
- Minimale Änderungen — die bestehenden API-Methoden und das UI (`ListDetailSubscribeSection`) wiederverwenden

**Non-Goals:**
- Neue API-Endpunkte oder Backend-Änderungen
- Neue Lokalisierungsschlüssel
- Änderung des Subscription-Verhaltens (es bleibt dasselbe `muteActorList`/`unmuteActorList`-Muster)
- Refactoring der Methodennamen (bleiben `subscribeToModerationList` etc.)

## Decisions

### Decision 1: Bedingung in `ListDetailView` von `.moderation` auf `!isOwnedList` erweitern

**Ansatz:** Entferne den `currentList.kind == .moderation`-Check aus beiden Stellen in `ListDetailView.swift`:
- Zeile 455: `if !isOwnedList, currentList.kind == .moderation` → `if !isOwnedList`
- `ListDetailView+Helpers.swift` Zeile 121: `guard !isOwnedList, currentList.kind == .moderation` → `guard !isOwnedList`

**Alternativen erwogen:**
- Nur `.internal` und `.regular` zusätzlich erlauben (`if !isOwnedList, currentList.kind != .internal && currentList.kind != .regular && currentList.kind != .moderation` → komplizierter, kein Vorteil)
- **Entschieden für `!isOwnedList`**: Einfacher, alle nicht-eigenen Listen abdeckend, zukunftssicher falls neue List-Arten hinzukommen.

### Decision 2: `ListDetailSubscribeSection` aus `ListDetailView`-Extension in eigene Datei auslagern

**Ansatz:** `ListDetailSubscribeSection` ist derzeit eine Extension-`struct` in `ListDetailView`. Um sie in `iPadListDetailView` wiederzuverwenden, wird sie in eine eigenständige Datei (`Sources/Shared/Components/ListDetailSubscribeSection.swift`) verschoben.

**Alternativen erwogen:**
- Die Section in der Extension belassen und in `iPadListDetailView` duplizieren → Code-Duplikation
- **Entschieden für Auslagerung**: Wiederverwendbarkeit, kein Duplikat

### Decision 3: iPad-Integration

**Ansatz:** `iPadListDetailView` bekommt:
- Neue `@State`-Properties: `isSubscribedToModerationList`, `subscribeError`, `isSubscribing`
- Einen `.task`-Block, der `loadSubscriptionStateIfNeeded` aufruft (oder die Logik direkt ausführt)
- `ListDetailSubscribeSection` im `listHeader` oder als separate Section

**Platzierung:** Unter der Listenbeschreibung im `listHeader`, vor den Action-Buttons — analog zur iPhone-Variante, wo sie nach dem Timeline-Link erscheint.

## Risks / Trade-offs

- **[Risk] API-Endpunkte könnten für Kurationslisten anders antworten** → Die AT-Protocol-Endpunkte `muteActorList`/`unmuteActorList` akzeptieren jede Listen-URI; das `viewer.muted`-Feld in `getList` existiert für alle List-Arten. Geringes Risiko.
- **[Risk] Verwirrung bei Nutzern:** „Subscribe" für Kurationslisten ist technisch ein „Mute" → Die UI verwendet bereits neutrale Begriffe („Subscribe"/„Unsubscribe"), nicht „Mute"/„Unmute". Akzeptabel.
- **[Trade-off] Methodennamen bleiben `...ModerationList`:** Die API-Methoden heißen weiterhin `subscribeToModerationList`, obwohl sie jetzt für alle List-Arten genutzt werden → Kein Refactoring in diesem Change, um das Diff minimal zu halten. Kann in einem separaten Cleanup angegangen werden.

## Migration Plan

1. Bedingungen in `ListDetailView.swift` und `ListDetailView+Helpers.swift` ändern
2. `ListDetailSubscribeSection` in eigene Datei auslagern
3. `iPadListDetailView` um Subscribe/Unsubscribe erweitern
4. Build & Test mit `make build`
5. Keine Datenbank-/Schema-Migration nötig

**Rollback:** Änderungen sind rein additiv (bzw. Bedingungs-Erweiterungen). Rollback durch Revert der zwei geänderten Dateien + Entfernen der neuen Komponenten-Datei.

## Open Questions

- *Keine*
