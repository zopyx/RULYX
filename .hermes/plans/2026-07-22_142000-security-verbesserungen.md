# RULYX — Sicherheits-Verbesserungsplan (Top 10 Prioritäten)

> **Goal:** Alle identifizierten Sicherheitslücken der App schliessen — von hardcodierten API-Keys bis zu lückenhaftem Pinning.
>
> **Scope:** Nur die 10 priorisierten Findings aus der Sicherheitsanalyse.
> Keine Refactoring-Aufgaben, keine Feature-Änderungen, kein Test-Erstausbau (ausser Verifikation).
>
> **Branch:** `security-audit-fixes-2026-07`

---

## Task 1: Hardcodierten Klipy-API-Key aus dem Binary entfernen

**Objective:** Der API-Key darf nicht im kompilierten Binary sichtbar sein. Stattdessen via Build-Time-Secret oder Server-Proxy einspielen.

**Betroffene Dateien:**
- Modify: `Sources/Domain/Services/GIFService.swift:49`
- Modify: `project.yml` (zusätzliche Build-Einstellungen)
- Create: `.env.secret` (nur lokal, nicht committed)

**Problem:**
```swift
private static let bundledAPIKey = "W3FgVTePIgmlS4FEj8oF2xbMzXgwx3QGPX3pYEmrQZIvH4eRB0sin6PKqzun4f6R"
```

Dieser String wird in die Binary kompiliert und ist via `strings`/Hopper/Ghidra extrahierbar.

**Option A (empfohlen):** xcconfig + Info.plist Injection
1. `project.yml` um `configs`-Einstellung erweitern: `KLIPY_API_KEY = $(KLIPY_API_KEY)`
2. In `Info.plist` einen Key `KlipyAPIKey` mit `$(KLIPY_API_KEY)` einfügen
3. Im CI/CD wird der Key via Umgebungsvariable gesetzt
4. In `GIFService` wird der Key via `Bundle.main.object(forInfoDictionaryKey:)` gelesen
5. `bundledAPIKey` entfernen, `seedKeyIfNeeded()` behalten für Migration bestehender Keys

**Option B (für dieses Projekt praktikabler):** `GIFService` erwartet Key in einer `.xcconfig`-Datei, die in `.gitignore` ist.

**Verifikation:**
```bash
# Prüfen, dass der alte Key nicht mehr im Binary steckt
strings build/RULYX.app/RULYX | grep -c "W3FgVTePIgmlS4FEj8oF2xb"
# → 0

# Prüfen, dass Keychain-Seeding noch funktioniert (Integration)
```

---

## Task 2: Certificate Pinning-Vereinheitlichung

**Objective:** Zwei separate Pinning-Implementierungen zusammenführen, `appViewHTTPClient` absichern, dynamische PDS-Hosts mit Fallback-Pinning schützen.

**Betroffene Dateien:**
- Modify: `Sources/Domain/Services/HTTPClient.swift` (CertificatePinningDelegate behalten, verbessern)
- Modify: `Sources/Domain/Services/BlueskyRequestExecutor.swift` (PinningDelegate entfernen, auf HTTPClient delegieren)
- Modify: `Sources/Domain/Services/LiveBlueskyClient.swift` (appViewHTTPClient mit Pinning oder zumindest Observierung)
- Potentiell: `Sources/Domain/Services/HTTPClient.swift` (Pinning-Fallback-Strategie für unbekannte Hosts)

### Schritt 1: Pinning aus BlueskyRequestExecutor entfernen

`BlueskyRequestExecutor.swift` Zeilen 196–241 (`PinningDelegate`-Klasse) ENTFERNEN. Der `BlueskyRequestExecutor` verwendet bereits `HTTPClient` für alle Requests — das Pinning läuft dort bereits für die Default-Hosts.

Aktuell erstellt `BlueskyRequestExecutor` eine SEPARATE `URLSession` mit eigenem PinningDelegate, der NUR `bsky.social` pinnt. Das ist redundant und schwächer als das `HTTPClient.defaultPinnedHashes`.

```patch
- private final class PinningDelegate: NSObject, URLSessionDelegate {
-     private static let pinnedSPKIHashes = ["Va6hs2tSCkc4CWC91P6Bga2S05J/R2R+Tp4WPAv7Hlc="]
-     func urlSession(… didReceive challenge: …) { … }
- }
- private func extractSPKI(from certDER: Data) -> Data? { … }
- private func readLength(from data: Data, index: inout Data.Index) -> Int? { … }
- private extension Data { subscript(safe index: Index) -> UInt8? { … } }
```

