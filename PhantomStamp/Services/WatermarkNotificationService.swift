//
//  WatermarkOperationNotificationService.swift
//  PhantomStamp
//
//  Presents system local notifications after watermark embed/extract completes.
//  Single-image APIs: one notification describing that image’s outcome.
//  Multi-image batch APIs: one summary notification after the whole batch (success / failure counts).
//

import Foundation
import UserNotifications

@MainActor
enum WatermarkOperationNotificationService {

    private static let center = UNUserNotificationCenter.current()

    /// Requests permission the first time it is needed; no-op if already decided.
    private static func ensureAuthorizedForDelivery() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                return false
            }
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    private static func schedule(title: String, body: String, delay: TimeInterval? = nil) async {
        guard await ensureAuthorizedForDelivery() else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = delay.map {
            UNTimeIntervalNotificationTrigger(timeInterval: max(1, $0), repeats: false)
        }
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }

    private static func trimBody(_ text: String, maxScalars: Int = 220) -> String {
        guard text.count > maxScalars else { return text }
        return String(text.prefix(maxScalars)) + "…"
    }

    // MARK: - Single image

    static func notifySingleEmbedFinished(success: Bool, error: Error?) async {
        if success {
            await schedule(
                title: AppConstants.Copy.WatermarkPush.embedSingleSuccessTitle,
                body: AppConstants.Copy.WatermarkPush.embedSingleSuccessBody,
                delay: 3
            )
        } else {
            let body = error?.localizedDescription ?? AppConstants.Copy.WatermarkPush.genericErrorBody
            await schedule(
                title: AppConstants.Copy.WatermarkPush.embedSingleFailureTitle,
                body: trimBody(body),
                delay: 1
            )
        }
    }

    static func notifySingleExtractFinished(success: Bool, extractedText: String?, error: Error?) async {
        if success, let text = extractedText {
            let body = AppConstants.Copy.WatermarkPush.extractSingleSuccessBodyPrefix + trimBody(text)
            await schedule(
                title: AppConstants.Copy.WatermarkPush.extractSingleSuccessTitle,
                body: body,
                delay: 1
            )
        } else {
            let body = error?.localizedDescription ?? AppConstants.Copy.WatermarkPush.genericErrorBody
            await schedule(
                title: AppConstants.Copy.WatermarkPush.extractSingleFailureTitle,
                body: trimBody(body),
                delay: 1
            )
        }
    }

    // MARK: - Batch (one notification after all work)

    static func notifyBatchEmbedFinished(succeeded: Int, failed: Int) async {
        let title = AppConstants.Copy.WatermarkPush.batchEmbedDoneTitle
        let body = String(format: AppConstants.Copy.WatermarkPush.batchEmbedDoneBodyFormat, succeeded, failed)
        await schedule(title: title, body: body)
    }

    static func notifyBatchExtractFinished(succeeded: Int, failed: Int) async {
        let title = AppConstants.Copy.WatermarkPush.batchExtractDoneTitle
        let body = String(format: AppConstants.Copy.WatermarkPush.batchExtractDoneBodyFormat, succeeded, failed)
        await schedule(title: title, body: body)
    }


    // MARK: - Robustness / limit tests (one summary per run)
    static func notifyRobustnessTestFinished(testName: String, success: Bool, summary: String) async {
        let status = success
            ? AppConstants.Copy.WatermarkPush.robustnessTestPassStatus
            : AppConstants.Copy.WatermarkPush.robustnessTestFailStatus
        let title = String(format: AppConstants.Copy.WatermarkPush.robustnessTestDoneTitleFormat, testName, status)
        await schedule(title: title, body: trimBody(summary))
    }
}
