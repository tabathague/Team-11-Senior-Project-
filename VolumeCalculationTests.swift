//
//  Untitled.swift
//  BiteToByte
//
//  Created by Tabatha Guebard on 5/20/26.
//

//
//  VolumeCalculationTests.swift
//  BiteToByte
//
//  Tests the volume accumulation logic from WebSocketManager.processReading
//  using 300 simulated readings at 12 mL/hr every 10 seconds.
//
//  HOW TO ADD:
//  1. In Xcode: File → New → Target → Unit Testing Bundle (name it "BiteToByteTe sts")
//  2. Add this file to that test target
//  3. Run with Cmd+U
//

import XCTest
import CoreData
@testable import BiteToByte

class VolumeCalculationTests: XCTestCase {

    // MARK: - In-memory CoreData stack for testing

    var context: NSManagedObjectContext!

    override func setUp() {
        super.setUp()
        let container = NSPersistentContainer(name: "FeedingModel")
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, error in
            XCTAssertNil(error, "Failed to load in-memory store: \(error!)")
        }
        context = container.viewContext
    }

    override func tearDown() {
        context = nil
        super.tearDown()
    }

    // MARK: - Volume Calculator (mirrors WebSocketManager logic)

    /// Mirrors the volume accumulation logic in WebSocketManager.processReading
    struct VolumeAccumulator {
        var lastTimestamp: Date? = nil
        var currentPeriodVolume: Double = 0.0
        var totalVolume: Double = 0.0

        mutating func process(rate: Double, timestamp: Date) -> Double {
            if let lastTime = lastTimestamp {
                let hoursElapsed = timestamp.timeIntervalSince(lastTime) / 3600.0
                let increment = rate * hoursElapsed
                currentPeriodVolume += increment
                totalVolume += increment
            }
            lastTimestamp = timestamp
            return currentPeriodVolume
        }
    }

    // MARK: - Generate 300 readings

    /// Generates N readings at a fixed rate, spaced intervalSeconds apart
    func generateReadings(
        count: Int,
        rateMLperHr: Double,
        intervalSeconds: Double,
        startDate: Date = Date()
    ) -> [(timestamp: Date, rate: Double)] {
        return (0..<count).map { i in
            let timestamp = startDate.addingTimeInterval(Double(i) * intervalSeconds)
            return (timestamp: timestamp, rate: rateMLperHr)
        }
    }

    // MARK: - Tests

    func testConstantRate12MLhr_300readings_10secInterval() {
        // Setup
        let rate = 12.0          // mL/hr
        let interval = 10.0      // seconds between readings
        let count = 300

        let readings = generateReadings(count: count, rateMLperHr: rate, intervalSeconds: interval)
        var accumulator = VolumeAccumulator()

        // Process all readings
        for r in readings {
            _ = accumulator.process(rate: r.rate, timestamp: r.timestamp)
        }

        // Expected: 299 intervals × (10/3600) hr × 12 mL/hr
        let expectedVolume = Double(count - 1) * (interval / 3600.0) * rate
        let tolerance = 0.001 // mL

        print("[TEST] 300 readings @ 12 mL/hr every 10s")
        print("[TEST] Expected volume: \(String(format: "%.4f", expectedVolume)) mL")
        print("[TEST] Actual volume:   \(String(format: "%.4f", accumulator.totalVolume)) mL")

        XCTAssertEqual(accumulator.totalVolume, expectedVolume, accuracy: tolerance,
            "Volume mismatch: expected \(expectedVolume) mL, got \(accumulator.totalVolume) mL")
    }

    func testConstantRate125MLhr_300readings_10secInterval() {
        let rate = 125.0
        let interval = 10.0
        let count = 300

        let readings = generateReadings(count: count, rateMLperHr: rate, intervalSeconds: interval)
        var accumulator = VolumeAccumulator()

        for r in readings {
            _ = accumulator.process(rate: r.rate, timestamp: r.timestamp)
        }

        let expectedVolume = Double(count - 1) * (interval / 3600.0) * rate
        let tolerance = 0.001

        print("[TEST] 300 readings @ 125 mL/hr every 10s")
        print("[TEST] Expected volume: \(String(format: "%.4f", expectedVolume)) mL")
        print("[TEST] Actual volume:   \(String(format: "%.4f", accumulator.totalVolume)) mL")

        XCTAssertEqual(accumulator.totalVolume, expectedVolume, accuracy: tolerance)
    }

    func testFirstReadingProducesZeroVolume() {
        // First reading should always produce 0 — no previous timestamp to diff against
        var accumulator = VolumeAccumulator()
        let volume = accumulator.process(rate: 12.0, timestamp: Date())

        print("[TEST] First reading volume: \(volume) mL (expected 0.0)")
        XCTAssertEqual(volume, 0.0, "First reading should produce 0 volume")
    }

    func testVaryingRates_300readings() {
        // Alternates between 12 and 50 mL/hr every 10 seconds
        let interval = 10.0
        let count = 300
        let startDate = Date()
        var accumulator = VolumeAccumulator()
        var expectedVolume = 0.0
        var lastTimestamp: Date? = nil

        for i in 0..<count {
            let rate = i % 2 == 0 ? 12.0 : 50.0
            let timestamp = startDate.addingTimeInterval(Double(i) * interval)

            if let last = lastTimestamp {
                let hoursElapsed = timestamp.timeIntervalSince(last) / 3600.0
                expectedVolume += rate * hoursElapsed
            }
            lastTimestamp = timestamp
            _ = accumulator.process(rate: rate, timestamp: timestamp)
        }

        print("[TEST] 300 readings alternating 12/50 mL/hr every 10s")
        print("[TEST] Expected volume: \(String(format: "%.4f", expectedVolume)) mL")
        print("[TEST] Actual volume:   \(String(format: "%.4f", accumulator.totalVolume)) mL")

        XCTAssertEqual(accumulator.totalVolume, expectedVolume, accuracy: 0.001)
    }

    func testIrregularIntervals_300readings() {
        // Simulates real-world irregular timing (Pi sleeps 10s but actual interval varies)
        let rate = 12.0
        let count = 300
        let startDate = Date()
        var accumulator = VolumeAccumulator()
        var expectedVolume = 0.0
        var lastTimestamp: Date? = nil

        for i in 0..<count {
            // Vary interval between 9 and 11 seconds randomly
            let jitter = Double.random(in: -1.0...1.0)
            let interval = 10.0 + jitter
            let timestamp = startDate.addingTimeInterval(Double(i) * 10.0 + jitter)

            if let last = lastTimestamp {
                let hoursElapsed = timestamp.timeIntervalSince(last) / 3600.0
                expectedVolume += rate * hoursElapsed
            }
            lastTimestamp = timestamp
            _ = accumulator.process(rate: rate, timestamp: timestamp)
        }

        print("[TEST] 300 readings @ 12 mL/hr with ±1s jitter")
        print("[TEST] Expected volume: \(String(format: "%.4f", expectedVolume)) mL")
        print("[TEST] Actual volume:   \(String(format: "%.4f", accumulator.totalVolume)) mL")

        XCTAssertEqual(accumulator.totalVolume, expectedVolume, accuracy: 0.001)
    }

    func testTwoPeriodBoundary_300readings() {
        // Verifies volume resets correctly at the 2-hour period boundary
        let rate = 12.0
        let interval = 10.0
        let count = 300  // 300 × 10s = 2990s ≈ 49.8 minutes (within first period)
        let startDate = Date()

        var accumulator = VolumeAccumulator()
        var lastTimestamp: Date? = nil
        var periodVolume = 0.0
        var periodStart = startDate
        var periodsClosed = 0

        for i in 0..<count {
            let timestamp = startDate.addingTimeInterval(Double(i) * interval)

            if let last = lastTimestamp {
                let hoursElapsed = timestamp.timeIntervalSince(last) / 3600.0
                periodVolume += rate * hoursElapsed

                // Close period at 2 hours
                if timestamp.timeIntervalSince(periodStart) >= 7200 {
                    print("[TEST] Period closed at reading \(i): \(String(format: "%.4f", periodVolume)) mL")
                    periodsClosed += 1
                    periodVolume = 0.0
                    periodStart = timestamp
                }
            }
            lastTimestamp = timestamp
            _ = accumulator.process(rate: rate, timestamp: timestamp)
        }

        print("[TEST] Total volume across \(count) readings: \(String(format: "%.4f", accumulator.totalVolume)) mL")
        print("[TEST] Periods closed: \(periodsClosed)")

        // 300 readings at 10s = 2990s total = ~0.830 hours
        // Expected total: 0.830 hr × 12 mL/hr ≈ 9.97 mL
        let expectedTotal = Double(count - 1) * (interval / 3600.0) * rate
        XCTAssertEqual(accumulator.totalVolume, expectedTotal, accuracy: 0.001)
    }

    func testPrintAllReadings_12MLhr_300readings() {
        // Prints a summary table of every 30th reading for visual inspection
        let rate = 12.0
        let interval = 10.0
        let count = 300
        let startDate = Date()

        var accumulator = VolumeAccumulator()

        print("\n[TEST] Reading summary (every 30th):")
        print(String(format: "%-10s %-20s %-15s", "Reading", "Elapsed (min)", "Volume (mL)"))
        print(String(repeating: "-", count: 50))

        for i in 0..<count {
            let timestamp = startDate.addingTimeInterval(Double(i) * interval)
            _ = accumulator.process(rate: rate, timestamp: timestamp)

            if i % 30 == 0 || i == count - 1 {
                let elapsedMin = Double(i) * interval / 60.0
                print(String(format: "%-10d %-20.2f %-15.4f",
                    i, elapsedMin, accumulator.totalVolume))
            }
        }

        let expectedVolume = Double(count - 1) * (interval / 3600.0) * rate
        XCTAssertEqual(accumulator.totalVolume, expectedVolume, accuracy: 0.001)
    }
}
