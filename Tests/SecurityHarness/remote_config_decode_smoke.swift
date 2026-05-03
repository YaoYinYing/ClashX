import Foundation

func assertPass(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
enum RemoteConfigDecodeSmokeMain {
    static func main() throws {
        let decoder = JSONDecoder()

        let oldPayload = """
        [
          {
            "url": "https://example.com/legacy",
            "name": "legacy-profile",
            "updateTime": 0
          }
        ]
        """.data(using: .utf8)!

        let oldModels = try decoder.decode([RemoteConfigModel].self, from: oldPayload)
        assertPass(oldModels.count == 1, "old payload should decode one profile")
        assertPass(oldModels[0].validationState == .unknown, "old payload should default validationState to unknown")
        assertPass(oldModels[0].lastUpdateState == .never, "old payload should default lastUpdateState to never")
        assertPass(oldModels[0].lastUpdateMessage == nil, "old payload should default lastUpdateMessage to nil")
        assertPass(oldModels[0].updating == false, "old payload should default updating to false")
        assertPass(oldModels[0].isPlaceHolderName == false, "old payload should default placeholder flag to false")

        let newPayload = """
        [
          {
            "url": "https://example.com/new",
            "name": "new-profile",
            "validationState": "valid",
            "lastUpdateState": "succeeded",
            "lastUpdateMessage": "Last update succeeded."
          }
        ]
        """.data(using: .utf8)!

        let newModels = try decoder.decode([RemoteConfigModel].self, from: newPayload)
        assertPass(newModels.count == 1, "new payload should decode one profile")
        assertPass(newModels[0].validationState == .valid, "new payload should preserve validationState")
        assertPass(newModels[0].lastUpdateState == .succeeded, "new payload should preserve lastUpdateState")
        assertPass(newModels[0].lastUpdateMessage == "Last update succeeded.", "new payload should preserve lastUpdateMessage")

        print("Remote config decode smoke checks passed")
    }
}
