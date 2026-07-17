## Context

Current video download pipeline in `MediaDownloadService.downloadVideo()`:

```
1. HLS playlist parsen → segment URLs
2. Segments parallel downloaden → temp directory
3. Segmente zu .ts konkatenieren (FileHandle write)
4. AVAssetReader/AVAssetWriter remux .ts → .mp4 (VideoRemuxer)
5a. Erfolg: .ts löschen, .mp4 behalten
5b. Misserfolg: .ts bleibt liegen (Fallback)
```

Probleme des aktuellen Ansatzes:
- **Zwei I/O-Durchläufe**: TS schreiben + TS lesen + MP4 schreiben
- **FileHandle-Timing**: Remux schlägt fehl wenn Handle noch offen (Bug, gerade gefixt)
- **TS-Reste**: Bei Remux-Fehler bleiben unbrauchbare .ts-Dateien
- **Speicher**: TS-Datei liegt doppelt auf Platte während Remux

## Goals / Non-Goals

**Goals:**
- Segmente direkt in .mp4 schreiben — kein .ts-Zwischenschritt
- PTS/DTS-Kontinuität über Segmentgrenzen hinweg
- Fehlerfall: keine .mp4-Reste (cancelWriting)
- `VideoRemuxer`-Enum entfernen

**Non-Goals:**
- Neu-Encodierung (bleibt Passthrough mit `outputSettings: nil`)
- Thread-Safety-Änderungen am Segment-Download (bleibt TaskGroup-basiert)
- Änderung der Download-UI oder des Fortschritts-Reportings

## Decisions

### Decision 1: AVAssetWriter öffnen bevor Segmente eintreffen

**Ansatz:** `AVAssetWriter(outputURL: mp4URL, fileType: .mp4)` wird VOR der Segment-Download-Schleife initialisiert. Sobald das erste Segment vollständig ist, werden seine Tracks analysiert und die `AVAssetWriterInput`-Kanäle konfiguriert.

**Warum:** Writer muss vor dem ersten `append()` vollständig konfiguriert sein. Track-Informationen (Video/Audio, Codec) sind erst nach Download des ersten Segments verfügbar.

**Ablauf:**
1. `AVAssetWriter` für `.mp4` anlegen → Status: `.unknown`
2. Erstes Segment herunterladen → `AVAsset(url: segmentURL)` → Tracks laden
3. `AVAssetWriterInput` + `AVAssetReaderTrackOutput` pro Track anlegen (Passthrough)
4. `writer.startWriting()` + `writer.startSession(atSourceTime:)`
5. Samples vom ersten Segment schreiben
6. Für jedes weitere Segment: `AVAssetReader` → Samples mit Offset → `writer.append()`

### Decision 2: PTS/DTS-Offset über kumulative Dauer

**Ansatz:** Nach jedem vollständig geschriebenen Segment wird dessen Dauer (`asset.duration`) zum kumulativen Offset addiert. Das nächste Segment erhält diesen Offset auf alle Sample-Timestamps.

**Offset-Anwendung:**
```swift
let offset = CMTime(value: offsetValue, timescale: timescale)
let adjustedSample = CMSampleBufferCreateCopyWithNewTiming(
    allocator: kCFAllocatorDefault,
    sampleBuffer: originalSample,
    sampleTimingEntries: [CMSampleTimingInfo(
        duration: originalDuration,
        presentationTimeStamp: CMTimeAdd(originalPTS, offset),
        decodeTimeStamp: CMTimeAdd(originalDTS, offset)
    )]
)
```

**Alternativen erwogen:**
- `CMSampleBufferCreateCopy` mit `sampleTimingAdjustment` → API existiert, aber komplexer
- Manuelles Umschreiben der PTS/DTS via `CMBlockBuffer` → zu low-level
- **Entschieden:** `CMSampleBufferCreateCopyWithNewTiming` — offizielle API, gut dokumentiert

### Decision 3: AVAssetReader pro Segment, AVAssetWriter global

**Ansatz:** Für jedes Segment wird ein neuer `AVAssetReader` erstellt (kurzlebig, pro Segment). Der `AVAssetWriter` lebt über die gesamte Download-Dauer.

**Warum:** `AVAssetReader` kann nicht mehrere Assets lesen. Segmente sind separate Dateien. Writer ist ein kontinuierlicher Sink.

**Reader-Lebenszyklus:**
```swift
// Pro Segment:
let asset = AVAsset(url: segmentFileURL)
let reader = AVAssetReader(asset: asset)
// ... Tracks laden, Outputs konfigurieren ...
reader.startReading()
while reader.status == .reading {
    for (output, input) in pairs where input.isReadyForMoreMediaData {
        if let sample = output.copyNextSampleBuffer() {
            let adjusted = applyOffset(sample, currentOffset)
            input.append(adjusted)
        }
    }
}
// Reader wird nach dem Segment verworfen
```

### Decision 4: Writer-Konfiguration vom ersten erfolgreichen Segment

**Ansatz:** Track-Konfiguration (Video-Codec, Audio-Codec, Auflösung) wird vom ersten vollständig heruntergeladenen Segment abgeleitet. Folgende Segmente müssen die gleiche Konfiguration haben.

**Risiko:** Adaptives HLS könnte unterschiedliche Auflösungen/Codecs pro Segment liefern. In der Praxis liefert Bluesky pro Video eine feste Qualitätsstufe. Sollte ein Segment abweichen, schlägt `input.append()` fehl → Fehlerbehandlung bricht ab und löscht die partielle MP4.

## Risks / Trade-offs

- **[Risk] PTS-Offset-Arithmetik falsch** → Video hat Ton/Bild-Sync-Probleme → Unit-Test mit 2-Segment-Video, PTS-Werte vor/nach Offset verifizieren
- **[Risk] Erstes Segment hat nur Video, kein Audio** → Writer hat keine Audio-Input → Wenn späteres Segment Audio hat, schlägt append fehl → Im ersten Segment Video+Audio-Tracks erkennen, fehlende Tracks mit leeren Inputs vorbereiten (placeholder) ODER nur Tracks aus erstem Segment verwenden und spätere ignorieren
- **[Risk] `AVAssetWriter` blockiert den aktuellen Thread** → `append()` kann blockieren wenn `isReadyForMoreMediaData == false` → existierende TaskGroup-Struktur verwenden, Serialisierung über `actor` ist bereits gegeben
- **[Trade-off] Segment-Temp-Dateien im Speicher** → Segmente werden aktuell als Dateien in tempDirectory gespeichert und dann via AVAsset gelesen → Alternative wäre In-Memory-Verarbeitung via `AVAsset(Data)`, aber das ist nicht direkt unterstützt

## Migration Plan

1. `downloadVideo()` in `MediaDownloadService.swift` ersetzen
2. `VideoRemuxer`-Enum entfernen
3. Bestehende `downloadSegment`-Hilfsfunktion beibehalten (unverändert)
4. Keine Migration nötig — externe API (`downloadMedia`) unverändert

**Rollback:** Alte `downloadVideo`-Implementierung wiederherstellen, `VideoRemuxer` wieder hinzufügen.

## Open Questions

- *Keine*
