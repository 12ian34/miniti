import Foundation

/// Minimal Streamable HTTP MCP client for docs search (BYOK path).
/// Mirrors `miniti-api/lib/mcpClient.ts` + `docsMcp.ts` behavior.
enum DocsMCPService {
    struct Tool {
        let name: String
        let inputSchema: [String: Any]?
    }

    struct SearchTool {
        let name: String
        let queryArgument: String
    }

    struct DocChunk: Equatable {
        let title: String
        let url: String?
        let text: String
    }

    enum MCPError: LocalizedError {
        case invalidURL
        case blockedHost
        case httpError(Int)
        case invalidResponse
        case noSearchTool
        case timeout

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Docs MCP URL must be a valid https URL."
            case .blockedHost: return "Docs MCP host is not allowed."
            case .httpError(let code): return "Docs MCP HTTP error: \(code)."
            case .invalidResponse: return "Invalid response from Docs MCP server."
            case .noSearchTool: return "No searchable docs tool found on MCP server."
            case .timeout: return "Docs MCP request timed out."
            }
        }
    }

    // MARK: - URL validation (SSRF)

    static func validateMCPURL(_ raw: String) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "https",
              let host = url.host?.lowercased(),
              !host.isEmpty else {
            throw MCPError.invalidURL
        }
        if url.user != nil || url.password != nil {
            throw MCPError.invalidURL
        }
        if host == "localhost"
            || host.hasSuffix(".localhost")
            || host.hasSuffix(".local")
            || host.hasSuffix(".internal")
            || host == "metadata.google.internal"
            || isBlockedIPv4(host)
            || isBlockedIPv6(host) {
            throw MCPError.blockedHost
        }
        return url
    }

    static func isBlockedIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return false }
        let a = parts[0], b = parts[1]
        if a == 10 || a == 127 || a == 0 { return true }
        if a == 169 && b == 254 { return true }
        if a == 172 && (16...31).contains(b) { return true }
        if a == 192 && b == 168 { return true }
        if a == 100 && (64...127).contains(b) { return true }
        return false
    }

    static func isBlockedIPv6(_ host: String) -> Bool {
        let h = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        // Only apply IPv6 literal rules to actual IPv6 literals. Regular
        // hostnames like "fd7.example.com" contain no colon and are not
        // unique-local/link-local addresses.
        guard h.contains(":") else { return false }
        if h == "::1" || h == "::" { return true }
        // Unique-local (fc00::/7) and link-local (fe80::/10) ranges.
        if h.hasPrefix("fc") || h.hasPrefix("fd") { return true }
        if h.hasPrefix("fe80:") { return true }
        return false
    }

    // MARK: - Public API

    static func probe(mcpURL: String) async throws -> SearchTool {
        let url = try validateMCPURL(mcpURL)
        let client = Client(url: url)
        let tools = try await client.listTools()
        guard let search = discoverSearchTool(tools) else { throw MCPError.noSearchTool }
        return search
    }

    static func retrieveChunks(mcpURL: String, query: String) async throws -> (tool: SearchTool, chunks: [DocChunk]) {
        let url = try validateMCPURL(mcpURL)
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.count >= 3 else { throw MCPError.invalidResponse }

        let client = Client(url: url)
        let tools = try await client.listTools()
        guard let search = discoverSearchTool(tools) else { throw MCPError.noSearchTool }
        let content = try await client.callTool(name: search.name, arguments: [search.queryArgument: trimmedQuery])
        return (search, normalizeChunks(from: content))
    }

    // MARK: - Tool discovery

    private static let blockedToolNameRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "^(submit_feedback|feedback|create|update|delete|write|send|post|put|patch)",
        options: .caseInsensitive
    )

    static func discoverSearchTool(_ tools: [Tool]) -> SearchTool? {
        struct Scored {
            let tool: Tool
            let queryArgument: String
            let score: Int
        }

        var scored: [Scored] = []
        for tool in tools {
            let range = NSRange(tool.name.startIndex..<tool.name.endIndex, in: tool.name)
            if let blocked = blockedToolNameRegex,
               blocked.firstMatch(in: tool.name, options: [], range: range) != nil {
                continue
            }
            guard let arg = firstStringProperty(in: tool.inputSchema) else { continue }
            let name = tool.name.lowercased()
            var score = 0
            if name.contains("search") { score += 100 }
            if arg == "query" || arg == "q" { score += 20 }
            if name.contains("knowledge") || name.contains("docs") || name.contains("documentation") { score += 10 }
            if name.contains("filesystem") || name.contains("shell") || name.contains("feedback") || name.contains("submit") {
                score -= 50
            }
            scored.append(Scored(tool: tool, queryArgument: arg, score: score))
        }
        scored.sort { $0.score > $1.score }
        guard let best = scored.first, best.score >= 0 else { return nil }
        return SearchTool(name: best.tool.name, queryArgument: best.queryArgument)
    }

    private static func firstStringProperty(in schema: [String: Any]?) -> String? {
        guard let schema,
              let properties = schema["properties"] as? [String: Any] else { return nil }
        let required = (schema["required"] as? [String]) ?? []
        for key in required {
            if let prop = properties[key] as? [String: Any] {
                let type = prop["type"] as? String
                if type == nil || type == "string" { return key }
            }
        }
        for (key, value) in properties {
            if let prop = value as? [String: Any] {
                let type = prop["type"] as? String
                if type == nil || type == "string" { return key }
            }
        }
        return nil
    }

    // MARK: - Chunk normalization

    static func normalizeChunks(from contentItems: [[String: Any]]) -> [DocChunk] {
        var chunks: [DocChunk] = []
        for item in contentItems {
            if let text = item["text"] as? String {
                chunks.append(contentsOf: chunksFromText(text))
            }
        }
        var seen = Set<String>()
        var unique: [DocChunk] = []
        for chunk in chunks {
            let key = "\(chunk.url ?? "")|\(chunk.title)|\(chunk.text.prefix(80))"
            if seen.contains(key) { continue }
            seen.insert(key)
            unique.append(chunk)
            if unique.count >= 8 { break }
        }
        return unique
    }

    private static func chunksFromText(_ text: String) -> [DocChunk] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let title = match(pattern: #"(?:^|\n)\s*Title:\s*(.+)"#, in: trimmed)
        let link = match(pattern: #"(?:^|\n)\s*Link:\s*(https?://\S+)"#, in: trimmed)
        let content = match(pattern: #"(?:^|\n)\s*Content:\s*([\s\S]+)"#, in: trimmed)

        if title != nil || link != nil || content != nil {
            return [
                DocChunk(
                    title: String((title ?? link ?? "Documentation").prefix(200)),
                    url: link,
                    text: String((content ?? trimmed).prefix(4_000))
                )
            ]
        }

        return [
            DocChunk(title: "Documentation", url: nil, text: String(trimmed.prefix(4_000)))
        ]
    }

    private static func match(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let result = regex.firstMatch(in: text, options: [], range: range),
              result.numberOfRanges > 1,
              let swiftRange = Range(result.range(at: 1), in: text) else {
            return nil
        }
        return String(text[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - HTTP client

    /// Refuses HTTP redirects so an allowed host cannot 302 into a private one.
    /// Mirrors `redirect: 'error'` in `miniti-api/lib/mcpClient.ts`.
    private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }

    private final class Client: @unchecked Sendable {
        private let url: URL
        private var sessionId: String?
        private var initialized = false
        private let session: URLSession

        init(url: URL) {
            self.url = url
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 10
            config.timeoutIntervalForResource = 12
            self.session = URLSession(
                configuration: config,
                delegate: NoRedirectDelegate(),
                delegateQueue: nil
            )
        }

        func listTools() async throws -> [Tool] {
            try await initializeIfNeeded()
            let result = try await request(method: "tools/list")
            guard let toolsAny = result["tools"] as? [[String: Any]] else {
                throw MCPError.invalidResponse
            }
            return toolsAny.compactMap { item in
                guard let name = item["name"] as? String, !name.isEmpty else { return nil }
                return Tool(name: name, inputSchema: item["inputSchema"] as? [String: Any])
            }
        }

        func callTool(name: String, arguments: [String: Any]) async throws -> [[String: Any]] {
            try await initializeIfNeeded()
            let result = try await request(
                method: "tools/call",
                params: ["name": name, "arguments": arguments]
            )
            if result["isError"] as? Bool == true { return [] }
            return (result["content"] as? [[String: Any]]) ?? []
        }

        private func initializeIfNeeded() async throws {
            if initialized { return }
            _ = try await request(
                method: "initialize",
                params: [
                    "protocolVersion": "2024-11-05",
                    "capabilities": [:] as [String: Any],
                    "clientInfo": ["name": "miniti", "version": "1.0.0"] as [String: Any],
                ]
            )
            try? await notify(method: "notifications/initialized")
            initialized = true
        }

        private func notify(method: String) async throws {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
            if let sessionId {
                request.setValue(sessionId, forHTTPHeaderField: "Mcp-Session-Id")
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "jsonrpc": "2.0",
                "method": method,
            ])
            _ = try await session.data(for: request)
        }

        private func request(method: String, params: [String: Any]? = nil) async throws -> [String: Any] {
            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
            if let sessionId {
                urlRequest.setValue(sessionId, forHTTPHeaderField: "Mcp-Session-Id")
            }

            var payload: [String: Any] = [
                "jsonrpc": "2.0",
                "id": Int(Date().timeIntervalSince1970 * 1000) % 1_000_000,
                "method": method,
            ]
            if let params { payload["params"] = params }
            urlRequest.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: urlRequest)
            } catch {
                let ns = error as NSError
                if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorTimedOut {
                    throw MCPError.timeout
                }
                throw MCPError.invalidResponse
            }

            if let http = response as? HTTPURLResponse {
                if let sid = http.value(forHTTPHeaderField: "Mcp-Session-Id") {
                    sessionId = sid
                }
                guard (200...299).contains(http.statusCode) else {
                    throw MCPError.httpError(http.statusCode)
                }
            }

            guard data.count <= 512_000 else { throw MCPError.invalidResponse }
            let rpc = try parseJSONRPC(data)
            if let err = rpc["error"] as? [String: Any] {
                DebugLogger.shared.log(.app, "Docs MCP RPC error: \(err)")
                throw MCPError.invalidResponse
            }
            guard let result = rpc["result"] as? [String: Any] else {
                throw MCPError.invalidResponse
            }
            return result
        }

        private func parseJSONRPC(_ data: Data) throws -> [String: Any] {
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return obj
            }
            guard let text = String(data: data, encoding: .utf8) else {
                throw MCPError.invalidResponse
            }
            var lastData: String?
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                let lineStr = String(line)
                if lineStr.hasPrefix("data:") {
                    lastData = String(lineStr.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                }
            }
            guard let lastData,
                  let payload = lastData.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
                throw MCPError.invalidResponse
            }
            return obj
        }
    }
}
