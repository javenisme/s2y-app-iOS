//
// This source file is part of the S2Y application project
//
// SPDX-FileCopyrightText: 2026 S2Y Health
//
// SPDX-License-Identifier: MIT

import Foundation
@testable import S2Y
import XCTest

final class CriticalLocalizationTests: XCTestCase {
    func testCriticalChineseNavigationAndChatLabels() throws {
        let translations = try chineseTranslations()

        XCTAssertEqual(translations["Health Assistant"], "健康助手")
        XCTAssertEqual(translations["Settings"], "设置")
        XCTAssertEqual(translations["New chat"], "新对话")
        XCTAssertEqual(translations["Send Message"], "发送消息")
        XCTAssertEqual(translations["Stop Response"], "停止回复")
        XCTAssertEqual(translations["On-device"], "设备端")
        XCTAssertEqual(translations["Omer Online"], "Omer 在线")
        XCTAssertEqual(translations["S2Y Health Assistant"], "S2Y 健康助手")
        XCTAssertEqual(translations["WELCOME_SUBTITLE"], "在你的控制下理解健康数据，并采取适合自己的健康管理行动。")
    }

    func testCriticalChineseSummaryAndPrivacyLabels() throws {
        let translations = try chineseTranslations()

        XCTAssertEqual(translations["Privacy"], "隐私")
        XCTAssertEqual(translations["Health Summary PDF"], "健康摘要 PDF")
        XCTAssertEqual(translations["Last 30 days"], "最近 30 天")
        XCTAssertEqual(translations["Prepare PDF Preview"], "准备 PDF 预览")
        XCTAssertEqual(translations["Share"], "分享")
        XCTAssertEqual(translations["Data Controls"], "数据控制")
    }

    private func chineseTranslations() throws -> [String: String] {
        let bundles = Bundle.allBundles + Bundle.allFrameworks
        let url = try XCTUnwrap(
            bundles.lazy.compactMap {
                $0.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: "zh-Hans")
            }.first
        )
        let data = try Data(contentsOf: url)
        let propertyList = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(propertyList as? [String: String])
    }
}
