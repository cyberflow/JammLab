import XCTest
@testable import JammLab

final class StemWorkflowLogicTests: XCTestCase {
    func testStemMixMuteSoloPrecedenceAndVolumeClamping() {
        var mix = StemMixState(items: [
            StemMixItem(type: .vocals, volume: 1, isAvailable: true),
            StemMixItem(type: .drums, volume: 0.75, isAvailable: true),
            StemMixItem(type: .bass, volume: 0.5, isAvailable: true),
            StemMixItem(type: .other, volume: 1, isAvailable: false)
        ])

        XCTAssertEqual(mix.effectiveVolume(for: .vocals), 1, accuracy: 0.0001)
        XCTAssertEqual(mix.effectiveVolume(for: .bass), 0.5, accuracy: 0.0001)
        XCTAssertTrue(mix.isAudible(.vocals))
        XCTAssertFalse(mix.isAudible(.other))

        mix.update(.vocals) { $0.isMuted = true }
        XCTAssertEqual(mix.effectiveVolume(for: .vocals), 0, accuracy: 0.0001)
        XCTAssertFalse(mix.isAudible(.vocals))
        XCTAssertTrue(mix.isAudible(.drums))

        mix.update(.bass) { $0.isSoloed = true }
        XCTAssertEqual(mix.effectiveVolume(for: .drums), 0, accuracy: 0.0001)
        XCTAssertEqual(mix.effectiveVolume(for: .bass), 0.5, accuracy: 0.0001)
        XCTAssertEqual(mix.effectiveVolume(for: .vocals), 0, accuracy: 0.0001)
        XCTAssertFalse(mix.isAudible(.drums))
        XCTAssertTrue(mix.isAudible(.bass))
        XCTAssertFalse(mix.isAudible(.vocals))

        mix.update(.bass) {
            $0.volume = 2
            $0.isMuted = true
        }
        XCTAssertEqual(mix.item(for: .bass).volume, 1, accuracy: 0.0001)
        XCTAssertTrue(mix.item(for: .bass).isMuted)
        XCTAssertTrue(mix.item(for: .bass).isSoloed)
        XCTAssertEqual(mix.effectiveVolume(for: .bass), 1, accuracy: 0.0001)
        XCTAssertTrue(mix.isAudible(.bass))

        mix.update(.bass) { $0.isSoloed = false }
        XCTAssertTrue(mix.item(for: .bass).isMuted)
        XCTAssertFalse(mix.item(for: .bass).isSoloed)
        XCTAssertEqual(mix.effectiveVolume(for: .bass), 0, accuracy: 0.0001)
        XCTAssertFalse(mix.isAudible(.bass))
    }

    func testBasicPitchTranscriptionPolicyExcludesDrumsOnly() {
        XCTAssertFalse(StemType.drums.supportsBasicPitchTranscription)
        XCTAssertTrue(StemType.bass.supportsBasicPitchTranscription)
        XCTAssertTrue(StemType.piano.supportsBasicPitchTranscription)
    }

    func testStemMixResetUsesStemVolumeGroupDefault() {
        var mix = StemMixState(items: [
            StemMixItem(type: .vocals, volume: 0.2, isMuted: true, isAvailable: true),
            StemMixItem(type: .drums, volume: 0.4, isSoloed: true, isAvailable: true)
        ])

        mix.resetMix(availableStems: [
            StemFile(type: .vocals, url: URL(fileURLWithPath: "/tmp/vocals.wav"), displayName: "Vocals")
        ])

        XCTAssertEqual(mix.item(for: .vocals).volume, AppSliderDefaults.stemTrackVolume, accuracy: 0.0001)
        XCTAssertEqual(mix.item(for: .drums).volume, AppSliderDefaults.stemTrackVolume, accuracy: 0.0001)
        XCTAssertTrue(mix.item(for: .vocals).isAvailable)
        XCTAssertFalse(mix.item(for: .drums).isAvailable)
        XCTAssertFalse(mix.item(for: .vocals).isMuted)
        XCTAssertFalse(mix.item(for: .drums).isSoloed)
    }

