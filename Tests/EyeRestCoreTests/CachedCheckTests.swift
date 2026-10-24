import Foundation
import Testing
@testable import EyeRestCore

struct Caching {
    @Test func anAnswerIsReusedForItsLifetime() {
        var cache = CachedCheck<String?>(lifetime: .seconds(5))
        let start = ContinuousClock.now
        var checks = 0
        func ask(at seconds: Int, answer: String?) -> String? {
            cache.value(at: start + .seconds(seconds)) {
                checks += 1
                return answer
            }
        }
        #expect(ask(at: 0, answer: "camera in use") == "camera in use")
        #expect(ask(at: 4, answer: nil) == "camera in use")
        #expect(ask(at: 5, answer: nil) == nil)
        #expect(ask(at: 9, answer: "camera in use") == nil)  // "not in a call" is reused too
        #expect(checks == 2)
    }
}
