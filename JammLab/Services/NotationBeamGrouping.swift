import Foundation

struct NotationBeamGroupingEvent: Equatable {
    var sourceIndex: Int
    var positionInQuarterNotes: Double
    var durationInQuarterNotes: Double
    var beamLevelCount: Int
    var isRest: Bool
}

struct NotationBeamRhythmicGroup: Equatable {
    var eventIndices: [Int]
    var startPositionInQuarterNotes: Double
    var endPositionInQuarterNotes: Double
}

struct NotationBeamMeterRules: Equatable {
    var primaryGroupLengthInQuarterNotes: Double
    var secondaryBreakIntervalInQuarterNotes: Double?

    static func rules(for timeSignature: TimeSignature) -> NotationBeamMeterRules? {
        switch (timeSignature.beatsPerBar, timeSignature.beatUnit) {
        case (2, 4), (3, 4), (4, 4):
            return NotationBeamMeterRules(
                primaryGroupLengthInQuarterNotes: 1,
                secondaryBreakIntervalInQuarterNotes: nil
            )
        case (3, 8), (6, 8):
            return NotationBeamMeterRules(
                primaryGroupLengthInQuarterNotes: 1.5,
                secondaryBreakIntervalInQuarterNotes: 0.5
            )
        default:
            return nil
        }
    }
}

enum NotationBeamGrouper {
    static func groups(
        timeSignature: TimeSignature,
        events: [NotationBeamGroupingEvent]
    ) -> [NotationBeamRhythmicGroup] {
        guard let rules = NotationBeamMeterRules.rules(for: timeSignature) else {
            return []
        }

        let sortedEvents = events.sorted {
            if abs($0.positionInQuarterNotes - $1.positionInQuarterNotes)
                > NotationMeasureTiming.timelineTolerance {
                return $0.positionInQuarterNotes < $1.positionInQuarterNotes
            }
            return $0.sourceIndex < $1.sourceIndex
        }
        var output: [NotationBeamRhythmicGroup] = []
        var current: [NotationBeamGroupingEvent] = []
        var currentMetricGroup: Int?

        func metricGroupIndex(for position: Double) -> Int {
            Int(floor(
                (position + NotationMeasureTiming.timelineTolerance)
                    / rules.primaryGroupLengthInQuarterNotes
            ))
        }

        func appendCurrentGroup() {
            guard current.count >= 2,
                  let first = current.first,
                  let last = current.last
            else {
                current.removeAll(keepingCapacity: true)
                currentMetricGroup = nil
                return
            }

            output.append(NotationBeamRhythmicGroup(
                eventIndices: current.map(\.sourceIndex),
                startPositionInQuarterNotes: first.positionInQuarterNotes,
                endPositionInQuarterNotes: last.positionInQuarterNotes
                    + last.durationInQuarterNotes
            ))
            current.removeAll(keepingCapacity: true)
            currentMetricGroup = nil
        }

        for event in sortedEvents {
            let eventMetricGroup = metricGroupIndex(
                for: event.positionInQuarterNotes
            )
            let metricGroupEnd = Double(eventMetricGroup + 1)
                * rules.primaryGroupLengthInQuarterNotes
            let staysInsideMetricGroup = event.positionInQuarterNotes
                + event.durationInQuarterNotes
                <= metricGroupEnd + NotationMeasureTiming.timelineTolerance
            let isBeamable = !event.isRest
                && event.beamLevelCount > 0
                && event.durationInQuarterNotes
                    <= 0.5 + NotationMeasureTiming.timelineTolerance
                && staysInsideMetricGroup
            guard isBeamable else {
                appendCurrentGroup()
                continue
            }

            if let currentMetricGroup, currentMetricGroup != eventMetricGroup {
                appendCurrentGroup()
            } else if let previous = current.last {
                let expectedPosition = previous.positionInQuarterNotes
                    + previous.durationInQuarterNotes
                if abs(event.positionInQuarterNotes - expectedPosition)
                    > NotationMeasureTiming.timelineTolerance {
                    appendCurrentGroup()
                }
            }

            if current.isEmpty {
                currentMetricGroup = eventMetricGroup
            }
            current.append(event)
        }

        appendCurrentGroup()
        return output
    }
}
