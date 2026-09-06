import AirPostureCore
import Foundation

private func check(_ condition: Bool, _ name: String) {
    if !condition {
        failures += 1
        FileHandle.standardError.write(Data("FAIL \(name)\n".utf8))
    }
}

func runAnalyticsChecks() {
    do {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        func date(_ key: String) -> Date { PostureAnalytics.parseDayKey(key, calendar: calendar)! }
        let legacy = try JSONDecoder().decode(DayBucket.self, from: Data(#"{"monitoredSeconds":100,"offNeutralSeconds":40,"slouchEpisodes":2}"#.utf8))
        expectEqual(legacy.unsplitSeconds, 40, "legacy off-neutral stays unsplit")
        expectEqual(legacy.uprightSeconds, 60, "legacy upright total preserved")
        expectEqual(legacy.countdownSeconds, 0, "legacy countdown is unknown")
        expectEqual(legacy.slouchSeconds, 0, "legacy slouch duration is unknown")
        // Exact comparisons catch tiny false legacy segments that would pass the
        // ordinary duration tolerance and still make the native UI show an unsplit row.
        let fractionalOff = 17.5 * (0.12 + 3 * 0.10)
        let fractionalCountdown = fractionalOff * 0.35
        let fractionalSlouch = fractionalOff * 0.65
        let classifiedSeconds = fractionalCountdown + fractionalSlouch
        let fullyClassified = DayBucket(monitoredSeconds: 17.5, offNeutralSeconds: classifiedSeconds,
                                        countdownSeconds: fractionalCountdown, slouchSeconds: fractionalSlouch)
        check(fullyClassified.unsplitSeconds == 0, "fractional fully classified bucket has exactly zero legacy remainder")
        let fractionalLegacy = DayBucket(monitoredSeconds: 17.5, offNeutralSeconds: classifiedSeconds + 0.25,
                                         countdownSeconds: fractionalCountdown, slouchSeconds: fractionalSlouch)
        check(fractionalLegacy.unsplitSeconds == 0.25, "genuine fractional legacy remainder is preserved exactly")
        let tinyLegacy = DayBucket(monitoredSeconds: 17.5, offNeutralSeconds: classifiedSeconds.nextUp,
                                  countdownSeconds: fractionalCountdown, slouchSeconds: fractionalSlouch)
        check(tinyLegacy.unsplitSeconds == classifiedSeconds.nextUp - classifiedSeconds,
              "a genuine one-ULP legacy remainder is preserved rather than rounded away")
        let schema1 = Data(#"{"schemaVersion":1,"days":{"2026-09-06":{"monitoredSeconds":100.5,"offNeutralSeconds":40.25,"slouchEpisodes":2}}}"#.utf8)
        let migrated = try JSONDecoder().decode(AnalyticsDocument.self, from: schema1)
        expectEqual(migrated.days["2026-09-06"]!.monitoredSeconds, 100.5, "fractional legacy duration preserved")
        let encoded = try JSONEncoder().encode(migrated)
        let object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        check(object["schemaVersion"] as? Int == 2, "migration writes schema 2")
        check(try JSONDecoder().decode(AnalyticsDocument.self, from: encoded).days == migrated.days, "schema 2 round trip")
        for malformed in [
            #"{"monitoredSeconds":-1,"offNeutralSeconds":0,"slouchEpisodes":0}"#,
            #"{"monitoredSeconds":10,"offNeutralSeconds":11,"slouchEpisodes":0}"#,
            #"{"monitoredSeconds":10,"offNeutralSeconds":5,"countdownSeconds":4,"slouchSeconds":2,"slouchEpisodes":0}"#,
            #"{"monitoredSeconds":10,"offNeutralSeconds":0,"slouchEpisodes":-1}"#,
            #"{"monitoredSeconds":10,"offNeutralSeconds":0,"countdownSeconds":null,"slouchEpisodes":0}"#
        ] {
            check((try? JSONDecoder().decode(DayBucket.self, from: Data(malformed.utf8))) == nil, "malformed bucket rejected: \(malformed)")
        }
        for version in [0, 3] {
            let invalid = Data("{\"schemaVersion\":\(version),\"days\":{}}".utf8)
            check((try? JSONDecoder().decode(AnalyticsDocument.self, from: invalid)) == nil, "unsupported schema rejected")
        }
        check(PostureAnalytics.parseDayKey("2026-02-30", calendar: calendar) == nil, "invalid calendar date rejected")
        check(PostureAnalytics.parseDayKey("2026-9-6", calendar: calendar) == nil, "noncanonical key rejected")

        var accumulator = AnalyticsAccumulator(days: ["2026-09-06": legacy], calendar: calendar)
        let start = date("2026-09-06").addingTimeInterval(12 * 3600)
        accumulator.observe(.upright, at: start, monotonic: 100)
        accumulator.observe(.countdown, at: start.addingTimeInterval(2.5), monotonic: 102.5)
        accumulator.observe(.slouch, at: start.addingTimeInterval(7.5), monotonic: 107.5)
        accumulator.observe(.slouch, at: start.addingTimeInterval(8.5), monotonic: 108.5)
        accumulator.observe(.inactive, at: start.addingTimeInterval(10), monotonic: 110)
        accumulator.advance(to: start.addingTimeInterval(500), monotonic: 600)
        let mixed = accumulator.days["2026-09-06"]!
        expectEqual(mixed.monitoredSeconds, 110, "elapsed fractions classified and inactive excluded")
        expectEqual(mixed.countdownSeconds, 5, "countdown until sustained transition")
        expectEqual(mixed.slouchSeconds, 2.5, "sustained interval duration")
        expectEqual(mixed.unsplitSeconds, 40, "new recordings preserve same-day legacy remainder")
        expectEqual(mixed.uprightSeconds + mixed.countdownSeconds + mixed.slouchSeconds + mixed.unsplitSeconds, 110, "category conservation")
        check(mixed.slouchEpisodes == 3, "one episode per sustained edge")
        accumulator.observe(.upright, at: start.addingTimeInterval(1000), monotonic: 1100)
        accumulator.advance(to: start.addingTimeInterval(1002), monotonic: 1102)
        expectEqual(accumulator.days["2026-09-06"]!.monitoredSeconds, 112, "reconnect does not backfill")
        accumulator.suspend(at: start.addingTimeInterval(1003), monotonic: 1103)
        accumulator.advance(to: start.addingTimeInterval(5000), monotonic: 5100)
        expectEqual(accumulator.days["2026-09-06"]!.monitoredSeconds, 113, "sleep and waiting for fresh observation excluded")
        accumulator.observe(.upright, at: start.addingTimeInterval(5000), monotonic: 5100)
        accumulator.advance(to: start.addingTimeInterval(5001), monotonic: 5101)
        expectEqual(accumulator.days["2026-09-06"]!.monitoredSeconds, 114, "fresh unchanged-zone observation resumes after wake")

        var midnight = AnalyticsAccumulator(calendar: calendar)
        let beforeMidnight = date("2026-09-06").addingTimeInterval(-0.5)
        midnight.observe(.slouch, at: beforeMidnight, monotonic: 0)
        midnight.advance(to: beforeMidnight.addingTimeInterval(2), monotonic: 2)
        expectEqual(midnight.days["2026-09-05"]!.slouchSeconds, 0.5, "midnight prior-day portion")
        expectEqual(midnight.days["2026-09-06"]!.slouchSeconds, 1.5, "midnight next-day portion")
        check(midnight.days["2026-09-05"]!.slouchEpisodes == 1 && midnight.days["2026-09-06"]!.slouchEpisodes == 0, "midnight does not create episode")
        for (key, seconds, next) in [("2026-03-08", 82800.0, "2026-03-09"), ("2026-11-01", 90000.0, "2026-11-02")] {
            var dst = AnalyticsAccumulator(calendar: calendar)
            dst.observe(.upright, at: date(key), monotonic: 0)
            dst.advance(to: date(next).addingTimeInterval(10), monotonic: seconds + 10)
            expectEqual(dst.days[key]!.monitoredSeconds, seconds, "DST local-day duration \(key)")
            expectEqual(dst.days[next]!.monitoredSeconds, 10, "DST next-day portion \(key)")
        }
        var clockJump = AnalyticsAccumulator(calendar: calendar)
        clockJump.observe(.upright, at: start, monotonic: 1)
        clockJump.advance(to: start.addingTimeInterval(3600), monotonic: 3)
        expectEqual(clockJump.days["2026-09-06"]!.monitoredSeconds, 2, "wall clock jumps do not inflate duration")

        var fractional = AnalyticsAccumulator(calendar: calendar)
        fractional.observe(.upright, at: start, monotonic: 0)
        fractional.advance(to: start, monotonic: 0.00000001)
        expectEqual(fractional.days["2026-09-06"]?.monitoredSeconds ?? 0, 0.00000001, "duration uses monotonic precision rather than wall-date precision", accuracy: 0.00000000001)

        var stale = AnalyticsAccumulator(calendar: calendar)
        stale.observe(.upright, at: start, monotonic: 100)
        stale.advance(to: start.addingTimeInterval(10), monotonic: 110)
        stale.observe(.countdown, at: start.addingTimeInterval(5), monotonic: 105)
        stale.advance(to: start.addingTimeInterval(12), monotonic: 112)
        expectEqual(stale.days["2026-09-06"]!.monitoredSeconds, 12, "out-of-order observation cannot duplicate elapsed time")
        expectEqual(stale.days["2026-09-06"]!.countdownSeconds, 0, "out-of-order observation cannot replace scoring state")

        stale.suspend(at: start.addingTimeInterval(13), monotonic: 113)
        stale.observe(.slouch, at: start.addingTimeInterval(11), monotonic: 111)
        stale.advance(to: start.addingTimeInterval(20), monotonic: 120)
        expectEqual(stale.days["2026-09-06"]!.monitoredSeconds, 13, "stale observation cannot reopen a suspended interval")
        check(stale.days["2026-09-06"]!.slouchEpisodes == 0, "stale observation cannot create an episode")

        let historyDays = [
            "2026-09-01": DayBucket(monitoredSeconds: 60),
            "2026-09-02": DayBucket(monitoredSeconds: 540, offNeutralSeconds: 540),
            "2026-09-04": DayBucket(monitoredSeconds: 60)
        ]
        let points = PostureAnalytics.history(days: historyDays, ending: date("2026-09-06"), count: 7, calendar: calendar)
        check(points.count == 7, "inclusive history range has exactly requested dates")
        expectEqual(points[2].trendPercent!, 10, "trend is duration weighted, not 50 percent")
        check(points[1].trendPercent == nil, "one observed date cannot produce trend")
        check(points[3].dailyPercent == nil && points[3].trendPercent == nil, "missing day has neither daily nor trend point")
        check(points[2].segmentID != points[4].segmentID, "daily line breaks across missing day")
        expectEqual(points[2].trendMonitoredSeconds, 600, "trend duration coverage")
        check(points[2].trendObservedDays == 2, "trend observed-day coverage")
        var comparisonDays = historyDays
        comparisonDays["2026-08-25"] = DayBucket(monitoredSeconds: 100, offNeutralSeconds: 50)
        let comparison = PostureAnalytics.comparison(days: comparisonDays, ending: date("2026-09-06"), calendar: calendar)
        expectEqual(comparison.previous.percentUpright!, 50, "previous period weighted percentage")
        expectEqual(comparison.latest.monitoredSeconds, 660, "latest period duration coverage")
        check(comparison.latest.observedDays == 3 && comparison.previous.observedDays == 1, "comparison calendar coverage")
        expectEqual(comparison.changePoints!, -31.818181818, "comparison percentage-point difference", accuracy: 0.000001)
        check(PostureAnalytics.comparison(days: [:], ending: start, calendar: calendar).changePoints == nil, "empty comparison requires more history")
        let boundaryDays = ["2026-06-08": legacy, "2026-06-09": legacy, "2026-09-06": legacy, "2026-09-07": legacy]
        let retained = PostureAnalytics.prune(days: boundaryDays, now: date("2026-09-06"), calendar: calendar)
        check(Set(retained.keys) == Set(["2026-06-09", "2026-09-06"]), "retention keeps today and 89 preceding dates only")
    } catch {
        check(false, "unexpected analytics error: \(error)")
    }
}