Und `static func makePinnedSession()` entfernen oder mindestens die private Session nicht mehr nutzen.

### Schritt 2: `appViewHTTPClient` absichern

`LiveBlueskyClient.swift:32`:
```swift
private let appViewHTTPClient = HTTPClient()
```

Dieser Client hat KEIN Pinning. Der Kommentar sagt "no certificate pinning because PDS hosts are dynamic" — das ist zwar nachvollziehbar, aber immer noch unsicher.

Lösung: Einen **Opportunistic Pinning**-Ansatz implementieren:
1. Bekannte Hosts (`bsky.social`, `api.bsky.app`, `clearsky.app`) werden gepinnt
2. Für unbekannte PDS-Hosts: beim ersten Verbinden den Hash speichern, bei Abweichung warnen (und konfigurierbar: Verbindung erlauben oder blocken)

Alternativ mindestens: TLS 1.2+ erzwingen und Schwachstellen-Checks (wie `HTTPClient.CertificatePinningDelegate` es bereits für den leeren-Fall tut).

### Schritt 3: Default-Pinning für `bsky.social` auch in `LiveBlueskyClient`

Sicherstellen, dass der Haupt-`httpClient` in `LiveBlueskyClient` mit `HTTPClient.defaultPinnedHashes` erstellt wird — das IST bereits der Fall in `init()`.

**Verifikation:**
```bash
# Noch keine Build-Tests, aber:
make lint
# → keine Compiler-Fehler durch entfernte Typen
```

---

## Task 3: App-Passwort-Memory-Exposure reduzieren

**Objective:** Das Bluesky-App-Passwort soll nur minimal im Speicher verbleiben. Nach erfolgreicher Session-Erstellung wird es aus dem Speicher entfernt.

**Betroffene Dateien:**
- Modify: `Sources/Domain/Services/BlueskySessionService.swift`
- Modify: `Sources/Domain/Services/AccountStore.swift`

### Schritt 1: Passwort-Argument nach Session-Auth aus Speicher entfernen

In `BlueskySessionService.performAuthenticatedRequest()` wird `appPassword` über den gesamten Retry-Zyklus (3 Attempts) gehalten. Das Passwort wird nur für `cachedSession()` → `recreateSession()` benötigt.

Änderung: `appPassword` sofort nach `cachedSession()` lokal nullen:

```swift
func performAuthenticatedRequest<Response>(
    account: AppAccount,
    appPassword: String?,
    operation: (BlueskySession) async throws -> Response
) async throws -> Response {
    var authSession = try await cachedSession(for: account, appPassword: appPassword)
    // Invalidate password reference after initial session acquisition
    let password: String? = nil  // shadow appPassword

    for attempt in 0 ..< 3 {
        do {
            let response = try await operation(authSession)
            // ... return response
        } catch BlueskyAPIError.unauthorized {
            guard attempt < 2 else { throw BlueskyAPIError.unauthorized }
            // Re-fetch password from keychain if needed for recoverSession
            authSession = try await recoverSession(
                currentSession: authSession,
                for: account,
                appPassword: accountStore.appPassword(for: account)  // fresh fetch
            )
            // ...
        }
    }
}
```

### Schritt 2: `recreateSession` nur bei Bedarf mit Keychain-Read

In `cachedSession()` wird `recreateSession()` aufgerufen, das intern `authenticate(handle:appPassword:)` aufruft. Das Passwort wird von `cachedSession`'s Caller (`performAuthenticatedRequest`) übergeben.

Statt das Passwort durchzureichen, könnte `recreateSession` direkt den Keychain-Read machen — dann ist das Passwort nur innerhalb dieser einen Funktion im Speicher.

**Verifikation:**
```swift
// Accounts-Store API: Password wird nur beim AddAccount noch durchgereicht
// Nach Session-Erfolg: `appPassword`-Parameter sollte in Debugger nicht mehr lesbar sein
```

---

## Task 4: AppLock-Lockout persistieren & Passcode-Fallback korrigieren

**Objective:** Fehlversuche + Lockout-Deadline müssen App-Neustart überleben. Biometrie muss auf Passcode fallen, nicht nur auf 60s-Warten.

**Betroffene Dateien:**
- Modify: `Sources/Shared/Support/AppLockManager.swift`

### Schritt 1: Lockout in Keychain persistieren

