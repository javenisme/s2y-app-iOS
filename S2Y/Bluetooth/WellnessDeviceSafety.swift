//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT
//

import Foundation

/// Capabilities a wellness device may expose after identity verification.
///
/// The app deliberately models abstract, user-facing capabilities here. Hardware
/// parameters and medical treatment modes are not part of this contract.
public enum WellnessDeviceCapability: String, Codable, Sendable, CaseIterable {
    case relaxationSession
    case levelAdjustment
    case sessionTimer
    case immediateStop
    case batteryStatus
}

public struct WellnessDeviceIdentity: Codable, Sendable, Equatable {
    public let deviceID: UUID
    public let productIdentifier: String
    public let firmwareVersion: String
    public let protocolVersion: Int
    public let reportedCapabilities: Set<WellnessDeviceCapability>
    public let manufacturerSignatureValidated: Bool

    public init(
        deviceID: UUID,
        productIdentifier: String,
        firmwareVersion: String,
        protocolVersion: Int,
        reportedCapabilities: Set<WellnessDeviceCapability>,
        manufacturerSignatureValidated: Bool
    ) {
        self.deviceID = deviceID
        self.productIdentifier = productIdentifier
        self.firmwareVersion = firmwareVersion
        self.protocolVersion = protocolVersion
        self.reportedCapabilities = reportedCapabilities
        self.manufacturerSignatureValidated = manufacturerSignatureValidated
    }
}

public struct VerifiedWellnessDevice: Sendable, Equatable {
    public let identity: WellnessDeviceIdentity
    public let allowedCapabilities: Set<WellnessDeviceCapability>
}

public enum WellnessDeviceTrustFailure: Error, Sendable, Equatable {
    case invalidManufacturerSignature
    case unsupportedProduct
    case unsupportedProtocol
    case missingImmediateStop
    case noAllowedCapabilities
}

/// Fail-closed device identity and capability policy.
public struct WellnessDeviceTrustPolicy: Sendable {
    public let supportedProductIdentifiers: Set<String>
    public let supportedProtocolVersions: ClosedRange<Int>
    public let allowedCapabilities: Set<WellnessDeviceCapability>

    public init(
        supportedProductIdentifiers: Set<String>,
        supportedProtocolVersions: ClosedRange<Int>,
        allowedCapabilities: Set<WellnessDeviceCapability> = Set(WellnessDeviceCapability.allCases)
    ) {
        self.supportedProductIdentifiers = supportedProductIdentifiers
        self.supportedProtocolVersions = supportedProtocolVersions
        self.allowedCapabilities = allowedCapabilities
    }

    public func verify(_ identity: WellnessDeviceIdentity) throws -> VerifiedWellnessDevice {
        guard identity.manufacturerSignatureValidated else {
            throw WellnessDeviceTrustFailure.invalidManufacturerSignature
        }
        guard supportedProductIdentifiers.contains(identity.productIdentifier) else {
            throw WellnessDeviceTrustFailure.unsupportedProduct
        }
        guard supportedProtocolVersions.contains(identity.protocolVersion) else {
            throw WellnessDeviceTrustFailure.unsupportedProtocol
        }
        guard identity.reportedCapabilities.contains(.immediateStop) else {
            throw WellnessDeviceTrustFailure.missingImmediateStop
        }

        let capabilities = identity.reportedCapabilities.intersection(allowedCapabilities)
        guard !capabilities.isEmpty else {
            throw WellnessDeviceTrustFailure.noAllowedCapabilities
        }
        return VerifiedWellnessDevice(identity: identity, allowedCapabilities: capabilities)
    }
}
