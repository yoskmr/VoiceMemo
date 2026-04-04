import Dependencies
import Domain
import Foundation
import InfraNetwork
import UIKit

// MARK: - MemoConversation Live Dependencies
// TASK-0041: きおくに聞く（AI対話）の Live DI 接続

extension MemoConversationClient: DependencyKey {
    public static let liveValue = MemoConversationClient(
        sendQuestion: { question, contextMemos in
            @Dependency(\.backendProxy) var backendProxy

            // MemoContext → MemoContextDTO に変換
            let dtos = contextMemos.map { memo in
                MemoContextDTO(
                    id: memo.id.uuidString,
                    title: memo.title,
                    text: memo.text,
                    date: memo.date,
                    emotion: memo.emotion,
                    tags: memo.tags
                )
            }

            // Backend Proxy 経由で POST /api/v1/ai/chat を呼び出す
            // トークン未取得時は自動認証してリトライする
            do {
                let dto = try await backendProxy.chatWithMemos(question, dtos)
                return ChatResponse(
                    answer: dto.answer,
                    referencedMemoIDs: dto.referencedMemoIDs
                )
            } catch BackendProxyError.tokenNotFound {
                // 自動認証: デバイス情報を取得して JWT を取得
                let deviceID = await UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
                let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
                let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
                _ = try await backendProxy.authenticate(deviceID, appVersion, osVersion)

                // リトライ
                let dto = try await backendProxy.chatWithMemos(question, dtos)
                return ChatResponse(
                    answer: dto.answer,
                    referencedMemoIDs: dto.referencedMemoIDs
                )
            }
        }
    )
}
