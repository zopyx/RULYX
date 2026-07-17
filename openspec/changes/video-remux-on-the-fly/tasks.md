## 1. Core — On-the-fly MP4 writer

- [ ] 1.1 `downloadVideo()` umschreiben: `AVAssetWriter` für `.mp4` vor Segment-Download-Schleife initialisieren
- [ ] 1.2 Erstes Segment nach Download analysieren: `AVAsset(url:)` → Video/Audio-Tracks erkennen → `AVAssetWriterInput` + `AVAssetReaderTrackOutput` pro Track anlegen (Passthrough: `outputSettings: nil`)
- [ ] 1.3 Samples des ersten Segments in den Writer schreiben, Segment-Dauer als initialen Offset merken
- [ ] 1.4 Für jedes weitere Segment: `AVAssetReader` öffnen, PTS/DTS pro Sample mit kumulativem Offset via `CMSampleBufferCreateCopyWithNewTiming` korrigieren, `writer.append()`
- [ ] 1.5 Nach letztem Segment: `writer.finishWriting()` aufrufen, Erfolg prüfen

## 2. Fehlerbehandlung

- [ ] 2.1 Wenn Writer-Konfiguration fehlschlägt (z.B. kein Track): `writer.cancelWriting()`, `.mp4`-Datei löschen, Error werfen
- [ ] 2.2 Wenn `input.append()` für ein Segment fehlschlägt: `writer.cancelWriting()`, `.mp4` löschen, Error werfen
- [ ] 2.3 Wenn `writer.finishWriting()` nicht `.completed` liefert: `.mp4` löschen, Error werfen (kein .ts-Fallback)

## 3. Cleanup

- [ ] 3.1 `VideoRemuxer`-Enum (Zeilen 438-541) entfernen
- [ ] 3.2 `MediaDownloadFailure.remuxFailed`-Case entfernen
- [ ] 3.3 toten Code: `.ts`-Konkatenation (FileHandle-Logik, `transportStreamURL`) entfernen

## 4. Validierung

- [ ] 4.1 Build mit `make build`
- [ ] 4.2 Lint mit `swiftformat --lint` auf `MediaDownloadService.swift`
- [ ] 4.3 Manueller Test: Video-Download via Media Browser → .mp4 muss direkt im Download-Ordner erscheinen, keine .ts-Datei
- [ ] 4.4 Manueller Test: Mehrsegment-Video → PTS-Kontinuität prüfen (Video muss durchgehend abspielbar sein)
