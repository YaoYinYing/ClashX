import Foundation

func assertContains(_ text: String?, _ expected: String, _ message: String) {
    guard let text, text.contains(expected) else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func assertNotContains(_ text: String?, _ unexpected: String, _ message: String) {
    guard let text else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
    if text.contains(unexpected) {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
enum RedactorSmokeMain {
    static func main() {
        let urlResult = SmartXRedactor.redactURLString("https://example.com/sub?token=abc#frag")
        assertContains(urlResult, "https://example.com/sub?token=%3Credacted%3E", "URL redaction should preserve origin and redact token values")
        assertNotContains(urlResult, "#frag", "URL redaction should remove fragments")
        assertNotContains(urlResult, "abc", "URL redaction should remove raw token values")

        let textURL = SmartXRedactor.sanitizeText("download from https://example.com/sub?token=abc")
        assertContains(textURL, "https://example.com/sub?token=%3Credacted%3E", "sanitizeText should redact HTTP URL query values without recursion")
        assertNotContains(textURL, "abc", "sanitizeText should remove URL token values")

        let reportLikeText = SmartXRedactor.sanitizeText("Active Profile Source: https://example.com/sub?token=abc")
        assertContains(reportLikeText, "https://example.com/sub?token=%3Credacted%3E", "report-like text should keep the URL shape while redacting query values")
        assertNotContains(reportLikeText, "abc", "report-like text should not leak query values")

        let homePathText = SmartXRedactor.sanitizeText("Log Folder: \(NSHomeDirectory())/Library/Logs")
        assertContains(homePathText, "~/Library/Logs", "sanitizeText should replace the home directory with ~")
        assertNotContains(homePathText, NSHomeDirectory(), "sanitizeText should not keep the full home directory path")

        let proxyText = SmartXRedactor.sanitizeText("proxy: trojan://secret@example.com")
        assertContains(proxyText, "<redacted-proxy-uri>", "sanitizeText should redact proxy URIs")
        assertNotContains(proxyText, "trojan://secret@example.com", "sanitizeText should not leak proxy URI secrets")

        let authText = SmartXRedactor.sanitizeText("Authorization: Bearer abcdef")
        assertContains(authText, "Authorization: <redacted>", "sanitizeText should redact authorization-style values")
        assertNotContains(authText, "abcdef", "sanitizeText should not leak authorization values")

        print("SmartX redactor smoke checks passed")
    }
}
