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

public enum WellnessSessionPurpose: String, Codable, Sendable, CaseIterable {
    case relaxation
    case mindfulBreak
    case windDown
}

public enum WellnessSessionOrigin: String, Codable, Sendable {
    case userCreated
    case assistantDraft
}

/// A user-readable request that intentionally excludes hardware stimulation parameters.
public struct WellnessSessionRequest: Codable, Sendable, Equatable {
    public let id: UUID
    public let deviceID: UUID
    public let purpose: WellnessSessionPurpose
    public let durationMinutes: Int
    public let comfortLevel: Int
    public let origin: WellnessSessionOrigin

    public init(
        id: UUID = UUID(),
        deviceID: UUID,
        purpose: WellnessSessionPurpose,
        durationMinutes: Int,
        comfortLevel: Int,
        origin: WellnessSessionOrigin
    ) {
        self.id = id
        self.deviceID = deviceID
        self.purpose = purpose
        self.durationMinutes = durationMinutes
        self.comfortLevel = comfortLevel
        self.origin = origin
    }
}

public struct ValidatedWellnessSession: Sendable, Equatable {
    public let request: WellnessSessionRequest
    public let validatedAt: Date
    public let expiresAt: Date
}

public enum WellnessSessionValidationFailure: Error, Sendable, Equatable {
    case deviceMismatch
    case missingCapability(WellnessDeviceCapability)
    case durationOutOfRange
    case comfortLevelOutOfRange
    case cooldownActive(until: Date)
}

/// Fixed local safety envelope. Server or AI suggestions cannot widen these bounds.
public struct WellnessSessionSafetyPolicy: Sendable {
    public let durationRange: ClosedRange<Int>
    public let comfortLevelRange: ClosedRange<Int>
    public let minimumCooldown: TimeInterval
    public let validationLifetime: TimeInterval

    public init(
        durationRange: ClosedRange<Int> = 1 ... 20,
        comfortLevelRange: ClosedRange<Int> = 1 ... 3,
        minimumCooldown: TimeInterval = 60 * 60,
        validationLifetime: TimeInterval = 5 * 60
    ) {
        self.durationRange = durationRange
        self.comfortLevelRange = comfortLevelRange
        self.minimumCooldown = minimumCooldown
        self.validationLifetime = validationLifetime
    }

    public func validate(
        _ request: WellnessSessionRequest,
        for device: VerifiedWellnessDevice,
        lastSessionEndedAt: Date?,
        now: Date = .now
    ) throws -> ValidatedWellnessSession {
        guard request.deviceID == device.identity.deviceID else {
            throw WellnessSessionValidationFailure.deviceMismatch
        }
        for capability in [
            WellnessDeviceCapability.relaxationSession,
            .sessionTimer,
            .immediateStop
        ] where !device.allowedCapabilities.contains(capability) {
            throw WellnessSessionValidationFailure.missingCapability(capability)
        }
        guard durationRange.contains(request.durationMinutes) else {
            throw WellnessSessionValidationFailure.durationOutOfRange
        }
        guard comfortLevelRange.contains(request.comfortLevel) else {
            throw WellnessSessionValidationFailure.comfortLevelOutOfRange
        }
        if let lastSessionEndedAt {
            let allowedAt = lastSessionEndedAt.addingTimeInterval(minimumCooldown)
            guard now >= allowedAt else {
                throw WellnessSessionValidationFailure.cooldownActive(until: allowedAt)
            }
        }
        return ValidatedWellnessSession(
            request: request,
            validatedAt: now,
            expiresAt: now.addingTimeInterval(validationLifetime)
        )
    }
}
