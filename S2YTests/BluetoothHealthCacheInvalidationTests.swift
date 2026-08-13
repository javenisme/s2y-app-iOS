//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT

@testable import S2Y
import XCTest

final class BluetoothHealthCacheInvalidationTests: XCTestCase {
    func testPulseOximeterInvalidatesOnlyMetricsPresentInPayload() {
        let oxygenOnly = BluetoothHealthData(
            deviceType: .pulseOximeter,
            oxygenSaturation: 0.98
        )

        XCTAssertEqual(oxygenOnly.affectedMetricKinds, [.oxygenSaturation])
    }

    func testBloodPressureInvalidatesBothPressureMetrics() {
        let pressure = BluetoothHealthData(
            deviceType: .bloodPressureMonitor,
            systolicPressure: 120,
            diastolicPressure: 80
        )

        XCTAssertEqual(
            pressure.affectedMetricKinds,
            [.bloodPressureSystolic, .bloodPressureDiastolic]
        )
    }
}
