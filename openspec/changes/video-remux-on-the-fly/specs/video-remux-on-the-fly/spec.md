## ADDED Requirements

### Requirement: Video downloads SHALL produce .mp4 files directly
The video download pipeline SHALL write HLS video segments directly into an MP4 container using AVAssetWriter, without creating an intermediate .ts (Transport Stream) file.

#### Scenario: Successful video download
- **WHEN** all HLS segments are downloaded successfully
- **THEN** a single .mp4 file SHALL exist in the target directory
- **AND** no .ts file SHALL be created at any point

#### Scenario: Partial segment failure
- **WHEN** one or more HLS segments fail to download
- **THEN** the partial .mp4 file SHALL be deleted (via `cancelWriting`)
- **AND** no .ts file SHALL exist
- **AND** the error SHALL be propagated to the caller

### Requirement: PTS/DTS timestamps SHALL be corrected across segment boundaries
Each HLS TS segment restarts timestamps at zero. The system SHALL compute a cumulative offset and apply it to all samples in subsequent segments so the output MP4 has continuous, monotonically increasing timestamps.

#### Scenario: Multi-segment video with timestamp correction
- **GIVEN** a video with 3 HLS segments
- **WHEN** the first segment's last PTS is 3.0 seconds
- **THEN** the second segment's samples SHALL have 3.0s added to their timestamps
- **AND** the third segment's offset SHALL be the cumulative duration of segments 1+2

### Requirement: On-the-fly remux SHALL use hardware-accelerated passthrough
The AVAssetReader and AVAssetWriter SHALL use `outputSettings: nil` (passthrough mode) to avoid re-encoding. This preserves quality and uses hardware acceleration where available.

#### Scenario: H.264 video passthrough
- **GIVEN** HLS segments encoded in H.264
- **WHEN** samples are read from AVAssetReaderTrackOutput
- **THEN** samples SHALL be written to AVAssetWriterInput without decoding or re-encoding

### Requirement: VideoRemuxer SHALL be removed
The standalone `VideoRemuxer` enum (which remuxes .ts to .mp4) SHALL be removed, as its functionality is subsumed by the on-the-fly writer.

#### Scenario: Codebase after removal
- **WHEN** the change is implemented
- **THEN** `VideoRemuxer` SHALL not exist in the codebase
- **AND** no callers SHALL reference it
