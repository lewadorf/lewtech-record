import Darwin
import Foundation

struct VerificationFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

func verificationRequire(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw VerificationFailure(message: message) }
}

@main
struct LewtechVerification {
    @MainActor
    static func main() async {
        var suites: [[String: Any]] = []
        var passed = true
        do {
            let count = try runTimelineChecks()
            suites.append(["suite": "timeline", "passed": true, "checks": count])
        } catch {
            passed = false
            suites.append(["suite": "timeline", "passed": false, "error": error.localizedDescription])
        }
        do {
            let count = try await runLibraryStoreChecks()
            suites.append(["suite": "library", "passed": true, "checks": count])
        } catch {
            passed = false
            suites.append(["suite": "library", "passed": false, "error": error.localizedDescription])
        }
        do {
            let count = try await runSyntheticPipelineChecks()
            suites.append(["suite": "media-pipeline", "passed": true, "checks": count, "synthetic": true,
                           "note": "Synthetic pixels and PCM exercise the real compositor, H.264/AAC writer and decoder. This does not verify device capture or macOS permissions."])
        } catch {
            passed = false
            suites.append(["suite": "media-pipeline", "passed": false, "synthetic": true, "error": error.localizedDescription])
        }
        do {
            let count = try runPreviewChecks()
            suites.append(["suite": "live-preview", "passed": true, "checks": count, "synthetic": true])
        } catch {
            passed = false
            suites.append(["suite": "live-preview", "passed": false, "error": error.localizedDescription])
        }
        if ProcessInfo.processInfo.environment["LEWTECH_STRESS_SECONDS"] != nil {
            do {
                let count = try await runFragmentTimingChecks()
                suites.append(["suite": "fragment-timing", "passed": true, "checks": count])
            } catch {
                passed = false
                suites.append(["suite": "fragment-timing", "passed": false, "error": String(describing: error)])
            }
        }
        let report: [String: Any] = ["passed": passed, "suites": suites]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
           let json = String(data: data, encoding: .utf8) { print(json) }
        else { print("Verification report failed to serialize."); exit(2) }
        exit(passed ? 0 : 1)
    }
}
