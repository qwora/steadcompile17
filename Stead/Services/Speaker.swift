import AVFoundation
import NaturalLanguage

/// Reads warnings aloud in the language of the text (Korean, Malay or English).
@MainActor
final class Speaker: ObservableObject {
    static let shared = Speaker()
    @Published private(set) var isSpeaking = false

    private let synth = AVSpeechSynthesizer()
    private var delegate: Delegate?

    func toggle(_ text: String) {
        if synth.isSpeaking { stop(); return }
        speak(text)
    }

    func speak(_ text: String) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: voiceLanguage(for: text))
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        let d = Delegate { [weak self] in self?.isSpeaking = false }
        delegate = d
        synth.delegate = d
        isSpeaking = true
        synth.speak(utterance)
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    private func voiceLanguage(for text: String) -> String {
        switch AnalyzeClient.locale(for: text) {
        case "ko": "ko-KR"
        case "ms": "ms-MY"
        default: "en-US"
        }
    }

    private final class Delegate: NSObject, AVSpeechSynthesizerDelegate {
        let done: @MainActor () -> Void
        init(done: @escaping @MainActor () -> Void) { self.done = done }
        func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) { Task { @MainActor in done() } }
        func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) { Task { @MainActor in done() } }
    }
}
