import XCTest
@testable import JammLab

final class ViewModelNotationSelectionTests: XCTestCase {
    @MainActor
    func testSelectingNotationMeasureDoesNotMarkProjectModified() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let measure = try notationMeasure(1, in: viewModel)

        viewModel.selectNotationMeasure(measure)

        XCTAssertEqual(viewModel.selectedNotationMeasures.map(\.number), [1])
        XCTAssertTrue(viewModel.canCopySelectedNotationMeasure)
        XCTAssertFalse(viewModel.isProjectModified)
    }

    @MainActor
    func testSelectingNotationItemDoesNotMarkProjectModifiedAndClearsMeasureSelection() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let measure = try notationMeasure(1, in: viewModel)
        let item = try XCTUnwrap(measure.notationItems.first)

        viewModel.selectNotationMeasure(measure)
        viewModel.selectNotationItem(NotationItemSelection(measure: measure, item: item))

        XCTAssertTrue(viewModel.selectedNotationMeasures.isEmpty)
        XCTAssertEqual(viewModel.selectedNotationItem?.measureNumber, 1)
        XCTAssertEqual(viewModel.selectedNotationItem?.offsetInQuarterNotes, 0)
        XCTAssertFalse(viewModel.isProjectModified)
    }

    @MainActor
    func testRequestEditSelectedNotationItemUsesExactItemOffsetAndExistingHarmony() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let measure = try notationMeasure(1, in: viewModel)
        let item = NotationMeasureItem(
            measureNumber: measure.number,
            measureStartTime: measure.startTime,
            offsetInQuarterNotes: 1,
            durationInQuarterNotes: 1,
            displayDuration: NotationDuration(denominator: 4)
        )
        let harmony = HarmonySymbol(
            time: NotationMeasureTiming.time(forQuarterOffset: 1, in: measure),
            measureNumber: measure.number,
            offsetInQuarterNotes: 1,
            rawText: "Fmaj7"
        )
        viewModel.harmonySymbols = [harmony]
        viewModel.notationItems = [item]
        viewModel.markProjectClean()

        let updatedMeasure = try notationMeasure(1, in: viewModel)
        let updatedItem = try XCTUnwrap(updatedMeasure.notationItems.first { $0.offsetInQuarterNotes == 1 })
        viewModel.selectNotationItem(NotationItemSelection(measure: updatedMeasure, item: updatedItem))

        XCTAssertTrue(viewModel.requestEditSelectedNotationItem())
        let request = try XCTUnwrap(viewModel.pendingHarmonyEditorRequest)
        XCTAssertEqual(request.time, harmony.time, accuracy: 0.0001)
        XCTAssertEqual(viewModel.selectedHarmonySymbolID, harmony.id)
        XCTAssertFalse(viewModel.isProjectModified)
    }

    @MainActor
    func testNotationItemSelectionClearsForTempoMapAndUndoChanges() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let firstMeasure = try notationMeasure(1, in: viewModel)
        let firstItem = try XCTUnwrap(firstMeasure.notationItems.first)

        viewModel.selectNotationItem(NotationItemSelection(measure: firstMeasure, item: firstItem))
        viewModel.setTimeSignature(beatsPerBar: 3, beatUnit: 4)

        XCTAssertNil(viewModel.selectedNotationItem)

        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        let updatedMeasure = try notationMeasure(1, in: viewModel)
        let updatedItem = try XCTUnwrap(updatedMeasure.notationItems.first)
        viewModel.markProjectClean()
        viewModel.selectNotationItem(NotationItemSelection(measure: updatedMeasure, item: updatedItem))
        viewModel.addNote(at: 0.5)

        XCTAssertNotNil(viewModel.selectedNotationItem)

        viewModel.undoLastEdit()

        XCTAssertNil(viewModel.selectedNotationItem)
    }

    @MainActor
    func testChangingSelectedWholeRestToQuarterCreatesTwoQuartersAndHalfInFourFour() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let measure = try notationMeasure(1, in: viewModel)
        let item = try XCTUnwrap(measure.notationItems.first)
        viewModel.markProjectClean()

        viewModel.selectNotationItem(NotationItemSelection(measure: measure, item: item))
        viewModel.setNotationDurationDenominator(4)

        let updatedMeasure = try notationMeasure(1, in: viewModel)
        XCTAssertEqual(updatedMeasure.notationItems.map(\.displayDuration.denominator), [4, 4, 2])
        XCTAssertEqual(updatedMeasure.notationItems.map(\.offsetInQuarterNotes), [0, 1, 2])
        XCTAssertEqual(updatedMeasure.notationItems.map(\.durationInQuarterNotes), [1, 1, 2])
        XCTAssertEqual(viewModel.selectedNotationItem?.offsetInQuarterNotes, 0)
        XCTAssertTrue(viewModel.isProjectModified)
    }

    @MainActor
    func testChangingSelectedWholeRestToHalfInThreeFourCreatesHalfAndQuarter() throws {
        let viewModel = try loadedNotationViewModel(duration: 6)
        viewModel.setTimeSignature(beatsPerBar: 3, beatUnit: 4)
        let measure = try notationMeasure(1, in: viewModel)
        let item = try XCTUnwrap(measure.notationItems.first)
        viewModel.markProjectClean()

        viewModel.selectNotationItem(NotationItemSelection(measure: measure, item: item))
        viewModel.setNotationDurationDenominator(2)

        let updatedMeasure = try notationMeasure(1, in: viewModel)
        XCTAssertEqual(updatedMeasure.notationItems.map(\.displayDuration.denominator), [2, 4])
        XCTAssertEqual(updatedMeasure.notationItems.map(\.offsetInQuarterNotes), [0, 2])
        XCTAssertEqual(updatedMeasure.notationItems.map(\.durationInQuarterNotes), [2, 1])
        XCTAssertTrue(viewModel.isProjectModified)
    }

    @MainActor
    func testShiftSelectingNotationMeasuresBuildsContiguousRange() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let firstMeasure = try notationMeasure(1, in: viewModel)
        let thirdMeasure = try notationMeasure(3, in: viewModel)

        viewModel.selectNotationMeasure(firstMeasure)
        viewModel.selectNotationMeasure(thirdMeasure, extendingSelection: true)

        XCTAssertEqual(viewModel.selectedNotationMeasures.map(\.number), [1, 2, 3])

        viewModel.selectNotationMeasure(firstMeasure, extendingSelection: true)

        XCTAssertEqual(viewModel.selectedNotationMeasures.map(\.number), [1])
    }

    @MainActor
    func testShiftSelectingNotationMeasureWithoutAnchorFallsBackToSingleSelection() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let secondMeasure = try notationMeasure(2, in: viewModel)

        viewModel.selectNotationMeasure(secondMeasure, extendingSelection: true)

        XCTAssertEqual(viewModel.selectedNotationMeasures.map(\.number), [2])
    }

    @MainActor
    func testCopyNotationMeasureCopiesOnlyHarmonies() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let measure = try notationMeasure(1, in: viewModel)
        viewModel.notes = [
            TimecodedNote(kind: .region, time: measure.startTime, duration: 1, title: "Intro")
        ]
        viewModel.harmonySymbols = [
            HarmonySymbol(time: 0.5, measureNumber: 99, offsetInQuarterNotes: 99, rawText: "F"),
            HarmonySymbol(time: measure.endTime, measureNumber: 1, offsetInQuarterNotes: 4, rawText: "G")
        ]

        viewModel.selectNotationMeasure(measure)

        XCTAssertTrue(viewModel.copySelectedNotationMeasure())
        XCTAssertEqual(viewModel.notationMeasureClipboard?.measures.map(\.items), [[
            NotationMeasureClipboardItem(offsetInQuarterNotes: 1, rawText: "F")
        ]])
    }

    @MainActor
    func testCopyNotationMeasureRangePreservesOrderAndEmptyMeasures() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let firstMeasure = try notationMeasure(1, in: viewModel)
        let thirdMeasure = try notationMeasure(3, in: viewModel)
        viewModel.harmonySymbols = [
            HarmonySymbol(time: 0, measureNumber: 1, offsetInQuarterNotes: 0, rawText: "C"),
            HarmonySymbol(time: 4, measureNumber: 3, offsetInQuarterNotes: 0, rawText: "Am")
        ]

        viewModel.selectNotationMeasure(firstMeasure)
        viewModel.selectNotationMeasure(thirdMeasure, extendingSelection: true)

        XCTAssertTrue(viewModel.copySelectedNotationMeasure())
        XCTAssertEqual(viewModel.notationMeasureClipboard?.measures.map(\.items), [
            [NotationMeasureClipboardItem(offsetInQuarterNotes: 0, rawText: "C")],
            [],
            [NotationMeasureClipboardItem(offsetInQuarterNotes: 0, rawText: "Am")]
        ])
    }

    @MainActor
    func testPasteNotationMeasureReplacesTargetAndSupportsUndoRedo() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        let sourceMeasure = try notationMeasure(1, in: viewModel)
        let targetMeasure = try notationMeasure(2, in: viewModel)
        let sourceA = HarmonySymbol(time: 0, measureNumber: 1, offsetInQuarterNotes: 0, rawText: "C")
        let sourceB = HarmonySymbol(time: 1, measureNumber: 1, offsetInQuarterNotes: 2, rawText: "F")
        let targetExisting = HarmonySymbol(time: 2.5, measureNumber: 2, offsetInQuarterNotes: 1, rawText: "G7")
        viewModel.harmonySymbols = [sourceA, sourceB, targetExisting]
        viewModel.markProjectClean()

        viewModel.selectNotationMeasure(sourceMeasure)
        XCTAssertTrue(viewModel.copySelectedNotationMeasure())
        viewModel.selectNotationMeasure(targetMeasure)
        let beforePaste = viewModel.harmonySymbols

        XCTAssertTrue(viewModel.pasteNotationMeasureClipboard())

        let targetSymbols = viewModel.harmonySymbols.filter {
            NotationMeasureTiming.containsEventTime($0.time, in: targetMeasure)
        }
        XCTAssertEqual(targetSymbols.map(\.rawText), ["C", "F"])
        XCTAssertEqual(targetSymbols.map(\.id).contains(sourceA.id), false)
        XCTAssertEqual(targetSymbols.map(\.id).contains(sourceB.id), false)
        XCTAssertEqual(targetSymbols[0].time, 2, accuracy: 0.0001)
        XCTAssertEqual(targetSymbols[1].time, 3, accuracy: 0.0001)
        XCTAssertNil(viewModel.selectedHarmonySymbolID)
        XCTAssertEqual(viewModel.selectedNotationMeasures.map(\.number), [targetMeasure.number])
        XCTAssertTrue(viewModel.isProjectModified)

        viewModel.undoLastEdit()

        XCTAssertEqual(viewModel.harmonySymbols, beforePaste)
        XCTAssertFalse(viewModel.isProjectModified)

        viewModel.redoLastEdit()

        let redoneTargetSymbols = viewModel.harmonySymbols.filter {
            NotationMeasureTiming.containsEventTime($0.time, in: targetMeasure)
        }
        XCTAssertEqual(redoneTargetSymbols.map(\.rawText), ["C", "F"])
        XCTAssertTrue(viewModel.isProjectModified)
    }

    @MainActor
    func testPasteNotationMeasureRangeStartsAtFirstSelectedTarget() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let sourceMeasure = try notationMeasure(1, in: viewModel)
        let secondMeasure = try notationMeasure(2, in: viewModel)
        let targetMeasure = try notationMeasure(3, in: viewModel)
        let fourthMeasure = try notationMeasure(4, in: viewModel)
        viewModel.harmonySymbols = [
            HarmonySymbol(time: 0, measureNumber: 1, offsetInQuarterNotes: 0, rawText: "C"),
            HarmonySymbol(time: 2, measureNumber: 2, offsetInQuarterNotes: 0, rawText: "F"),
            HarmonySymbol(time: 4, measureNumber: 3, offsetInQuarterNotes: 0, rawText: "G"),
            HarmonySymbol(time: 6, measureNumber: 4, offsetInQuarterNotes: 0, rawText: "Am")
        ]

        viewModel.selectNotationMeasure(sourceMeasure)
        viewModel.selectNotationMeasure(secondMeasure, extendingSelection: true)
        XCTAssertTrue(viewModel.copySelectedNotationMeasure())
        viewModel.selectNotationMeasure(targetMeasure)

        XCTAssertTrue(viewModel.pasteNotationMeasureClipboard())

        let thirdMeasureSymbols = viewModel.harmonySymbols.filter {
            NotationMeasureTiming.containsEventTime($0.time, in: targetMeasure)
        }
        let fourthMeasureSymbols = viewModel.harmonySymbols.filter {
            NotationMeasureTiming.containsEventTime($0.time, in: fourthMeasure)
        }
        XCTAssertEqual(thirdMeasureSymbols.map(\.rawText), ["C"])
        XCTAssertEqual(fourthMeasureSymbols.map(\.rawText), ["F"])
        XCTAssertEqual(viewModel.selectedNotationMeasures.map(\.number), [3, 4])
    }

    @MainActor
    func testPastingEmptyNotationMeasureClearsTarget() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let emptyMeasure = try notationMeasure(3, in: viewModel)
        let targetMeasure = try notationMeasure(2, in: viewModel)
        viewModel.harmonySymbols = [
            HarmonySymbol(time: 2.5, measureNumber: 2, offsetInQuarterNotes: 1, rawText: "G7")
        ]

        viewModel.selectNotationMeasure(emptyMeasure)
        XCTAssertTrue(viewModel.copySelectedNotationMeasure())
        viewModel.selectNotationMeasure(targetMeasure)

        XCTAssertTrue(viewModel.pasteNotationMeasureClipboard())

        XCTAssertFalse(viewModel.harmonySymbols.contains {
            NotationMeasureTiming.containsEventTime($0.time, in: targetMeasure)
        })
    }

    @MainActor
    func testPastingNotationMeasureRangePreservesEmptyMeasuresByClearingTargets() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let sourceMeasure = try notationMeasure(1, in: viewModel)
        let secondMeasure = try notationMeasure(2, in: viewModel)
        let targetMeasure = try notationMeasure(3, in: viewModel)
        let fourthMeasure = try notationMeasure(4, in: viewModel)
        viewModel.harmonySymbols = [
            HarmonySymbol(time: 0, measureNumber: 1, offsetInQuarterNotes: 0, rawText: "C"),
            HarmonySymbol(time: 4, measureNumber: 3, offsetInQuarterNotes: 0, rawText: "G"),
            HarmonySymbol(time: 6, measureNumber: 4, offsetInQuarterNotes: 0, rawText: "Am")
        ]

        viewModel.selectNotationMeasure(sourceMeasure)
        viewModel.selectNotationMeasure(secondMeasure, extendingSelection: true)
        XCTAssertTrue(viewModel.copySelectedNotationMeasure())
        viewModel.selectNotationMeasure(targetMeasure)

        XCTAssertTrue(viewModel.pasteNotationMeasureClipboard())

        XCTAssertEqual(viewModel.harmonySymbols.filter {
            NotationMeasureTiming.containsEventTime($0.time, in: targetMeasure)
        }.map(\.rawText), ["C"])
        XCTAssertFalse(viewModel.harmonySymbols.contains {
            NotationMeasureTiming.containsEventTime($0.time, in: fourthMeasure)
        })
    }

    @MainActor
    func testPastingNotationMeasureRangeIgnoresOverflowBeyondAvailableTargets() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let sourceMeasure = try notationMeasure(1, in: viewModel)
        let thirdMeasure = try notationMeasure(3, in: viewModel)
        let fourthMeasure = try notationMeasure(4, in: viewModel)
        viewModel.harmonySymbols = [
            HarmonySymbol(time: 0, measureNumber: 1, offsetInQuarterNotes: 0, rawText: "C"),
            HarmonySymbol(time: 2, measureNumber: 2, offsetInQuarterNotes: 0, rawText: "F"),
            HarmonySymbol(time: 4, measureNumber: 3, offsetInQuarterNotes: 0, rawText: "G"),
            HarmonySymbol(time: 6, measureNumber: 4, offsetInQuarterNotes: 0, rawText: "Am")
        ]

        viewModel.selectNotationMeasure(sourceMeasure)
        viewModel.selectNotationMeasure(thirdMeasure, extendingSelection: true)
        XCTAssertTrue(viewModel.copySelectedNotationMeasure())
        viewModel.selectNotationMeasure(fourthMeasure)

        XCTAssertTrue(viewModel.pasteNotationMeasureClipboard())

        let fourthMeasureSymbols = viewModel.harmonySymbols.filter {
            NotationMeasureTiming.containsEventTime($0.time, in: fourthMeasure)
        }
        XCTAssertEqual(fourthMeasureSymbols.map(\.rawText), ["C"])
        XCTAssertEqual(viewModel.selectedNotationMeasures.map(\.number), [4])
    }

    @MainActor
    func testPasteNotationMeasureSkipsOffsetsOutsideTargetTimeSignature() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        viewModel.addTempoTimeSignatureMarker(at: 2, bpm: 120, beatsPerBar: 3)
        viewModel.markProjectClean()
        let sourceMeasure = try notationMeasure(1, in: viewModel)
        let targetMeasure = try notationMeasure(2, in: viewModel)
        viewModel.harmonySymbols = [
            HarmonySymbol(time: 0, measureNumber: 1, offsetInQuarterNotes: 0, rawText: "C"),
            HarmonySymbol(time: 1.5, measureNumber: 1, offsetInQuarterNotes: 3, rawText: "D")
        ]

        viewModel.selectNotationMeasure(sourceMeasure)
        XCTAssertTrue(viewModel.copySelectedNotationMeasure())
        viewModel.selectNotationMeasure(targetMeasure)

        XCTAssertTrue(viewModel.pasteNotationMeasureClipboard())

        let targetSymbols = viewModel.harmonySymbols.filter {
            NotationMeasureTiming.containsEventTime($0.time, in: targetMeasure)
        }
        XCTAssertEqual(targetSymbols.map(\.rawText), ["C"])
        XCTAssertEqual(try XCTUnwrap(targetSymbols.first).time, 2, accuracy: 0.0001)
    }

    @MainActor
    func testTempoMapChangesClearSelectedNotationMeasure() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let measure = try notationMeasure(1, in: viewModel)

        viewModel.selectNotationMeasure(measure)
        viewModel.setTimeSignature(beatsPerBar: 3, beatUnit: 4)

        XCTAssertTrue(viewModel.selectedNotationMeasures.isEmpty)
    }

    @MainActor
    func testCopyRejectsPartialStaleNotationMeasureSelection() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let firstMeasure = try notationMeasure(1, in: viewModel)
        let secondMeasure = try notationMeasure(2, in: viewModel)

        viewModel.selectedNotationMeasures = [
            NotationMeasureSelection(measure: firstMeasure),
            NotationMeasureSelection(
                measure: ScoreMeasure(
                    number: secondMeasure.number,
                    startTime: secondMeasure.startTime,
                    endTime: secondMeasure.endTime + 0.25,
                    attributes: secondMeasure.attributes
                )
            )
        ]

        XCTAssertFalse(viewModel.copySelectedNotationMeasure())
        XCTAssertTrue(viewModel.selectedNotationMeasures.isEmpty)
    }

    @MainActor
    func testClearingNotationMeasureSelectionDoesNotClearClipboardOrMarkDirty() throws {
        let viewModel = try loadedNotationViewModel(duration: 8)
        let measure = try notationMeasure(1, in: viewModel)
        viewModel.harmonySymbols = [
            HarmonySymbol(time: 0, measureNumber: 1, offsetInQuarterNotes: 0, rawText: "C")
        ]
        viewModel.selectNotationMeasure(measure)
        XCTAssertTrue(viewModel.copySelectedNotationMeasure())
        viewModel.markProjectClean()

        viewModel.clearNotationMeasureSelection()

        XCTAssertTrue(viewModel.selectedNotationMeasures.isEmpty)
        XCTAssertNotNil(viewModel.notationMeasureClipboard)
        XCTAssertFalse(viewModel.isProjectModified)
    }

    @MainActor
    func testExportNotationWritesMusicXMLWithoutChangingDirtyOrUndoState() async throws {
        let emptyViewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: MockPlaybackEngine()
        )
        XCTAssertFalse(emptyViewModel.canExportNotation)

        let viewModel = try loadedNotationViewModel(duration: 8)
        let undoManager = UndoManager()
        viewModel.undoManager = undoManager
        viewModel.tempoBPM = 132.5
        viewModel.beatGridSettings.bpm = 132.5
        viewModel.harmonySymbols = [
            HarmonySymbol(time: 0, measureNumber: 1, offsetInQuarterNotes: 0, rawText: "Cmaj7")
        ]
        viewModel.markProjectClean()

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("notation-export-\(UUID().uuidString)")
            .appendingPathExtension("musicxml")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        XCTAssertTrue(viewModel.canExportNotation)
        let didExportCleanProject = await viewModel.exportNotation(format: .musicXML, to: outputURL)

        XCTAssertTrue(didExportCleanProject)
        XCTAssertFalse(viewModel.isProjectModified)
        XCTAssertFalse(viewModel.canUndo)
        XCTAssertNil(viewModel.errorMessage)
        let xml = try String(contentsOf: outputURL, encoding: .utf8)
        XCTAssertTrue(xml.contains("<score-partwise version=\"4.0\">"))
        XCTAssertTrue(xml.contains("<kind text=\"Cmaj7\">major-seventh</kind>"))
        XCTAssertTrue(xml.contains("<per-minute>132.5</per-minute>"))

        viewModel.setLooping(true)
        XCTAssertTrue(viewModel.isProjectModified)
        XCTAssertTrue(viewModel.canUndo)

        let didExportDirtyProject = await viewModel.exportNotation(format: .musicXML, to: outputURL)

        XCTAssertTrue(didExportDirtyProject)
        XCTAssertTrue(viewModel.isProjectModified)
        XCTAssertTrue(viewModel.canUndo)
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    private func loadedNotationViewModel(duration: TimeInterval) throws -> AudioPlayerViewModel {
        let audioURL = try temporaryAudioFile(duration: duration)
        let viewModel = AudioPlayerViewModel(
            analyzer: MockAnalyzer(),
            peakformProvider: MockPeakformProvider(),
            playbackEngine: MockPlaybackEngine()
        )
        let media = ImportedAudioFile(url: audioURL, displayName: "notation.wav", duration: duration)
        try viewModel.loadImportedAudio(media)
        viewModel.beatGridSettings = BeatGridSettings(bpm: 120, timeSignature: .fourFour)
        viewModel.tempoBPM = 120
        viewModel.applyTempoMapToPlaybackEngine()
        viewModel.markProjectClean()
        return viewModel
    }

    @MainActor
    private func notationMeasure(_ number: Int, in viewModel: AudioPlayerViewModel) throws -> ScoreMeasure {
        let score = NotationViewportFactory().scoreState(
            tempoMap: viewModel.tempoMap,
            duration: viewModel.duration,
            currentTime: viewModel.currentTime,
            playbackMarkerTime: viewModel.playbackMarkerTime,
            isPlaying: viewModel.playbackState == .playing,
            keyName: viewModel.effectiveKeyName,
            notationItems: viewModel.notationItems,
            harmonySymbols: viewModel.harmonySymbols,
            notes: viewModel.notes
        )
        return try XCTUnwrap(score.measures.first { $0.number == number })
    }
}
