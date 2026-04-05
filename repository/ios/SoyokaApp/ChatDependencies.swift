import Dependencies
import Domain
import Foundation
import InfraLogging
import InfraNetwork
import UIKit

// MARK: - MemoConversation Live Dependencies
// TASK-0041: きおくに聞く（AI対話）の Live DI 接続

extension MemoConversationClient: DependencyKey {
    public static let liveValue = MemoConversationClient(
        sendQuestion: { question, contextMemos in
            @Dependency(\.backendProxy) var backendProxy

            let startTime = CFAbsoluteTimeGetCurrent()

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
                let dto: ChatResponseDTO
                do {
                    dto = try await backendProxy.chatWithMemos(question, dtos)
                } catch BackendProxyError.tokenNotFound {
                    // 自動認証
                    let deviceID = await UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
                    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
                    let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
                    _ = try await backendProxy.authenticate(deviceID, appVersion, osVersion)
                    dto = try await backendProxy.chatWithMemos(question, dtos)
                }

                let duration = CFAbsoluteTimeGetCurrent() - startTime
                #if DEBUG
                await APIRequestLogStore.shared.append(APIRequestLog(
                    source: .network,
                    endpoint: "/api/v1/ai/chat",
                    method: "POST",
                    status: .success(statusCode: 200),
                    duration: duration,
                    request: RequestDetail(body: "question: \(question), memos: \(dtos.count)件"),
                    response: ResponseDetail(body: "answer: \(dto.answer.prefix(100))..., refs: \(dto.referencedMemoIDs.count)件")
                ))
                #endif

                return ChatResponse(
                    answer: dto.answer,
                    referencedMemoIDs: dto.referencedMemoIDs
                )
            } catch {
                let duration = CFAbsoluteTimeGetCurrent() - startTime
                #if DEBUG
                await APIRequestLogStore.shared.append(APIRequestLog(
                    source: .network,
                    endpoint: "/api/v1/ai/chat",
                    method: "POST",
                    status: .failure(message: error.localizedDescription),
                    duration: duration,
                    request: RequestDetail(body: "question: \(question), memos: \(dtos.count)件"),
                    response: nil
                ))
                #endif
                throw error
            }
        }
    )
}