```swift
// Neue Properties
private let lockoutKeychainService = "com.ajung.RULYX.lockout"
private let consecutiveFailuresAccount = "consecutiveFailures"
private let lockoutUntilAccount = "lockoutUntil"

// Lockout speichern
private func persistLockout() {
    try? keychain.save("\(consecutiveFailedAttempts)", service: lockoutKeychainService, account: consecutiveFailuresAccount)
    if let until = lockoutUntil {
        try? keychain.save("\(until.timeIntervalSince1970)", service: lockoutKeychainService, account: lockoutUntilAccount)
    }
}

// Lockout laden
private func loadLockout() {
    if let val = try? keychain.read(service: lockoutKeychainService, account: consecutiveFailuresAccount),
       let count = Int(val) {
        consecutiveFailedAttempts = count
    }
    if let val = try? keychain.read(service: lockoutKeychainService, account: lockoutUntilAccount),
       let ts = TimeInterval(val) {
        lockoutUntil = Date(timeIntervalSince1970: ts)
    }
}
```

### Schritt 2: `deviceOwnerAuthenticationWithBiometrics` → `deviceOwnerAuthentication`

`authenticate()` verwendet `.deviceOwnerAuthenticationWithBiometrics`. Das muss `.deviceOwnerAuthentication` werden (inkludiert Passcode-Fallback):

```swift
// ALT:
let success = try await context.evaluatePolicy(
    .deviceOwnerAuthenticationWithBiometrics,  // KEIN Passcode-Fallback!
    localizedReason: ...
)

// NEU:
let success = try await context.evaluatePolicy(
    .deviceOwnerAuthentication,  // mit Passcode-Fallback
    localizedReason: ...
)
```

### Schritt 3: Lockout-Reset bei erfolgreicher Authentifizierung + Persistenz

```swift
if success {
    isLocked = false
    consecutiveFailedAttempts = 0
    lockoutUntil = nil
    persistLockout()  // NEU
}
```

**Verifikation:**
```swift
// AppLock einschalten, 5x falschen Finger/Face zeigen
// App killen, neu starten
// → Lockout muss noch aktiv sein (60s)
// Nach Ablauf: normaler Passcode-Fallback, nicht nur Biometrie
```

---

## Task 5: Jailbreak Detector entfernen oder in echten Schutz umwandeln

**Objective:** Aktuell ist der Detector toter Code (nirgends aufgerufen) und ohnehin trivial umgehbar. Entweder echten Schutz einbauen oder den Code entfernen.

**Betroffene Dateien:**
- Modify/Delete: `Sources/Shared/Support/JailbreakDetector.swift`
- Modify: `Sources/App/RULYXApp.swift` (Integration)

**Entscheidung:** Aus der Analyse (und da die App keine Bank/Health-App ist) ist Jailbreak-Erkennung für eine Moderation-App nicht kritisch. Empfohlen: Code entfernen (vereinfacht Wartung, vermeidet falsche Sicherheitsillusion).

Falls Beibehaltung gewünscht: Robustere Check-Methoden einbauen:
- `fork()`-Test (erzeugt Kindprozess, scheitert in Sandbox)
- `dlopen()` auf Systembibliotheken ausserhalb Sandbox
- Symlink-Check auf `/etc` und `/var`
- Berechtigungsprüfung (erwartete vs. tatsächliche Werte)
- Mindestens eine Reaktion: App schliesst oder zeigt Warnung

**Verifikation:**
```bash
search_files("JailbreakDetector", path="Sources/")
# → 0 wenn gelöscht, oder >0 wenn mit Reaktivierung
```

---

## Task 6: Model-Downloads mit SHA256-Integritätsprüfung

**Objective:** Jeder GGUF-Model-Download muss vor Verwendung auf Integrität geprüft werden.

**Betroffene Dateien:**
- Modify: `Sources/Domain/AI/LiveAIService.swift`
- Modify: `Sources/Domain/AI/model_manifest.json` (SHA256-Hashes hinzufügen)

### Schritt 1: SHA256-Hashes zum Catalog hinzufügen

`ModelBundle` um `sha256`-Property erweitern (oder manifest-basiert):

```swift
// existing:
ModelBundle(
    id: "phi-3-mini-q4",
    name: "Phi-3 Mini (Q4)",
    downloadURL: URL(string: "https://huggingface.co/...")!,
    fileSize: 2_350_000_000,
    ...
)

// neu mit sha256:
ModelBundle(
    id: "phi-3-mini-q4",
    name: "Phi-3 Mini (Q4)",
    downloadURL: URL(string: "https://huggingface.co/...")!,
    fileSize: 2_350_000_000,
    sha256: "a1b2c3d4e5f6...",  // NEU
    ...
)
```

