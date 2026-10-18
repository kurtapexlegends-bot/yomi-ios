import XCTest
import JavaScriptCore
@testable import YomiCore
@testable import YomiExtensions

final class ExtensionBridgeTests: XCTestCase {
    func testHTMLAndCryptoBridgeExecution() throws {
        guard let context = JSContext() else {
            XCTFail("Failed to create JSContext")
            return
        }

        HTMLBridge.inject(into: context)
        CryptoBridge.inject(into: context)

        // Test Native HTML Parser
        let htmlSample = "<div class='manga-title'>Chainsaw Man</div>"
        let script = "__yomi_text(\"\(htmlSample)\", \".manga-title\")"
        let textResult = context.evaluateScript(script)
        XCTAssertEqual(textResult?.toString(), "Chainsaw Man")

        // Test Crypto SHA256 Hash
        let hashScript = "__yomi_sha256('yomi')"
        let hashResult = context.evaluateScript(hashScript)
        XCTAssertNotNil(hashResult?.toString())
        XCTAssertEqual(hashResult?.toString().count, 64)
    }
}
