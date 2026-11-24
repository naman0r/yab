import Foundation
import Testing
@testable import Fast

/// Words queued with ⌘Enter behind a running Claude Code, then a message
/// sent now with Enter (#1029, #1030). Claude Code's stdin is a file here,
/// so nothing reaches a provider.
@MainActor
struct ChatQueueTests {
    private func running() throws -> (Agents, Agents.Session, () -> Void) {
        let suite = "chat-queue-" + UUID().uuidString
        let settings = UserDefaults(suiteName: suite)!
        let consent = ProviderConsent(settings: settings, history: [])
        consent.grant("claude")
        let stdin = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        FileManager.default.createFile(atPath: stdin.path, contents: Data())
        let agents = Agents()
        let session = Agents.Session(id: suite, cli: "claude", name: "Claude", prompt: "First", state: .running)
        session.providerPermit = consent.permit("claude")
        session.input = try FileHandle(forWritingTo: stdin)
        agents.register(session)
        return (agents, session, {
            try? session.input?.close()
            try? FileManager.default.removeItem(at: stdin)
            settings.removePersistentDomain(forName: suite)
        })
    }

    @Test func aMessageSentNowIsShownWithItsOwnWordsAndWhatWentWithIt() throws {
        let (agents, session, done) = try running()
        defer { done() }
        agents.followUp(session.id, "Q1", queue: true)
        agents.followUp(session.id, "Q2", queue: true)
        agents.followUp(session.id, "S: please do this now", with: [.quote("the line")])
        let asked = try #require(session.items.last { $0.kind == .asked })
        #expect(asked.text == "S: please do this now")
        #expect(asked.detail == ChatAttachment.labels(tabs: [], files: [], quotes: ["the line"]).joined(separator: "\n"))
        #expect(session.sent[asked.id] == [.quote("the line")])
        #expect(session.queue == ["Q1", "Q2"])
        #expect(session.saying == ["Q1", "Q2"])
        #expect(session.carrying == [[], []] && session.attaching == [[], []])
    }

    @Test func queueingIsNotSending() throws {
        let (agents, session, done) = try running()
        defer { done() }
        agents.followUp(session.id, "Q1", queue: true)
        agents.followUp(session.id, "Q2", queue: true)
        #expect(session.unheard == 0, "queued words do not move the transcript")
        // As the turn's end lets the first go (Agents.turned).
        session.queue.removeFirst()
        #expect(session.unheard == 1, "sent from the queue, it follows them down")
    }
}