### Schritt 2: Nach Download verifizieren

In `LiveAIService.download()`, nach erfolgreichem Download und vor `rebuildStates()`:

```swift
// Nach dem Download
if let expectedHash = model.sha256 {
    let fileURL = fileManager.localURL(for: model.id)
    let fileHandle = try FileHandle(forReadingFrom: fileURL)
    let data = fileHandle.readDataToEndOfFile()
    let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    guard hash == expectedHash.lowercased() else {
        try fileManager.delete(model.id)
        throw AIError("Model integrity check failed: SHA256 mismatch (expected \(expectedHash), got \(hash))")
    }
}
```

**Verifikation:**
```swift
// Test: Korrupte Datei (echo "xxx" > model.gguf) → Download muss fehlschlagen
// Test: Korrekte Datei → Download erfolgreich
```

---

## Task 7: InferenceEngine als regelbasiert kennzeichnen (keine Fake-AI)

**Objective:** Die UI/EULA/About-Seite muss klarstellen, dass die "Inference Engine" ein keyword-basiertes Rule-System ist, kein ML.

**Betroffene Dateien:**
- Modify: `Sources/Domain/AI/InferenceEngine.swift` (Doku)
- Modify: `Sources/Domain/AI/LiveAIService.swift` (complete-Methode)
- Modify: `Sources/Features/Lists/ModerationRulesView.swift` oder passende UI

### Schritt 1: Doku-Korrektur

`InferenceEngine.swift` Header:

```swift
/// A KEYWORD- AND RULE-BASED (NOT ML) text classification engine used for
/// on-device content moderation. This is NOT a machine learning model —
/// it uses hardcoded keyword matching, heuristic rules, and basic
/// word-frequency scoring.
```

### Schritt 2: `complete()`-Methode korrigieren

Aktuell simuliert `LiveAIService.complete()` einen LLM-Stream, gibt aber nur die `analyze()`-Ausgabe aus. Das ist irreführend.

Entweder:
- `complete()` entfernen (weil kein echter LLM verfügbar ist)
- Oder die Methode ehrlich als "analysis report" labeln und nicht als "completion"/"generation" bewerben

```swift
// ALT: "complete(prompt:using:)"
// NEU: "analyzePost(text:) -> String"
func analyzePost(text: String) -> String {
    engine.analyze(text: text)
}
```

### Schritt 3: Download-Fortschritt-Balken korrigieren

Die `ModelDownloadIndicator` zeigt für `phi-3-mini-q4` und `qwen3-1.7b-q8` an, dass sie heruntergeladen werden können — aber selbst nach Download gibt es KEINEN echten LLM. Der Download erzeugt eine Datei, die nie verwendet wird (`complete()` nutzt nur `InferenceEngine`).

Entweder:
- Modelle aus dem Katalog entfernen (weil sie nie genutzt werden)
- Echten CoreML/GGUF-Support implementieren
- Oder zumindest dokumentieren: "Model Download (currently unused — planned for future on-device ML)"

**Verifikation:**
```bash
search_files("complete|classify|analyze", path="Sources/Domain/AI/LiveAIService.swift")
# → Keine irreführenden "completion"-Referenzen mehr
```

---

## Task 8: AppLock `authenticate()` mit Passcode-Fallback

**Objective:** Der User muss bei Face-ID/Touch-ID-Fehlschlag auf den Geräte-Passcode ausweichen können, nicht nur 60s warten.

**Betroffene Dateien:**
- Modify: `Sources/Shared/Support/AppLockManager.swift`

Dies ist eine Korrektur von Task 4, Schritt 2 — hier die reine Policy-Änderung:

```patch
- let success = try await context.evaluatePolicy(
-     .deviceOwnerAuthenticationWithBiometrics,
-     localizedReason: String.localized("biometric.auth_reason")
- )
+ let success = try await context.evaluatePolicy(
+     .deviceOwnerAuthentication,
+     localizedReason: String.localized("biometric.auth_reason")
+ )
```

`.deviceOwnerAuthentication` fragt zuerst Face ID/Touch ID an, bietet aber "Passcode eingeben" als Aktion an, wenn Biometrie scheitert.

**Achtung:** Dadurch ist der 5-Fail-Lockout-Mechanismus der App technisch obsolet, weil der User stattdessen den Passcode nehmen kann. Dennoch beibehalten für den Fall, dass der Passcode ebenfalls falsch eingegeben wird.