    func testStemMixStateDecodeNormalizesMissingNewStemTypes() throws {
        let json = """
        {
          "items": [
            {
              "type": "vocals",
              "volume": 0.25,
              "isMuted": true,
              "isSoloed": false,
              "isAvailable": true
            },
            {
              "type": "drums",
              "volume": 0.5,
              "isMuted": false,
              "isSoloed": true,
              "isAvailable": true
            }
          ]
        }
        """

        var mix = try JSONDecoder().decode(StemMixState.self, from: Data(json.utf8))

        XCTAssertEqual(mix.items.map(\.type), StemType.allCases)
        XCTAssertEqual(mix.item(for: .vocals).volume, 0.25, accuracy: 0.0001)
        XCTAssertTrue(mix.item(for: .vocals).isMuted)
        XCTAssertTrue(mix.item(for: .drums).isSoloed)
        XCTAssertEqual(mix.item(for: .guitar).volume, AppSliderDefaults.stemTrackVolume, accuracy: 0.0001)
        XCTAssertFalse(mix.item(for: .piano).isAvailable)

        let sixStemFiles = StemSeparationMethod.sixStem.stemTypes.map { type in
            StemFile(type: type, url: URL(fileURLWithPath: "/tmp/\(type.canonicalStemFilename)"), displayName: type.title)
        }
        mix.setAvailability(from: sixStemFiles)

        XCTAssertTrue(mix.item(for: .guitar).isAvailable)
        XCTAssertTrue(mix.item(for: .piano).isAvailable)
        XCTAssertFalse(mix.item(for: .instrumental).isAvailable)
    }

    func testStemFingerprintCanMatchSameFileThroughDifferentPath() {
        let original = StemSourceFingerprint(path: "/Users/me/Music/song.mp3", fileSize: 42, modificationTime: 1234)
        let resolvedBookmark = StemSourceFingerprint(path: "/private/var/folders/song.mp3", fileSize: 42, modificationTime: 1234)
        let editedFile = StemSourceFingerprint(path: "/Users/me/Music/song.mp3", fileSize: 43, modificationTime: 1234)

        XCTAssertTrue(original.hasSameFileIdentity(as: resolvedBookmark))
        XCTAssertFalse(original.hasSameFileIdentity(as: editedFile))
    }

    func testStemSeparationMethodsExposeModelsAndStemOrder() {
        XCTAssertEqual(StemSeparationMethod.allCases.map(\.id), ["vocalInstrumental", "fourStem", "sixStem"])
        XCTAssertEqual(StemSeparationMethod.vocalInstrumental.modelName, "UVR-MDX-NET-Inst_HQ_5.onnx")
        XCTAssertEqual(StemSeparationMethod.vocalInstrumental.stemTypes, [.vocals, .instrumental])
        XCTAssertEqual(StemSeparationMethod.vocalInstrumental.stemCountSummary, "2 stems: vocals and instrumental.")
        XCTAssertEqual(StemSeparationMethod.fourStem.modelName, "htdemucs.yaml")
        XCTAssertEqual(StemSeparationMethod.fourStem.stemTypes, [.vocals, .bass, .drums, .other])
        XCTAssertEqual(StemSeparationMethod.fourStem.stemCountSummary, "4 stems: vocals, bass, drums, and other.")
        XCTAssertEqual(StemSeparationMethod.sixStem.modelName, "htdemucs_6s.yaml")
        XCTAssertEqual(StemSeparationMethod.sixStem.stemTypes, [.vocals, .bass, .drums, .other, .guitar, .piano])
        XCTAssertEqual(StemSeparationMethod.sixStem.stemCountSummary, "6 stems: vocals, bass, drums, other, guitar, and piano.")
    }

    func testTimelineStemTrackHeightExpandsForSixStemRows() {
        let defaultHeight = AppTheme.Timeline.stemTracksHeight
        let sixStemHeight = AppTheme.Timeline.stemTracksHeight(rowCount: StemSeparationMethod.sixStem.stemTypes.count)

        XCTAssertEqual(AppTheme.Timeline.stemTracksHeight(rowCount: StemSeparationMethod.vocalInstrumental.stemTypes.count), defaultHeight)
        XCTAssertEqual(AppTheme.Timeline.stemTracksHeight(rowCount: StemSeparationMethod.fourStem.stemTypes.count), defaultHeight)
        XCTAssertGreaterThan(sixStemHeight, defaultHeight)
        XCTAssertGreaterThan(
            AppTheme.Timeline.tracksMinimumHeight(stemRowCount: StemSeparationMethod.sixStem.stemTypes.count),
            AppTheme.Timeline.tracksMinimumHeight
        )
    }

