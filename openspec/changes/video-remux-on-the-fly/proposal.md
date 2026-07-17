## Why

Der aktuelle Video-Download-Prozess produziert immer eine `.ts`-Zwischendatei (Transport Stream), die nach erfolgreichem Remux zu `.mp4` gelöscht wird. Wenn der Remux fehlschlägt — z.B. weil das `FileHandle` noch offen ist oder `AVAsset` den konkatenierten TS-Stream nicht lesen kann — bleibt die `.ts`-Datei im Download-Ordner liegen. Der Nutzer sieht unbrauchbare TS-Dateien statt abspielbarer MP4s.

Ein "on-the-fly"-Ansatz, bei dem die HLS-Segmente direkt in eine `.mp4`-Datei geschrieben werden, eliminiert den Zwischenschritt vollständig. Kein TS-Zwischenformat, kein separater Remux-Pass, keine liegengebliebenen TS-Dateien.

## What Changes

- **Entfernen** der TS-Konkatenation und des separaten `VideoRemuxer.remuxToMP4`-Aufrufs
- **Neue Logik**: Während des Segment-Downloads wird ein `AVAssetWriter` (`.mp4`) geöffnet. Jedes heruntergeladene Segment wird via `AVAssetReader` gelesen und die Samples direkt in den `AVAssetWriter` geschrieben
- PTS/DTS-Offset-Management: Jedes TS-Segment beginnt bei Timestamp 0 → kumulativer Offset pro Segment
- Fehlschlag-Handling: Wenn der Writer fehlschlägt, wird die `.mp4`-Datei verworfen; es entstehen keine `ts`-Reste
- `VideoRemuxer`-Enum wird obsolet und entfernt

## Capabilities

### New Capabilities
- `video-remux-on-the-fly`: Video-Downloads schreiben Segmente direkt in `.mp4`, ohne `.ts`-Zwischendatei

### Modified Capabilities
- *Keine* — bestehende Specs bleiben unverändert

## Impact

- `Sources/Domain/Services/MediaDownloadService.swift` — `downloadVideo()` neu implementiert, `VideoRemuxer` entfernt
- Keine API-Änderungen, keine neuen Dependencies
- Keine Änderungen an `MediaBrowserViewModel` oder `MediaBrowserView`