**Verifikation:**
```swift
// AppLock einschalten
// Face ID ablehnen → "Passcode eingeben" erscheint
// Passcode korrekt eingeben → App entsperrt
```

---

## Task 9: Privacy Manifest um Face ID und fehlende API-Kategorien ergänzen

**Objective:** `PrivacyInfo.xcprivacy` muss alle genutzten API-Kategorien gemäss Apple-Dokumentation deklarieren.

**Betroffene Dateien:**
- Modify: `Sources/App/PrivacyInfo.xcprivacy`

### Fehlende Deklarationen:

**1. Face ID API** (`NSPrivacyAccessedAPICategoryFaceID`)
```
<dict>
    <key>NSPrivacyAccessedAPIType</key>
    <string>NSPrivacyAccessedAPICategoryFaceID</string>
    <key>NSPrivacyAccessedAPITypeReasons</key>
    <array>
        <string>42A4.1</string>
    </array>
</dict>
```
Begründung: Face ID wird für App-Lock (Zugriffsschutz) verwendet — Reason `42A4.1`.

**2. System Boot Time** (wenn `ProcessInfo.processInfo.systemUptime` verwendet wird — prüfen!)
Wenn verwendet:
```
<dict>
    <key>NSPrivacyAccessedAPIType</key>
    <string>NSPrivacyAccessedAPICategorySystemBootTime</string>
    <key>NSPrivacyAccessedAPITypeReasons</key>
    <array>
        <string>35F9.1</string>
    </array>
</dict>
```

**3. UserDefaults in AppStorage** (bereits deklariert — CA92.1 ✅)

**4. FileTimestamp** (bereits deklariert — C617.1 ✅)

**5. DiskSpace** (bereits deklariert — E174.1 ✅)

**Verifikation:**
```bash
# Xcode Privacy Report generieren
xcodebuild -project RULYX.xcodeproj -scheme RULYX -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO
# → Keine Privacy-Report-Warnungen
```

---

## Task 10: User-Agent auf app-spezifischen konstanten Wert umstellen

**Objective:** Statt zufälligem Browser-User-Agent einen aussagekräftigen, konstanten User-Agent verwenden.

**Betroffene Dateien:**
- Modify: `Sources/Domain/Services/UserAgentProvider.swift`
- Modify: `Sources/Domain/Services/HTTPClient.swift` (3 Stellen)

### Schritt 1: UserAgentProvider ändern

```swift
// ALT: Zufälliger Browser-UA
static var random: String {
    userAgents.randomElement()!
}

// NEU: Konstanter App-UA
static let appUserAgent = "RULYX/1.0.17 (iOS; Swift; com.ajung.RULYX)"
static let random = appUserAgent  // Kompatibilitätshalber
```

### Schritt 2: HTTPClient aktualisieren

Alle 3 Stellen in `HTTPClient.swift` wo `UserAgentProvider.random` verwendet wird, durch `UserAgentProvider.appUserAgent` ersetzen:

```patch
- request.setValue(UserAgentProvider.random, forHTTPHeaderField: "User-Agent")
+ request.setValue(UserAgentProvider.appUserAgent, forHTTPHeaderField: "User-Agent")
```

Oder `UserAgentProvider.random` selbst umbiegen (s.o.).

**Verifikation:**
```bash
# Test: Ein HTTP-Request loggen, prüfen User-Agent
# → "RULYX/1.0.17 (iOS; Swift; com.ajung.RULYX)"
```

---

## Anhang: Nicht priorisierte Verbesserungen

Folgende Punkte wurden identifiziert, sind aber für dieses Sprint nicht priorisiert:

| Issue | Begründung |
|---|---|
| `@unchecked Sendable` in 4 Klassen | Aktuell keine Race-Condition bekannt, Swift 6 Concurrency ist opt-in |
| iCloud-Account-Sync ohne Ende-zu-Ende-Verschlüsselung | Enthält nur öffentliche Daten (Handle, DID), kein Secret |
| Keychain-Zugriff als "überall lesbar" (`KlipyKeychainHelper.read()`) | Ist bereits in der App-Sandbox, kein Angriffsweg |
| Keine Biometrie beim Öffnen der App im Background | Absichtliches Design (nicht erzwingbar) |
|  `HTTPRequestDebugView` exponiert API-Traffic in der UI | Debug-Feature, benannt als solches |
