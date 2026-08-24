import Foundation

protocol ProxyEnvironmentProviding: Sendable {
    func environmentVariables() -> [String: String]
}

struct SystemProxyEnvironment: ProxyEnvironmentProviding {
    func environmentVariables() -> [String: String] {
        guard let output = Self.readScutilProxyOutput() else { return [:] }
        return SystemProxySettings.parse(scutilOutput: output).environmentVariables
    }

    private static func readScutilProxyOutput() -> String? {
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/scutil")
        process.arguments = ["--proxy"]
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }
}

struct SystemProxySettings: Equatable, Sendable {
    let http: ProxyEndpoint?
    let https: ProxyEndpoint?

    var environmentVariables: [String: String] {
        var variables: [String: String] = [:]
        if let http {
            let value = http.environmentValue
            variables["HTTP_PROXY"] = value
            variables["http_proxy"] = value
        }
        if let https {
            let value = https.environmentValue
            variables["HTTPS_PROXY"] = value
            variables["https_proxy"] = value
        }
        return variables
    }

    static func parse(scutilOutput: String) -> Self {
        let values = scutilOutput.split(whereSeparator: \.isNewline).reduce(into: [String: String]()) { values, line in
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            values[key] = value
        }

        return Self(
            http: endpoint(prefix: "HTTP", values: values),
            https: endpoint(prefix: "HTTPS", values: values)
        )
    }

    private static func endpoint(prefix: String, values: [String: String]) -> ProxyEndpoint? {
        guard let enabled = values["\(prefix)Enable"], ["1", "true", "yes"].contains(enabled.lowercased()),
              let host = values["\(prefix)Proxy"], !host.isEmpty,
              let port = values["\(prefix)Port"].flatMap(Int.init), port > 0
        else { return nil }

        return ProxyEndpoint(host: host, port: port)
    }
}

struct ProxyEndpoint: Equatable, Sendable {
    let host: String
    let port: Int

    var environmentValue: String {
        let formattedHost = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        return "http://\(formattedHost):\(port)"
    }
}
