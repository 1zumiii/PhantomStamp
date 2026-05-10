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

    private static func scheduleImmediate(title: String, body: String) async {
        guard await ensureAuthorizedForDelivery() else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await center.add(request)
    }

    private static func trimBody(_ text: String, maxScalars: Int = 220) -> String {
        guard text.count > maxScalars else { return text }
        return String(text.prefix(maxScalars)) + "…"
    }

    // MARK: - Single image

    static func notifySingleEmbedFinished(success: Bool, error: Error?) async {
        if success {
            await scheduleImmediate(
                title: AppConstants.Copy.WatermarkPush.embedSingleSuccessTitle,
                body: AppConstants.Copy.WatermarkPush.embedSingleSuccessBody
            )
        } else {
            let body = error?.localizedDescription ?? AppConstants.Copy.WatermarkPush.genericErrorBody
            await scheduleImmediate(
                title: AppConstants.Copy.WatermarkPush.embedSingleFailureTitle,
                body: trimBody(body)
            )
        }
    }

    static func notifySingleExtractFinished(success: Bool, extractedText: String?, error: Error?) async {
        try? await Task.sleep(nanoseconds: 8_000_000_000)
        if success, let text = extractedText {
            let body = AppConstants.Copy.WatermarkPush.extractSingleSuccessBodyPrefix + trimBody(text)
            await scheduleImmediate(
                title: AppConstants.Copy.WatermarkPush.extractSingleSuccessTitle,
                body: body
            )
        } else {
            let body = error?.localizedDescription ?? AppConstants.Copy.WatermarkPush.genericErrorBody
            await scheduleImmediate(
                title: AppConstants.Copy.WatermarkPush.extractSingleFailureTitle,
                body: trimBody(body)
            )
        }
    }

    // MARK: - Batch (one notification after all work)

    static func notifyBatchEmbedFinished(succeeded: Int, failed: Int) async {
        let title = AppConstants.Copy.WatermarkPush.batchEmbedDoneTitle
        let body = String(format: AppConstants.Copy.WatermarkPush.batchEmbedDoneBodyFormat, succeeded, failed)
        await scheduleImmediate(title: title, body: body)
    }

    static func notifyBatchExtractFinished(succeeded: Int, failed: Int) async {
        let title = AppConstants.Copy.WatermarkPush.batchExtractDoneTitle
        let body = String(format: AppConstants.Copy.WatermarkPush.batchExtractDoneBodyFormat, succeeded, failed)
        await scheduleImmediate(title: title, body: body)
    }
}
