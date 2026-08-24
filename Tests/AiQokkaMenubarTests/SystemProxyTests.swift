@testable import AiQokkaMenubar
import XCTest

final class SystemProxyTests: XCTestCase {
    func testParsesEnabledHTTPAndHTTPSProxies() {
        let settings = SystemProxySettings.parse(scutilOutput: """
        <dictionary> {
          HTTPEnable : 1
          HTTPPort : 29290
          HTTPProxy : 127.0.0.1
          HTTPSEnable : 1
          HTTPSPort : 29290
          HTTPSProxy : 127.0.0.1
        }
        """)

        XCTAssertEqual(
            settings.environmentVariables,
            [
                "HTTP_PROXY": "http://127.0.0.1:29290",
                "HTTPS_PROXY": "http://127.0.0.1:29290",
                "http_proxy": "http://127.0.0.1:29290",
                "https_proxy": "http://127.0.0.1:29290"
            ]
        )
    }

    func testIgnoresDisabledOrIncompleteProxyEntries() {
        let settings = SystemProxySettings.parse(scutilOutput: """
        <dictionary> {
          HTTPEnable : 0
          HTTPPort : 8080
          HTTPProxy : 127.0.0.1
          HTTPSEnable : 1
          HTTPSProxy : 127.0.0.1
        }
        """)

        XCTAssertTrue(settings.environmentVariables.isEmpty)
    }
}

final class ProcessCommandExecutorTests: XCTestCase {
    func testPassesResolvedProxyEnvironmentToProcess() async throws {
        let executor = ProcessCommandExecutor(
            proxyEnvironment: FixedProxyEnvironment(environment: [
                "HTTP_PROXY": "http://127.0.0.1:29290"
            ])
        )

        let output = try await executor.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [],
            timeout: .seconds(5)
        )

        XCTAssertEqual(output.status, 0)
        XCTAssertTrue(output.stdout.split(separator: "\n").contains("HTTP_PROXY=http://127.0.0.1:29290"))
    }
}

private struct FixedProxyEnvironment: ProxyEnvironmentProviding {
    let environment: [String: String]

    func environmentVariables() -> [String: String] {
        environment
    }
}
