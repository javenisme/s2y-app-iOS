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

    func testAccountCopyUsesS2YBrandAndExplainsItsPurpose() throws {
        let chinese = try chineseTranslations()
        let englishSubtitle = String(
            localized: "ACCOUNT_SUBTITLE",
            bundle: .main,
            locale: Locale(identifier: "en")
        )
        let englishSetupDescription = String(
            localized: "ACCOUNT_SETUP_DESCRIPTION",
            bundle: .main,
            locale: Locale(identifier: "en")
        )

        XCTAssertEqual(englishSubtitle, "Use your S2Y account for Health Assistant and Omer Online.")
        XCTAssertEqual(
            englishSetupDescription,
            "Sign in to your existing account, or create one if you are new to S2Y."
        )
        XCTAssertFalse(englishSubtitle.localizedCaseInsensitiveContains("template"))
        XCTAssertFalse(englishSubtitle.localizedCaseInsensitiveContains("module"))

        XCTAssertEqual(chinese["Your Account"], "你的账户")
        XCTAssertEqual(chinese["ACCOUNT_SUBTITLE"], "使用你的 S2Y 账户连接健康助手与 Omer 在线服务。")
        XCTAssertEqual(chinese["ACCOUNT_SETUP_DESCRIPTION"], "登录现有账户；如果你是第一次使用 S2Y，也可以创建账户。")
        XCTAssertEqual(chinese["ACCOUNT_SIGNED_IN_DESCRIPTION"], "你已登录下方账户。可以继续使用，或退出登录后切换账户。")
    }

    func testOnboardingExplainsUserChoicesInsteadOfFrameworkModules() throws {
        let chinese = try chineseTranslations()
        let englishWelcome = String(
            localized: "WELCOME_SUBTITLE",
            bundle: .main,
            locale: Locale(identifier: "en")
        )
        let englishPrivacy = String(
            localized: "INTERESTING_MODULES_SUBTITLE",
            bundle: .main,
            locale: Locale(identifier: "en")
        )

        XCTAssertEqual(
            englishWelcome,
            "Understand your health data and choose your own health-management actions."
        )
        XCTAssertEqual(englishPrivacy, "Review how S2Y handles data before choosing permissions.")
        XCTAssertFalse(englishWelcome.localizedCaseInsensitiveContains("framework"))
        XCTAssertFalse(englishPrivacy.localizedCaseInsensitiveContains("module"))

        XCTAssertEqual(chinese["Apple Health"], "Apple 健康")
        XCTAssertEqual(chinese["Choose your AI"], "选择 AI")
        XCTAssertEqual(chinese["You stay in control"], "由你掌控")
        XCTAssertEqual(chinese["Before You Start"], "开始之前")
        XCTAssertEqual(chinese["Health data"], "健康数据")
        XCTAssertEqual(chinese["AI processing"], "AI 处理方式")
        XCTAssertEqual(chinese["Account and sync"], "账户与同步")
        XCTAssertEqual(chinese["Health management"], "健康管理")
    }

    private func chineseTranslations() throws -> [String: String] {
        try translations(localization: "zh-Hans")
    }

    private func translations(localization: String) throws -> [String: String] {
        let bundles = Bundle.allBundles + Bundle.allFrameworks
        let url = try XCTUnwrap(
            bundles.lazy.compactMap {
                $0.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: localization)
            }.first
        )
        let data = try Data(contentsOf: url)
        let propertyList = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(propertyList as? [String: String])
    }
}