    func testTimelineHeightHelpersCollapseNotationTrackWithoutChangingStemExpansion() {
        let collapsedHeight = AppTheme.Timeline.tracksMinimumHeight(
            stemRowCount: StemSeparationMethod.defaultValue.stemTypes.count,
            isNotationTrackCollapsed: true
        )
        let expandedHeight = AppTheme.Timeline.tracksMinimumHeight(
            stemRowCount: StemSeparationMethod.defaultValue.stemTypes.count,
            isNotationTrackCollapsed: false
        )
        let sixStemCollapsedHeight = AppTheme.Timeline.tracksMinimumHeight(
            stemRowCount: StemSeparationMethod.sixStem.stemTypes.count,
            isNotationTrackCollapsed: true
        )

        XCTAssertLessThan(collapsedHeight, expandedHeight)
        XCTAssertEqual(
            expandedHeight - collapsedHeight,
            AppTheme.Timeline.notationTrackHeight - AppTheme.Timeline.notationTrackCollapsedHeight,
            accuracy: 0.0001
        )
        XCTAssertGreaterThan(sixStemCollapsedHeight, collapsedHeight)
    }

    func testTimelineHeightHelpersIncludeExpandedStemNotationRowsOnce() {
        let rowCount = StemSeparationMethod.fourStem.stemTypes.count
        let baseStemHeight = AppTheme.Timeline.stemTracksHeight(rowCount: rowCount)
        let oneExpandedHeight = AppTheme.Timeline.stemTracksHeight(
            rowCount: rowCount,
            expandedStemNotationCount: 1
        )
        let allExpandedHeight = AppTheme.Timeline.stemTracksHeight(
            rowCount: rowCount,
            expandedStemNotationCount: rowCount
        )
        let clampedExpandedHeight = AppTheme.Timeline.stemTracksHeight(
            rowCount: rowCount,
            expandedStemNotationCount: rowCount + 3
        )
        let notationRowExpansion = AppTheme.Timeline.trackSpacing
            + AppTheme.Timeline.notationTrackHeight

        XCTAssertEqual(
            AppTheme.Timeline.stemRowHeight(isNotationExpanded: false),
            AppTheme.Timeline.stemTrackHeight
        )
        XCTAssertEqual(
            AppTheme.Timeline.stemRowHeight(isNotationExpanded: true),
            AppTheme.Timeline.stemTrackHeight + notationRowExpansion
        )
        XCTAssertEqual(oneExpandedHeight - baseStemHeight, notationRowExpansion)
        XCTAssertEqual(
            allExpandedHeight - baseStemHeight,
            CGFloat(rowCount) * notationRowExpansion
        )
        XCTAssertEqual(clampedExpandedHeight, allExpandedHeight)
        XCTAssertEqual(
            AppTheme.Timeline.tracksMinimumHeight(
                stemRowCount: rowCount,
                isNotationTrackCollapsed: true,
                expandedStemNotationCount: 1
            ) - AppTheme.Timeline.tracksMinimumHeight(
                stemRowCount: rowCount,
                isNotationTrackCollapsed: true
            ),
            notationRowExpansion
        )
        XCTAssertEqual(
            AppTheme.Timeline.timelineBlockMinimumHeight(
                stemRowCount: rowCount,
                isNotationTrackCollapsed: true,
                expandedStemNotationCount: 1
            ),
            AppTheme.Timeline.tracksMinimumHeight(
                stemRowCount: rowCount,
                isNotationTrackCollapsed: true,
                expandedStemNotationCount: 1
            )
                + AppTheme.Timeline.viewportFooterGap
                + AppTheme.Timeline.viewportControlBarHeight
        )
        XCTAssertEqual(
            AppTheme.Timeline.minimumContentHeight(
                stemRowCount: rowCount,
                isNotationTrackCollapsed: true,
                expandedStemNotationCount: 1
            ),
            AppTheme.Timeline.timelineBlockMinimumHeight(
                stemRowCount: rowCount,
                isNotationTrackCollapsed: true,
                expandedStemNotationCount: 1
            )
        )
    }

}
