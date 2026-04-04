import Dependencies
import Domain
import Foundation
import InfraNetwork

// MARK: - MemoConversation Live Dependencies
// TASK-0041: きおくに聞く（AI対話）の Live DI 接続

extension MemoConversationClient: DependencyKey {
    public static let liveValue: MemoConversationClient = {
        @Dependency(\.backendProxy) var backendProxy

        return MemoConversationClient(
            sendQuestion: { question, contextMemos in
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
                let dto = try await backendProxy.chatWithMemos(question, dtos)

                // ChatResponseDTO → ChatResponse に変換
                return ChatResponse(
                    answer: dto.answer,
                    referencedMemoIDs: dto.referencedMemoIDs
                )
            }
        )
    }()
}
