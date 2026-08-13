//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 Stanford University
//
// SPDX-License-Identifier: MIT

@testable import S2Y
import XCTest

final class OmerMobileChatModelsTests: XCTestCase {
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    func testChatRequestMatchesFirebaseMobileAPIContract() throws {
        let requestID = try XCTUnwrap(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let conversationID = try XCTUnwrap(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let messageID = try XCTUnwrap(UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
        let request = OmerMobileChatRequest(
            requestId: requestID,
            conversationId: conversationID,
            agentId: "health-assistant",
            message: .init(id: messageID, text: "I feel dizzy"),
            locale: "en_US",
            healthContext: ["recentSymptoms": "dizziness"],
            client: .init(platform: "ios", version: "1.0")
        )

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(request)) as? [String: Any])
        XCTAssertEqual(json["requestId"] as? String, requestID.uuidString)
        XCTAssertEqual(json["conversationId"] as? String, conversationID.uuidString)
        XCTAssertEqual(json["agentId"] as? String, "health-assistant")
        XCTAssertEqual((json["message"] as? [String: Any])?["text"] as? String, "I feel dizzy")
        XCTAssertEqual((json["client"] as? [String: Any])?["platform"] as? String, "ios")
    }

    func testChatResponseDecodesApprovalAndToolResult() throws {
        let data = Data(#"""
        {
          "answer": "I can log that symptom after you approve.",
          "conversationId": "22222222-2222-2222-2222-222222222222",
          "requestId": "11111111-1111-1111-1111-111111111111",
          "agentId": "health-assistant",
          "billing": {
            "plan": "pro",
            "usedTokens": 1200,
            "monthlyTokenLimit": 2000000,
            "remainingTokens": 1998800
          },
          "toolEvents": [
            {
              "type": "approval-required",
              "approvalId": "approval-1",
              "toolCallId": "tool-1",
              "toolName": "logSymptoms"
            },
            {
              "type": "result",
              "toolCallId": "tool-2",
              "toolName": "getCommonSymptoms"
            }
          ]
        }
        """#.utf8)

        let response = try decoder.decode(OmerMobileChatResponse.self, from: data)
        XCTAssertEqual(response.agentId, "health-assistant")
        XCTAssertEqual(response.toolEvents.count, 2)
        XCTAssertEqual(response.toolEvents[0].approvalId, "approval-1")
        XCTAssertEqual(response.toolEvents[0].toolName, "logSymptoms")
        XCTAssertEqual(response.toolEvents[1].type, "result")
        XCTAssertEqual(response.billing?.plan, "pro")
        XCTAssertEqual(response.billing?.remainingTokens, 1_998_800)
    }

    func testAgentRegistryResponseDecodesRiskAndApprovalMetadata() throws {
        let data = Data(#"""
        {
          "agents": [{
            "id": "health-assistant",
            "name": "Health Assistant",
            "description": "Health-aware support",
            "capabilities": ["health-chat"],
            "tools": [{
              "id": "logSymptoms",
              "risk": "write",
              "requiresApproval": true
            }]
          }]
        }
        """#.utf8)

        let response = try decoder.decode(OmerAgentsResponse.self, from: data)
        let agent = try XCTUnwrap(response.agents.first)
        let tool = try XCTUnwrap(agent.tools.first)
        XCTAssertEqual(agent.id, "health-assistant")
        XCTAssertEqual(tool.risk, "write")
        XCTAssertTrue(tool.requiresApproval)
    }

    func testToolDecisionEncodesOnlyExplicitApproval() throws {
        let data = try encoder.encode(OmerToolDecisionRequest(approved: false))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json.count, 1)
        XCTAssertEqual(json["approved"] as? Bool, false)
    }

    func testCrossPlatformChatListAndDetailDecode() throws {
        let listData = Data(#"""
        {
          "chats": [{
            "id": "22222222-2222-2222-2222-222222222222",
            "createdAt": "2026-08-11T16:00:00.000Z",
            "title": "Symptoms after activity",
            "userId": "99999999-9999-9999-9999-999999999999",
            "visibility": "private"
          }],
          "hasMore": false
        }
        """#.utf8)
        let list = try decoder.decode(OmerChatListResponse.self, from: listData)
        XCTAssertEqual(list.chats.first?.title, "Symptoms after activity")
        XCTAssertFalse(list.hasMore)

        let detailData = Data(#"""
        {
          "chat": {
            "id": "22222222-2222-2222-2222-222222222222",
            "createdAt": "2026-08-11T16:00:00.000Z",
            "title": "Symptoms after activity",
            "userId": "99999999-9999-9999-9999-999999999999",
            "visibility": "private"
          },
          "messages": [{
            "id": "33333333-3333-3333-3333-333333333333",
            "role": "user",
            "content": "Why do I crash after activity?",
            "createdAt": "2026-08-11T16:01:00.000Z"
          }]
        }
        """#.utf8)
        let detail = try decoder.decode(OmerChatDetailResponse.self, from: detailData)
        XCTAssertEqual(detail.chat.id, list.chats.first?.id)
        XCTAssertEqual(detail.messages.first?.role, "user")
        XCTAssertEqual(detail.messages.first?.content, "Why do I crash after activity?")
    }

    func testOnDeviceExchangeSyncContract() throws {
        let requestID = try XCTUnwrap(UUID(uuidString: "11111111-1111-4111-8111-111111111111"))
        let conversationID = try XCTUnwrap(UUID(uuidString: "22222222-2222-4222-8222-222222222222"))
        let request = OmerLocalChatSyncRequest(
            requestId: requestID,
            conversationId: conversationID,
            source: "ios-on-device",
            messages: [
                .init(id: UUID(), role: "user", content: "How did I sleep?"),
                .init(id: UUID(), role: "assistant", content: "Your on-device summary shows seven hours.")
            ]
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(request)) as? [String: Any])
        XCTAssertEqual(json["source"] as? String, "ios-on-device")
        XCTAssertEqual((json["messages"] as? [[String: Any]])?.count, 2)

        let responseData = Data(#"""
        {
          "requestId": "11111111-1111-4111-8111-111111111111",
          "conversationId": "22222222-2222-4222-8222-222222222222",
          "synced": true
        }
        """#.utf8)
        let response = try decoder.decode(OmerLocalChatSyncResponse.self, from: responseData)
        XCTAssertEqual(response.conversationId, conversationID)
        XCTAssertTrue(response.synced)
    }

    func testLocalChatCacheRoundTripsConversationContent() throws {
        let chatID = try XCTUnwrap(UUID(uuidString: "22222222-2222-4222-8222-222222222222"))
        let messageID = try XCTUnwrap(UUID(uuidString: "33333333-3333-4333-8333-333333333333"))
        let summary = OmerChatSummary(
            id: chatID,
            createdAt: "2026-08-12T12:00:00Z",
            title: "Sleep quality",
            visibility: "private"
        )
        let snapshot = OmerChatCacheSnapshot(
            chats: [summary],
            details: [
                OmerChatDetailResponse(
                    chat: summary,
                    messages: [
                        OmerChatHistoryMessage(
                            id: messageID,
                            role: "assistant",
                            content: "**Average:** 7.5 hours",
                            createdAt: "2026-08-12T12:00:01Z"
                        )
                    ]
                )
            ]
        )

        let decoded = try decoder.decode(OmerChatCacheSnapshot.self, from: encoder.encode(snapshot))
        XCTAssertEqual(decoded.chats.first?.id, chatID)
        XCTAssertEqual(decoded.details.first?.messages.first?.content, "**Average:** 7.5 hours")
    }

    func testAssistantMarkdownIsConvertedToDisplayText() throws {
        let markdown = "**Average sleep:** 7.5 hours\n\nYour consistency is *improving*."
        let rendered = try XCTUnwrap(ChatMarkdownRenderer.attributedString(from: markdown))
        let displayText = String(rendered.characters)

        XCTAssertTrue(displayText.contains("Average sleep:"))
        XCTAssertTrue(displayText.contains("improving"))
        XCTAssertFalse(displayText.contains("**"))
        XCTAssertFalse(displayText.contains("*improving*"))
    }

    func testChatHistoryGroupsConversationsByRelativeDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-12T18:00:00Z"))
        let chats = [
            OmerChatSummary(id: UUID(), createdAt: "2026-08-12T12:00:00.000Z", title: "Today", visibility: "private"),
            OmerChatSummary(id: UUID(), createdAt: "2026-08-11T12:00:00.000Z", title: "Yesterday", visibility: "private"),
            OmerChatSummary(id: UUID(), createdAt: "2026-08-08T12:00:00.000Z", title: "This week", visibility: "private"),
            OmerChatSummary(id: UUID(), createdAt: "invalid", title: "Earlier", visibility: "private")
        ]

        let sections = OmerChatHistorySection.grouped(chats, relativeTo: now, calendar: calendar)

        XCTAssertEqual(sections.map(\.title), ["Today", "Yesterday", "Previous 7 days", "Earlier"])
        XCTAssertEqual(sections.flatMap(\.chats).map(\.title), ["Today", "Yesterday", "This week", "Earlier"])
    }

    func testHealthSuggestionsOnlyIncludeAvailableMetrics() {
        let suggestions = HealthQuickQuerySuggestion.available(for: [.steps, .sleepDurationHours])

        XCTAssertEqual(suggestions.map(\.id), ["steps", "sleep"])
        XCTAssertFalse(suggestions.contains(where: { $0.metricKind == .heartRateAverage }))
        XCTAssertFalse(suggestions.contains(where: { $0.metricKind == .activeEnergy }))
    }

    func testAssistantMarkdownCreatesUserFriendlyBlocks() {
        let markdown = """
        # Sleep summary

        **Average:** 7.5 hours

        - Keep a consistent bedtime
        2. Review again next week

        > This is a wellness insight, not a diagnosis.
        """

        let blocks = ChatMarkdownRenderer.blocks(from: markdown)

        XCTAssertEqual(
            blocks.map(\.kind),
            [.heading(1), .paragraph, .unorderedListItem, .orderedListItem(2), .quote]
        )
        XCTAssertEqual(String(blocks[0].content.characters), "Sleep summary")
        XCTAssertEqual(String(blocks[1].content.characters), "Average: 7.5 hours")
        XCTAssertFalse(blocks.map { String($0.content.characters) }.joined().contains("**"))
    }

    func testHealthPermissionGroupsArePurposeBasedAndNonOverlapping() {
        let groups = HealthPermissionGroup.allCases
        let allMetrics = groups.flatMap(\.metricKinds)

        XCTAssertEqual(Set(allMetrics), Set(HealthKitService.MetricKind.allCases))
        XCTAssertEqual(allMetrics.count, Set(allMetrics).count)
        XCTAssertTrue(groups.allSatisfy { !$0.title.isEmpty && !$0.purpose.isEmpty })
    }

    func testHealthMetricFreshnessUsesClearAgeBands() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-12T18:00:00Z"))

        XCTAssertEqual(
            HealthMetricProvenance.freshness(for: now.addingTimeInterval(-24 * 60 * 60), relativeTo: now),
            .current
        )
        XCTAssertEqual(
            HealthMetricProvenance.freshness(for: now.addingTimeInterval(-4 * 24 * 60 * 60), relativeTo: now),
            .aging
        )
        XCTAssertEqual(
            HealthMetricProvenance.freshness(for: now.addingTimeInterval(-8 * 24 * 60 * 60), relativeTo: now),
            .stale
        )
    }

    func testClinicalRecordSummaryRoundTripsWithoutRawFHIRPayload() throws {
        let id = try XCTUnwrap(UUID(uuidString: "22222222-2222-4222-8222-222222222222"))
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-12T18:00:00Z"))
        let summary = ClinicalRecordSummary(
            id: id,
            category: .labResults,
            displayName: "Example laboratory result",
            recordedAt: date,
            sourceName: "Example Health Provider",
            hasLinkedFHIRResource: true
        )

        let data = try encoder.encode(summary)
        let decoded = try decoder.decode(ClinicalRecordSummary.self, from: data)

        XCTAssertEqual(decoded, summary)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("resourceType"))
    }

    func testClinicalRecordIndexFiltersDeduplicatesAndBoundsSummaries() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-12T18:00:00Z"))
        let selectedID = UUID()
        let selected = ClinicalRecordSummary(
            id: selectedID,
            category: .labResults,
            displayName: "Selected result",
            recordedAt: date,
            sourceName: "Provider A",
            hasLinkedFHIRResource: true
        )
        let olderDuplicate = ClinicalRecordSummary(
            id: selectedID,
            category: .labResults,
            displayName: "Duplicate result",
            recordedAt: date.addingTimeInterval(-60),
            sourceName: "Provider A",
            hasLinkedFHIRResource: true
        )
        let unselected = ClinicalRecordSummary(
            id: UUID(),
            category: .medications,
            displayName: "Medication",
            recordedAt: date,
            sourceName: "Provider B",
            hasLinkedFHIRResource: true
        )

        let index = ClinicalRecordIndex(
            records: [olderDuplicate, selected, unselected],
            selectedCategories: [.labResults],
            refreshedAt: date,
            maximumRecordCount: 1
        )

        XCTAssertEqual(index.records, [selected])
        XCTAssertEqual(index.maximumRecordCount, 1)
        let json = String(decoding: try encoder.encode(index), as: UTF8.self)
        XCTAssertFalse(json.contains("resourceType"))
    }

    func testClinicalRecordIndexReportsProvenanceCoverageAndRecency() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-12T18:00:00Z"))
        let recent = ClinicalRecordSummary(
            id: UUID(),
            category: .labResults,
            displayName: "Recent result",
            recordedAt: now.addingTimeInterval(-30 * 24 * 60 * 60),
            sourceName: "Provider A",
            hasLinkedFHIRResource: true
        )
        let historical = ClinicalRecordSummary(
            id: UUID(),
            category: .conditions,
            displayName: "Historical condition",
            recordedAt: now.addingTimeInterval(-400 * 24 * 60 * 60),
            sourceName: "Provider B",
            hasLinkedFHIRResource: false
        )
        let index = ClinicalRecordIndex(
            records: [recent, historical],
            selectedCategories: [.labResults, .conditions, .medications],
            refreshedAt: now
        )

        XCTAssertEqual(recent.recency(relativeTo: now), .recent)
        XCTAssertEqual(historical.recency(relativeTo: now), .historical)
        XCTAssertEqual(index.assessment.totalRecordCount, 2)
        XCTAssertEqual(index.assessment.sourceCount, 2)
        XCTAssertEqual(index.assessment.categoryCounts[.labResults], 1)
        XCTAssertEqual(index.assessment.selectedCategoriesWithoutReadableRecords, [.medications])
        XCTAssertEqual(index.assessment.newestRecordedAt, recent.recordedAt)
        XCTAssertEqual(index.assessment.oldestRecordedAt, historical.recordedAt)

        let json = String(decoding: try encoder.encode(index), as: UTF8.self)
        XCTAssertFalse(json.contains("Observation/"))
        XCTAssertFalse(json.contains("FHIRResourceIdentifier"))
    }

    @MainActor
    func testClinicalRecordIndexStorePersistsAndClearsLocalSummaryFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("summary-index.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = ClinicalRecordSummary(
            id: UUID(),
            category: .conditions,
            displayName: "Example condition",
            recordedAt: .now,
            sourceName: "Provider A",
            hasLinkedFHIRResource: true
        )
        let index = ClinicalRecordIndex(records: [record], selectedCategories: [.conditions])
        let store = ClinicalRecordIndexStore(fileURL: fileURL)

        try store.replace(with: index)

        XCTAssertEqual(store.index, index)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(ClinicalRecordIndexStore(fileURL: fileURL).index, index)

        try store.clear()

        XCTAssertNil(store.index)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testWearableMeasurementsNormalizeUnitsAndPreserveOrigin() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-12T18:00:00Z"))
        let input = WearableMeasurementInput(
            id: "energy-1",
            metricIdentifier: "HKQuantityTypeIdentifierActiveEnergyBurned",
            value: 418.4,
            unit: "kJ",
            startDate: date,
            endDate: date.addingTimeInterval(60),
            timeZoneIdentifier: "America/New_York",
            sourceIdentifier: "com.example.watch",
            sourceName: "Example Watch",
            deviceName: "Watch"
        )

        let result = try XCTUnwrap(WearableMeasurementNormalizer.normalize([input]).first)

        XCTAssertEqual(result.value, 100, accuracy: 0.001)
        XCTAssertEqual(result.unit, "kcal")
        XCTAssertEqual(result.originalValue, 418.4)
        XCTAssertEqual(result.originalUnit, "kJ")
        XCTAssertEqual(result.sourceIdentifier, "com.example.watch")
        XCTAssertEqual(result.timeZoneIdentifier, "America/New_York")
    }

    func testWearableDeduplicationIsScopedToSourceAndSyncIdentifier() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-12T18:00:00Z"))
        func sample(id: String, source: String, version: Int, value: Double) -> WearableMeasurementInput {
            WearableMeasurementInput(
                id: id,
                metricIdentifier: "HKQuantityTypeIdentifierStepCount",
                value: value,
                unit: "count",
                startDate: date,
                endDate: date,
                timeZoneIdentifier: "UTC",
                sourceIdentifier: source,
                sourceName: source,
                syncIdentifier: "shared-sync-id",
                syncVersion: version
            )
        }

        let normalized = WearableMeasurementNormalizer.normalize([
            sample(id: "old", source: "watch-a", version: 1, value: 10),
            sample(id: "new", source: "watch-a", version: 2, value: 20),
            sample(id: "other-source", source: "watch-b", version: 1, value: 30)
        ])

        XCTAssertEqual(normalized.count, 2)
        XCTAssertEqual(Set(normalized.map(\.id)), ["new", "other-source"])
    }

    func testWearableNormalizerRejectsVendorOnlyScores() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-12T18:00:00Z"))
        let vendorScore = WearableMeasurementInput(
            id: "score-1",
            metricIdentifier: "com.vendor.readiness-score",
            value: 92,
            unit: "score",
            startDate: date,
            endDate: date,
            timeZoneIdentifier: "UTC",
            sourceIdentifier: "com.vendor.app",
            sourceName: "Vendor"
        )

        XCTAssertTrue(WearableMeasurementNormalizer.normalize([vendorScore]).isEmpty)
    }

    func testTrendSummaryExcludesMissingDaysFromAverage() throws {
        let start = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-01T00:00:00Z"))
        var points: [HealthKitService.DailyMetric] = []
        for offset in 0..<7 {
            points.append(HealthKitService.DailyMetric(
                date: start.addingTimeInterval(Double(offset) * 86_400),
                value: offset < 2 ? Double((offset + 1) * 1_000) : 0,
                isObserved: offset < 2
            ))
        }

        let trend = HealthKitService.Trend.summarize(windowDays: 7, points: points)

        XCTAssertEqual(trend.average, 1_500)
        XCTAssertEqual(trend.changeRate, 1)
        XCTAssertEqual(trend.observedDays, 2)
        XCTAssertEqual(trend.dataQuality, .limited)
    }

    func testComparisonRequiresCoverageInBothWindows() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-01T00:00:00Z"))
        var current: [HealthKitService.DailyMetric] = []
        var previous: [HealthKitService.DailyMetric] = []
        for offset in 0..<7 {
            current.append(HealthKitService.DailyMetric(
                date: date.addingTimeInterval(Double(offset) * 86_400),
                value: 8_000,
                isObserved: true
            ))
            previous.append(HealthKitService.DailyMetric(
                date: date.addingTimeInterval(Double(offset - 7) * 86_400),
                value: offset < 2 ? 4_000 : 0,
                isObserved: offset < 2
            ))
        }

        let comparison = HealthKitService.Comparison.summarize(
            windowDays: 7,
            current: current,
            previous: previous
        )

        XCTAssertEqual(comparison.currentAverage, 8_000)
        XCTAssertEqual(comparison.previousAverage, 4_000)
        XCTAssertEqual(comparison.deltaRate, 1)
        XCTAssertEqual(comparison.dataQuality, .limited)
    }

    func testHealthChartRequestRecognizesTrendAndComparisonWindows() {
        XCTAssertEqual(
            HealthChartRequest.parse("How have my steps trended over the past 30 days?"),
            .trend(kind: .steps, days: 30)
        )
        XCTAssertEqual(
            HealthChartRequest.parse("Compare my heart rate this week vs last week"),
            .comparison(kind: .heartRateAverage, days: 7)
        )
        XCTAssertNil(HealthChartRequest.parse("What can I do to relax today?"))
    }

    func testHealthInterpretationStatesCoverageAndWellnessBoundary() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-01T00:00:00Z"))
        let trend = HealthKitService.Trend.summarize(
            windowDays: 7,
            points: [
                .init(date: date, value: 6, isObserved: true),
                .init(date: date.addingTimeInterval(86_400), value: 7, isObserved: true)
            ]
        )

        let context = HealthInterpretationPolicy.trendContext(trend, kind: .sleepDurationHours)

        XCTAssertTrue(context.contains("Coverage: 2/7 days"))
        XCTAssertTrue(context.contains("Coverage is limited"))
        XCTAssertTrue(context.contains("not a diagnosis or treatment recommendation"))
    }

    func testLongitudinalDatasetAlignsObservedValuesWithoutZeroImputation() throws {
        let calendar = Calendar(identifier: .gregorian)
        let start = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-01T12:00:00Z"))
        let dayTwo = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: start))
        let dataset = LongitudinalHealthAligner.align(
            series: [
                .steps: [
                    .init(date: start, value: 4_000),
                    .init(date: dayTwo, value: 0, isObserved: false)
                ],
                .sleepDurationHours: [
                    .init(date: dayTwo, value: 7.5)
                ]
            ],
            expectedDays: 7,
            calendar: calendar
        )

        XCTAssertEqual(dataset.days.count, 2)
        XCTAssertEqual(dataset.values(for: .steps).map(\.value), [4_000])
        XCTAssertEqual(dataset.values(for: .sleepDurationHours).map(\.value), [7.5])
        XCTAssertTrue(dataset.pairedValues(.steps, .sleepDurationHours).isEmpty)
        XCTAssertEqual(dataset.coverage.first(where: { $0.metricKind == .steps })?.observedDays, 1)
    }

    func testLongitudinalDatasetAveragesDuplicateSamplesWithinDay() throws {
        let calendar = Calendar(identifier: .gregorian)
        let morning = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-01T08:00:00Z"))
        let evening = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-01T20:00:00Z"))
        let dataset = LongitudinalHealthAligner.align(
            series: [
                .heartRateAverage: [
                    .init(date: morning, value: 60),
                    .init(date: evening, value: 80)
                ]
            ],
            expectedDays: 1,
            calendar: calendar
        )

        XCTAssertEqual(dataset.values(for: .heartRateAverage).map(\.value), [70])
        XCTAssertEqual(dataset.coverage.first?.dataQuality, .complete)
    }

    func testPersonalBaselineRequiresFourteenObservedDays() {
        let baseline = PersonalHealthBaselineAnalyzer.baseline(
            for: .restingHeartRate,
            values: Array(repeating: 60, count: 13)
        )

        XCTAssertEqual(baseline.availability, .insufficientData)
        XCTAssertNil(baseline.baselineMedian)
    }

    func testPersonalDeviationUsesRobustIndividualBaseline() {
        let baselineValues = [58, 59, 60, 61, 62, 58, 59, 60, 61, 62, 59, 60, 61, 60]
            .map(Double.init)

        let deviation = PersonalHealthBaselineAnalyzer.deviation(
            baselineValues: baselineValues,
            currentValues: [72, 73, 74],
            metricKind: .restingHeartRate
        )

        XCTAssertEqual(deviation.baselineMedian, 60)
        XCTAssertEqual(deviation.currentMedian, 73)
        XCTAssertEqual(deviation.direction, .higher)
        XCTAssertEqual(deviation.baselineObservedDays, 14)
    }

    func testPersonalDeviationIsUndeterminedWithTooFewCurrentDays() {
        let deviation = PersonalHealthBaselineAnalyzer.deviation(
            baselineValues: Array(repeating: 7.5, count: 14),
            currentValues: [5.5, 6],
            metricKind: .sleepDurationHours
        )

        XCTAssertEqual(deviation.direction, .undetermined)
        XCTAssertNil(deviation.robustDistance)
    }

    func testDescriptiveRelationshipUsesOnlyPairedDaysAndRejectsCausality() throws {
        let calendar = Calendar(identifier: .gregorian)
        let start = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-01T12:00:00Z"))
        var steps: [HealthKitService.DailyMetric] = []
        var sleep: [HealthKitService.DailyMetric] = []
        for offset in 0..<7 {
            let date = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: start))
            steps.append(.init(date: date, value: Double(offset + 1) * 1_000))
            sleep.append(.init(date: date, value: Double(offset + 1)))
        }
        let dataset = LongitudinalHealthAligner.align(
            series: [.steps: steps, .sleepDurationHours: sleep],
            expectedDays: 7,
            calendar: calendar
        )

        let relationship = DescriptiveHealthRelationshipAnalyzer.analyze(
            dataset: dataset,
            first: .steps,
            second: .sleepDurationHours
        )

        XCTAssertEqual(relationship.pairedDays, 7)
        XCTAssertEqual(relationship.direction, .movesTogether)
        XCTAssertEqual(relationship.strength, .strong)
        XCTAssertTrue(relationship.explanation.contains("not evidence that one caused the other"))
    }

    func testDescriptiveRelationshipRequiresSevenPairedDays() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-01T12:00:00Z"))
        let dataset = LongitudinalHealthAligner.align(
            series: [
                .steps: [.init(date: date, value: 5_000)],
                .sleepDurationHours: [.init(date: date, value: 7)]
            ],
            expectedDays: 30
        )

        let relationship = DescriptiveHealthRelationshipAnalyzer.analyze(
            dataset: dataset,
            first: .steps,
            second: .sleepDurationHours
        )

        XCTAssertEqual(relationship.availability, .insufficientData)
        XCTAssertNil(relationship.coefficient)
    }

    func testPersonalInsightReportRetainsCoverageAndTraceability() throws {
        let calendar = Calendar(identifier: .gregorian)
        let start = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-01T12:00:00Z"))
        var steps: [HealthKitService.DailyMetric] = []
        var sleep: [HealthKitService.DailyMetric] = []
        for offset in 0..<30 {
            let date = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: start))
            steps.append(.init(date: date, value: offset < 23 ? 5_000 : 8_000))
            sleep.append(.init(date: date, value: offset < 23 ? 7 : 8))
        }
        let dataset = LongitudinalHealthAligner.align(
            series: [.steps: steps, .sleepDurationHours: sleep],
            expectedDays: 30,
            calendar: calendar
        )

        let report = PersonalHealthInsightBuilder.build(dataset: dataset, generatedAt: start)

        XCTAssertEqual(report.coverage.count, 2)
        XCTAssertEqual(report.coverage.first(where: { $0.metricKind == .steps })?.observedDays, 30)
        XCTAssertEqual(report.deviations.first(where: { $0.metricKind == .steps })?.direction, .higher)
        XCTAssertEqual(report.relationships.first?.pairedDays, 30)
        XCTAssertTrue(report.hasUsableInsight)
    }

    func testPersonalInsightIntentIsExplicit() {
        XCTAssertTrue(PersonalHealthInsightLoader.matches("Show patterns in my health data"))
        XCTAssertTrue(PersonalHealthInsightLoader.matches("我的健康数据有什么关联"))
        XCTAssertFalse(PersonalHealthInsightLoader.matches("How many steps today?"))
    }

    func testWellnessPlanRequiresExplicitValidActivation() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-12T18:00:00Z"))
        let goal = WellnessGoal(
            metricKind: .sleepDurationHours,
            direction: .consistency,
            targetValue: nil,
            targetUnit: "hours",
            reviewDate: date.addingTimeInterval(14 * 86_400)
        )
        let action = WellnessAction(
            title: "Keep a regular wind-down time",
            detail: "Choose a realistic 20-minute wind-down window.",
            category: .sleepRoutine,
            daysPerWeek: 5,
            estimatedMinutes: 20
        )
        let draft = WellnessPlan(
            title: "Sleep consistency",
            summary: "A user-controlled wellness plan.",
            origin: .assistantDraft,
            goals: [goal],
            actions: [action],
            createdAt: date,
            updatedAt: date
        )

        let active = try WellnessPlanLifecycle.transition(draft, to: .active, at: date)
        let paused = try WellnessPlanLifecycle.transition(active, to: .paused, at: date)

        XCTAssertEqual(active.status, .active)
        XCTAssertEqual(active.activatedAt, date)
        XCTAssertEqual(paused.status, .paused)
        XCTAssertThrowsError(try WellnessPlanLifecycle.transition(paused, to: .completed))
    }

    func testEmptyWellnessPlanCannotActivate() {
        let plan = WellnessPlan(
            title: "Empty",
            summary: "No actions yet",
            origin: .userCreated,
            goals: [],
            actions: []
        )

        XCTAssertThrowsError(try WellnessPlanLifecycle.transition(plan, to: .active)) { error in
            XCTAssertEqual(error as? WellnessPlanTransitionError, .emptyPlan)
        }
    }

    func testWellnessDraftUsesPersonalBaselineAndRequiresConfirmation() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-12T18:00:00Z"))
        let report = PersonalHealthInsightReport(
            windowDays: 30,
            generatedAt: date,
            coverage: [],
            deviations: [PersonalMetricDeviation(
                metricKind: .sleepDurationHours,
                currentMedian: 6.5,
                baselineMedian: 7.5,
                robustDistance: -3,
                direction: .lower,
                baselineObservedDays: 20,
                currentObservedDays: 7
            )],
            relationships: []
        )

        let draft = WellnessPlanDraftBuilder.build(from: report, now: date)

        XCTAssertEqual(draft.plan.status, .draft)
        XCTAssertEqual(draft.plan.origin, .assistantDraft)
        XCTAssertEqual(draft.plan.goals.first?.targetValue, 6.5)
        XCTAssertTrue(draft.rationale.first?.contains("your own earlier baseline") == true)
        XCTAssertTrue(draft.limitations.contains { $0.contains("until you confirm") })
    }

    func testWellnessDraftAvoidsMetricTargetsWhenBaselineIsInsufficient() {
        let report = PersonalHealthInsightReport(
            windowDays: 30,
            generatedAt: .now,
            coverage: [],
            deviations: [],
            relationships: []
        )

        let draft = WellnessPlanDraftBuilder.build(from: report)

        XCTAssertTrue(draft.plan.goals.isEmpty)
        XCTAssertEqual(draft.plan.actions.first?.category, .checkIn)
        XCTAssertTrue(draft.plan.actions.first?.isOptional == true)
    }

    func testOnlyActiveWellnessPlansProduceDailyActions() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-12T18:00:00Z"))
        let goal = WellnessGoal(
            metricKind: .steps,
            direction: .maintain,
            targetValue: 6_000,
            targetUnit: "steps",
            reviewDate: date
        )
        let action = WellnessAction(
            title: "Movement break",
            detail: "A comfortable activity",
            category: .movement,
            daysPerWeek: 7,
            estimatedMinutes: 10
        )
        let draft = WellnessPlan(
            title: "Plan",
            summary: "Draft",
            origin: .userCreated,
            goals: [goal],
            actions: [action]
        )
        let active = try WellnessPlanLifecycle.transition(draft, to: .active, at: date)

        XCTAssertTrue(WellnessDailySchedule.actions(for: draft, on: date).isEmpty)
        XCTAssertEqual(WellnessDailySchedule.actions(for: active, on: date), [action])
    }

    func testWeeklyReviewKeepsMissingRecordsSeparateFromSkipped() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let end = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-08T12:00:00Z"))
        let action = WellnessAction(
            title: "Daily check-in",
            detail: "Brief reflection",
            category: .checkIn,
            daysPerWeek: 7,
            estimatedMinutes: 2
        )
        let goal = WellnessGoal(
            metricKind: .sleepDurationHours,
            direction: .consistency,
            targetValue: nil,
            targetUnit: "hours",
            reviewDate: end
        )
        let draft = WellnessPlan(
            title: "Plan",
            summary: "Summary",
            origin: .userCreated,
            goals: [goal],
            actions: [action]
        )
        let plan = try WellnessPlanLifecycle.transition(draft, to: .active, at: end)
        let records = [
            WellnessActionRecord(
                id: UUID(),
                planID: plan.id,
                actionID: action.id,
                day: end,
                outcome: .skipped,
                recordedAt: end
            )
        ]

        let review = WellnessWeeklyReviewBuilder.build(
            plan: plan,
            records: records,
            endingAt: end,
            calendar: calendar
        )

        XCTAssertEqual(review.scheduledCount, 7)
        XCTAssertEqual(review.skippedCount, 1)
        XCTAssertEqual(review.unrecordedCount, 6)
        XCTAssertEqual(review.adjustment, .considerSimplifying)
    }

    func testWellnessDeviceTrustPolicyFailsClosedForUnknownIdentity() throws {
        let identity = WellnessDeviceIdentity(
            deviceID: UUID(),
            productIdentifier: "unknown-device",
            firmwareVersion: "1.0.0",
            protocolVersion: 1,
            reportedCapabilities: [.relaxationSession, .immediateStop],
            manufacturerSignatureValidated: true
        )
        let policy = WellnessDeviceTrustPolicy(
            supportedProductIdentifiers: ["s2y-wellness-reference"],
            supportedProtocolVersions: 1 ... 1
        )

        XCTAssertThrowsError(try policy.verify(identity)) { error in
            XCTAssertEqual(error as? WellnessDeviceTrustFailure, .unsupportedProduct)
        }
    }

    func testWellnessDeviceTrustPolicyRequiresImmediateStopCapability() throws {
        let identity = WellnessDeviceIdentity(
            deviceID: UUID(),
            productIdentifier: "s2y-wellness-reference",
            firmwareVersion: "1.0.0",
            protocolVersion: 1,
            reportedCapabilities: [.relaxationSession],
            manufacturerSignatureValidated: true
        )
        let policy = WellnessDeviceTrustPolicy(
            supportedProductIdentifiers: ["s2y-wellness-reference"],
            supportedProtocolVersions: 1 ... 1
        )

        XCTAssertThrowsError(try policy.verify(identity)) { error in
            XCTAssertEqual(error as? WellnessDeviceTrustFailure, .missingImmediateStop)
        }
    }

    func testWellnessDeviceTrustPolicyNarrowsReportedCapabilities() throws {
        let identity = WellnessDeviceIdentity(
            deviceID: UUID(),
            productIdentifier: "s2y-wellness-reference",
            firmwareVersion: "1.0.0",
            protocolVersion: 1,
            reportedCapabilities: [.relaxationSession, .levelAdjustment, .immediateStop],
            manufacturerSignatureValidated: true
        )
        let policy = WellnessDeviceTrustPolicy(
            supportedProductIdentifiers: ["s2y-wellness-reference"],
            supportedProtocolVersions: 1 ... 1,
            allowedCapabilities: [.relaxationSession, .immediateStop]
        )

        let verified = try policy.verify(identity)
        XCTAssertEqual(verified.allowedCapabilities, [.relaxationSession, .immediateStop])
    }

    func testWellnessSessionPolicyRejectsAssistantDraftOutsideLocalLimits() throws {
        let deviceID = UUID()
        let device = verifiedWellnessDevice(id: deviceID)
        let request = WellnessSessionRequest(
            deviceID: deviceID,
            purpose: .relaxation,
            durationMinutes: 45,
            comfortLevel: 2,
            origin: .assistantDraft
        )

        XCTAssertThrowsError(
            try WellnessSessionSafetyPolicy().validate(request, for: device, lastSessionEndedAt: nil)
        ) { error in
            XCTAssertEqual(error as? WellnessSessionValidationFailure, .durationOutOfRange)
        }
    }

    func testWellnessSessionPolicyEnforcesCooldown() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-12T20:00:00Z"))
        let deviceID = UUID()
        let device = verifiedWellnessDevice(id: deviceID)
        let request = WellnessSessionRequest(
            deviceID: deviceID,
            purpose: .windDown,
            durationMinutes: 10,
            comfortLevel: 1,
            origin: .userCreated
        )
        let lastEnd = now.addingTimeInterval(-30 * 60)

        XCTAssertThrowsError(
            try WellnessSessionSafetyPolicy().validate(
                request,
                for: device,
                lastSessionEndedAt: lastEnd,
                now: now
            )
        ) { error in
            XCTAssertEqual(
                error as? WellnessSessionValidationFailure,
                .cooldownActive(until: lastEnd.addingTimeInterval(60 * 60))
            )
        }
    }

    func testWellnessSessionPolicyProducesShortLivedValidation() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-12T20:00:00Z"))
        let deviceID = UUID()
        let device = verifiedWellnessDevice(id: deviceID)
        let request = WellnessSessionRequest(
            deviceID: deviceID,
            purpose: .mindfulBreak,
            durationMinutes: 10,
            comfortLevel: 2,
            origin: .assistantDraft
        )

        let validated = try WellnessSessionSafetyPolicy().validate(
            request,
            for: device,
            lastSessionEndedAt: now.addingTimeInterval(-2 * 60 * 60),
            now: now
        )
        XCTAssertEqual(validated.expiresAt, now.addingTimeInterval(5 * 60))
        XCTAssertEqual(validated.request.origin, .assistantDraft)
    }

    func testWellnessSessionCannotStartWithoutMatchingUserConfirmation() throws {
        let validated = try validatedWellnessSession()
        var controller = WellnessSessionController()
        let confirmation = controller.prepare(validated, now: validated.validatedAt)

        XCTAssertThrowsError(
            try controller.confirm(confirmationID: UUID(), now: validated.validatedAt)
        ) { error in
            XCTAssertEqual(error as? WellnessSessionControlFailure, .confirmationMismatch)
        }
        XCTAssertEqual(controller.state, .awaitingConfirmation(confirmation))
    }

    func testWellnessSessionConfirmationExpires() throws {
        let validated = try validatedWellnessSession()
        var controller = WellnessSessionController()
        let confirmation = controller.prepare(validated, now: validated.validatedAt)

        XCTAssertThrowsError(
            try controller.confirm(
                confirmationID: confirmation.id,
                now: validated.expiresAt.addingTimeInterval(1)
            )
        ) { error in
            XCTAssertEqual(error as? WellnessSessionControlFailure, .confirmationExpired)
        }
    }

    func testActiveWellnessSessionCanAlwaysStopLocally() throws {
        let validated = try validatedWellnessSession()
        var controller = WellnessSessionController()
        let confirmation = controller.prepare(validated, now: validated.validatedAt)
        _ = try controller.confirm(
            confirmationID: confirmation.id,
            now: validated.validatedAt.addingTimeInterval(1)
        )
        let stopTime = validated.validatedAt.addingTimeInterval(30)

        let stopped = try controller.stopImmediately(reason: .safetyStop, now: stopTime)

        XCTAssertEqual(stopped.reason, .safetyStop)
        XCTAssertEqual(stopped.stoppedAt, stopTime)
        XCTAssertEqual(controller.state, .stopped(stopped))
    }

    func testWellnessSessionAuditRecordsUserVisibleFieldsWithoutHardwarePayload() throws {
        let validated = try validatedWellnessSession()
        let active = ActiveWellnessSession(
            session: validated,
            confirmedAt: validated.validatedAt,
            scheduledEndAt: validated.validatedAt.addingTimeInterval(600)
        )
        var log = WellnessSessionAuditLog()
        log.begin(active)
        let stopped = StoppedWellnessSession(
            request: validated.request,
            stoppedAt: validated.validatedAt.addingTimeInterval(120),
            reason: .userStopped
        )
        log.finish(stopped)

        let record = try XCTUnwrap(log.records.first)
        XCTAssertEqual(record.stopReason, .userStopped)
        XCTAssertEqual(record.endedAt, stopped.stoppedAt)

        let json = String(decoding: try encoder.encode(log), as: UTF8.self)
        XCTAssertFalse(json.localizedCaseInsensitiveContains("amplitude"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("frequency"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("treatment"))
    }

    func testWellnessSessionAuditLogCapsLocalHistory() throws {
        let validated = try validatedWellnessSession()
        let active = ActiveWellnessSession(
            session: validated,
            confirmedAt: validated.validatedAt,
            scheduledEndAt: validated.validatedAt.addingTimeInterval(600)
        )
        var log = WellnessSessionAuditLog(maximumRecordCount: 2)

        log.begin(active)
        log.begin(active)
        log.begin(active)

        XCTAssertEqual(log.records.count, 2)
    }

    func testHealthSafetyTriageEscalatesEmergencySignalsWithoutDiagnosis() throws {
        let escalation = try XCTUnwrap(
            HealthSafetyTriage.evaluate("I have sudden chest pain and can't breathe")
        )

        XCTAssertEqual(escalation.level, .emergency)
        XCTAssertEqual(escalation.signalCategories, ["breathing", "chest-pain"])
        XCTAssertTrue(escalation.userMessage.contains("911"))
        XCTAssertFalse(escalation.userMessage.localizedCaseInsensitiveContains("diagnosis"))
    }

    func testHealthSafetyTriageRecognizesChineseCrisisLanguage() throws {
        let escalation = try XCTUnwrap(HealthSafetyTriage.evaluate("我不想活了，想伤害自己"))

        XCTAssertEqual(escalation.level, .selfHarmCrisis)
        XCTAssertEqual(escalation.signalCategories, ["self-harm"])
        XCTAssertTrue(escalation.userMessage.contains("988"))
    }

    func testHealthSafetyTriageDoesNotEscalateNegatedOrRoutineQueries() {
        XCTAssertNil(HealthSafetyTriage.evaluate("I do not have chest pain; how was my sleep?"))
        XCTAssertNil(HealthSafetyTriage.evaluate("How has my resting heart rate changed this week?"))
        XCTAssertNil(HealthSafetyTriage.evaluate("我没有胸痛，只想查看步数趋势"))
    }

    func testSafetyEscalationMetadataDoesNotClaimAIOrHealthAnalysis() {
        let metadata = ProcessingMetadata(safetyEscalationLevel: .emergency)

        XCTAssertEqual(metadata.safetyEscalationLevel, .emergency)
        XCTAssertNil(metadata.llmSource)
        XCTAssertFalse(metadata.healthAnalysisUsed)
        XCTAssertFalse(metadata.contextUsed)
    }

    func testHealthCommunicationLayersKeepObservationAndGuidanceDistinct() {
        let observation = ChatMessage(
            role: .assistant,
            content: "Seven observed days",
            communicationKind: .healthObservation
        )
        let generalGuidance = ChatMessage(role: .assistant, content: "Consider a consistent bedtime")
        let userMessage = ChatMessage(role: .user, content: "How was my sleep?")

        XCTAssertEqual(observation.communicationKind, .healthObservation)
        XCTAssertEqual(generalGuidance.communicationKind, .wellnessGuidance)
        XCTAssertNil(userMessage.communicationKind)
        XCTAssertTrue(HealthCommunicationKind.wellnessGuidance.disclosure.contains("not diagnosis"))
    }

    func testHealthSafetyAuditExcludesRawMessageAndProviderContact() throws {
        let escalation = try XCTUnwrap(HealthSafetyTriage.evaluate("I have chest pain"))
        let event = HealthSafetyEvent(escalation: escalation)
        var log = HealthSafetyEventLog(maximumEventCount: 2)

        log.record(event)
        log.record(event)
        log.record(event)

        XCTAssertEqual(log.events.count, 2)
        XCTAssertFalse(event.aiProviderContacted)
        let json = String(decoding: try encoder.encode(log), as: UTF8.self)
        XCTAssertFalse(json.localizedCaseInsensitiveContains("I have chest pain"))
        XCTAssertTrue(json.contains("chest-pain"))
    }

    func testHealthSafetyAuditCanBeClearedLocally() throws {
        let escalation = try XCTUnwrap(HealthSafetyTriage.evaluate("I have chest pain"))
        var log = HealthSafetyEventLog()
        log.record(HealthSafetyEvent(escalation: escalation))

        log.clear()

        XCTAssertTrue(log.events.isEmpty)
    }

    func testHealthSharingConsentDefaultsToDenyForEveryScope() {
        let authorization = HealthSharingAuthorization()

        for scope in HealthSharingScope.allCases {
            XCTAssertFalse(HealthSharingConsentPolicy.permits(scope, authorization: authorization))
        }
    }

    func testHealthSharingScopesAreGrantedIndependently() {
        let authorization = HealthSharingAuthorization(grantedScopes: [.omerChatText])

        XCTAssertTrue(HealthSharingConsentPolicy.permits(.omerChatText, authorization: authorization))
        XCTAssertFalse(HealthSharingConsentPolicy.permits(.relevantHealthSummary, authorization: authorization))
        XCTAssertFalse(HealthSharingConsentPolicy.permits(.onDeviceConversationSync, authorization: authorization))
        XCTAssertFalse(HealthSharingConsentPolicy.permits(.clinicalRecordSummary, authorization: authorization))
        XCTAssertFalse(HealthSharingConsentPolicy.permits(.wellbeingCheckInCloudBackup, authorization: authorization))
        XCTAssertFalse(HealthSharingConsentPolicy.permits(.wellbeingCheckInSummary, authorization: authorization))
        XCTAssertEqual(
            HealthSharingConsentPolicy.decision(
                requestedScopes: [.omerChatText, .relevantHealthSummary],
                authorization: authorization
            ),
            .denied(missingScopes: [.relevantHealthSummary])
        )
    }

    func testHealthSharingConsentReceiptSupportsImmediateRevocation() {
        var ledger = HealthSharingConsentLedger()
        ledger.apply(.granted, scopes: [.omerChatText, .relevantHealthSummary])
        ledger.apply(.revoked, scopes: [.relevantHealthSummary])

        let authorization = ledger.authorization()
        XCTAssertTrue(authorization.grantedScopes.contains(.omerChatText))
        XCTAssertFalse(authorization.grantedScopes.contains(.relevantHealthSummary))
        XCTAssertEqual(ledger.receipts.first?.change, .revoked)
    }

    func testHealthSharingConsentDoesNotCarryAcrossPolicyVersions() {
        var ledger = HealthSharingConsentLedger()
        ledger.apply(
            .granted,
            scopes: [.omerChatText],
            policyVersion: "previous-version"
        )

        XCTAssertTrue(ledger.authorization().grantedScopes.isEmpty)
    }

    func testHealthSharingConsentLedgerBoundsReceiptHistory() {
        var ledger = HealthSharingConsentLedger(maximumReceiptCount: 2)
        ledger.apply(.granted, scopes: [.omerChatText])
        ledger.apply(.granted, scopes: [.relevantHealthSummary])
        ledger.apply(.revoked, scopes: [.omerChatText])

        XCTAssertEqual(ledger.receipts.count, 2)
    }

    func testHealthSharingConsentRequirementReportsOnlyMissingScopes() throws {
        let authorization = HealthSharingAuthorization(grantedScopes: [.omerChatText])

        XCTAssertNoThrow(
            try HealthSharingConsentPolicy.require([.omerChatText], authorization: authorization)
        )
        XCTAssertThrowsError(
            try HealthSharingConsentPolicy.require(
                [.omerChatText, .relevantHealthSummary],
                authorization: authorization
            )
        ) { error in
            XCTAssertEqual(
                error as? HealthSharingConsentFailure,
                HealthSharingConsentFailure(missingScopes: [.relevantHealthSummary])
            )
        }
    }

    func testClinicalRecordContextIsBoundedAndExcludesIdentifiers() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-12T18:00:00Z"))
        let records = (0..<3).map { offset in
            ClinicalRecordSummary(
                id: UUID(),
                category: .labResults,
                displayName: "Example result \(offset)\nwith whitespace",
                recordedAt: now.addingTimeInterval(TimeInterval(-offset * 60)),
                sourceName: "Example Provider",
                hasLinkedFHIRResource: true
            )
        }
        let index = ClinicalRecordIndex(
            records: records,
            selectedCategories: [.labResults],
            refreshedAt: now
        )

        let context = try XCTUnwrap(ClinicalRecordContextBuilder.build(
            from: index,
            maximumRecordCount: 2,
            maximumCharacterCount: 500
        ))

        XCTAssertEqual(context.components(separatedBy: "\n").count, 2)
        XCTAssertTrue(context.contains("Example result 0 with whitespace"))
        XCTAssertTrue(context.contains("source=Example Provider"))
        XCTAssertFalse(context.contains(records[0].id.uuidString))
        XCTAssertFalse(context.localizedCaseInsensitiveContains("fhir"))
        XCTAssertLessThanOrEqual(context.count, 500)
    }

    func testWellbeingCheckInBuildsMinimizedSnapshotWithoutFreeTextNotes() throws {
        let response = Data(#"""
        {
          "item": [
            {"linkId":"overall-wellness","answer":[{"valueCoding":{"code":"good"}}]},
            {"linkId":"sleep-hours","answer":[{"valueDecimal":7.5}]},
            {"linkId":"symptoms","answer":[
              {"valueCoding":{"code":"headache"}},
              {"valueCoding":{"code":"fatigue"}}
            ]},
            {"linkId":"notes","answer":[{"valueString":"Private free text details"}]},
            {"linkId":"goals-today","answer":[{"valueCoding":{"code":"better-sleep"}}]}
          ]
        }
        """#.utf8)

        let snapshot = try WellbeingCheckInSnapshotBuilder.build(
            responseData: response,
            questionnaireIdentifier: "DailyHealth"
        )

        XCTAssertEqual(snapshot.overallWellbeing, "good")
        XCTAssertEqual(snapshot.sleepHours, 7.5)
        XCTAssertEqual(snapshot.reportedSymptoms, ["headache", "fatigue"])
        XCTAssertEqual(snapshot.goalFocus, "better-sleep")
        let encoded = String(decoding: try encoder.encode(snapshot), as: UTF8.self)
        XCTAssertFalse(encoded.contains("Private free text details"))
        XCTAssertFalse(encoded.contains("notes"))
    }

    func testWellbeingCheckInBoundsInvalidValuesAndSymptomCount() {
        let snapshot = WellbeingCheckInSnapshot(
            questionnaireIdentifier: "DailyHealth",
            sleepHours: 25,
            reportedSymptoms: (0..<12).map { "symptom-\($0)" }
        )

        XCTAssertNil(snapshot.sleepHours)
        XCTAssertEqual(snapshot.reportedSymptoms.count, 8)
    }

    @MainActor
    func testWellbeingCheckInStorePersistsBoundsAndClearsSnapshots() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("snapshots.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date()
        let store = WellbeingCheckInStore(fileURL: fileURL, maximumSnapshotCount: 2)

        for offset in 0..<3 {
            try store.save(WellbeingCheckInSnapshot(
                recordedAt: now.addingTimeInterval(TimeInterval(offset)),
                questionnaireIdentifier: "DailyHealth",
                overallWellbeing: "good"
            ))
        }

        XCTAssertEqual(store.snapshots.count, 2)
        XCTAssertEqual(store.snapshots.first?.recordedAt, now.addingTimeInterval(2))
        XCTAssertEqual(
            WellbeingCheckInStore(fileURL: fileURL, maximumSnapshotCount: 2).snapshots,
            store.snapshots
        )

        try store.clear()

        XCTAssertTrue(store.snapshots.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testWellbeingCheckInOutboundPurposesAreIndependent() {
        let authorization = HealthSharingAuthorization(grantedScopes: [.wellbeingCheckInCloudBackup])

        XCTAssertTrue(
            HealthSharingConsentPolicy.permits(.wellbeingCheckInCloudBackup, authorization: authorization)
        )
        XCTAssertFalse(HealthSharingConsentPolicy.permits(.wellbeingCheckInSummary, authorization: authorization))
        XCTAssertFalse(HealthSharingConsentPolicy.permits(.omerChatText, authorization: authorization))
    }

    func testWellbeingCheckInContextIsBoundedAndExcludesLocalIdentifiers() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-12T18:00:00Z"))
        let snapshots = (0..<4).map { offset in
            WellbeingCheckInSnapshot(
                id: UUID(),
                recordedAt: now.addingTimeInterval(TimeInterval(-offset * 24 * 60 * 60)),
                questionnaireIdentifier: "PrivateQuestionnaireIdentifier",
                overallWellbeing: "good",
                sleepQuality: "fair",
                reportedSymptoms: ["fatigue"]
            )
        }

        let context = try XCTUnwrap(WellbeingCheckInContextBuilder.build(
            from: snapshots,
            maximumSnapshotCount: 2,
            maximumCharacterCount: 500
        ))

        XCTAssertEqual(context.components(separatedBy: "\n").count, 2)
        XCTAssertTrue(context.contains("overall=good"))
        XCTAssertTrue(context.contains("symptoms=fatigue"))
        XCTAssertFalse(context.contains("PrivateQuestionnaireIdentifier"))
        XCTAssertFalse(context.contains(snapshots[0].id.uuidString))
        XCTAssertLessThanOrEqual(context.count, 500)
    }

    func testLocalHealthDataInventoryIncludesEveryCategoryAndBoundsCounts() {
        let snapshot = LocalHealthDataInventorySnapshot(counts: [
            .wellbeingCheckIns: 3,
            .safetyActivity: -1
        ])

        XCTAssertEqual(snapshot.items.count, LocalHealthDataCategory.allCases.count)
        XCTAssertEqual(Set(snapshot.items.map(\.category)), Set(LocalHealthDataCategory.allCases))
        XCTAssertEqual(snapshot.items.first { $0.category == .wellbeingCheckIns }?.itemCount, 3)
        XCTAssertEqual(snapshot.items.first { $0.category == .safetyActivity }?.itemCount, 0)
        XCTAssertTrue(snapshot.items.allSatisfy { !$0.storageDescription.isEmpty })
    }

    func testLocalHealthDataExportIsVersionedAndExcludesRawFHIRFields() throws {
        let generatedAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-12T18:00:00Z"))
        let package = LocalHealthDataExportPackage(
            generatedAt: generatedAt,
            inventory: LocalHealthDataInventorySnapshot(generatedAt: generatedAt, counts: [:]),
            localChatCache: OmerChatCacheSnapshot(chats: [], details: [])
        )

        let data = try LocalHealthDataExportService.encodedData(for: package)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(json.contains(#""formatVersion" : 1"#))
        XCTAssertTrue(json.contains(#""generatedAt""#))
        XCTAssertTrue(json.contains(#""localChatCache""#))
        XCTAssertFalse(json.contains("fhirResourceIdentifier"))
        XCTAssertFalse(json.contains("resourceType"))
    }

    func testAppleOnDeviceAvailabilityProvidesExplicitRecoveryWithoutAutomaticFallback() {
        let states: [AppleFoundationModelAvailability] = [
            .unavailable(.requiresNewerOS),
            .unavailable(.deviceNotEligible),
            .unavailable(.appleIntelligenceNotEnabled),
            .unavailable(.modelNotReady),
            .unavailable(.simulatorUnsupported),
            .unavailable(.frameworkUnavailable)
        ]

        for state in states {
            XCTAssertFalse(state.statusTitle.isEmpty)
            XCTAssertFalse(state.recoveryGuidance.isEmpty)
            XCTAssertFalse(state.recoveryGuidance.contains("Using Omer instead"))
        }
        XCTAssertEqual(AppleFoundationModelAvailability.available.statusTitle, "Ready")
        XCTAssertTrue(
            AppleFoundationModelAvailability.unavailable(.appleIntelligenceNotEnabled)
                .recoveryGuidance.contains("iPhone Settings")
        )
        XCTAssertTrue(
            AppleFoundationModelAvailability.unavailable(.modelNotReady)
                .recoveryGuidance.contains("power and Wi-Fi")
        )
    }

    @MainActor
    func testClearingSharingReceiptsAlsoReturnsEveryScopeToDefaultDeny() {
        let suiteName = "HealthSharingConsentStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = HealthSharingConsentStore(defaults: defaults)
        store.set(.omerChatText, granted: true)
        store.set(.wellbeingCheckInCloudBackup, granted: true)

        store.clear()

        XCTAssertTrue(store.ledger.receipts.isEmpty)
        XCTAssertTrue(store.authorization.grantedScopes.isEmpty)
        XCTAssertNil(defaults.data(forKey: "healthSharingConsent.v1"))
    }

    func testRevokingOnDeviceSyncDoesNotRevokeOmerQuestionConsent() {
        var ledger = HealthSharingConsentLedger()
        ledger.apply(.granted, scopes: [.omerChatText, .onDeviceConversationSync])
        ledger.apply(.revoked, scopes: [.onDeviceConversationSync])

        let authorization = ledger.authorization()
        XCTAssertTrue(HealthSharingConsentPolicy.permits(.omerChatText, authorization: authorization))
        XCTAssertFalse(
            HealthSharingConsentPolicy.permits(.onDeviceConversationSync, authorization: authorization)
        )
    }

    private func validatedWellnessSession() throws -> ValidatedWellnessSession {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-12T20:00:00Z"))
        let deviceID = UUID()
        let request = WellnessSessionRequest(
            deviceID: deviceID,
            purpose: .relaxation,
            durationMinutes: 10,
            comfortLevel: 1,
            origin: .assistantDraft
        )
        return try WellnessSessionSafetyPolicy().validate(
            request,
            for: verifiedWellnessDevice(id: deviceID),
            lastSessionEndedAt: nil,
            now: now
        )
    }

    private func verifiedWellnessDevice(id: UUID) -> VerifiedWellnessDevice {
        let identity = WellnessDeviceIdentity(
            deviceID: id,
            productIdentifier: "s2y-wellness-reference",
            firmwareVersion: "1.0.0",
            protocolVersion: 1,
            reportedCapabilities: [.relaxationSession, .sessionTimer, .immediateStop],
            manufacturerSignatureValidated: true
        )
        return VerifiedWellnessDevice(
            identity: identity,
            allowedCapabilities: identity.reportedCapabilities
        )
    }
}
