// eyerest-mcp: lets AI agents read EyeRest's break status and screen time.
// It speaks MCP over stdio, e.g.:
//   claude mcp add eyerest -- /Applications/EyeRest.app/Contents/MacOS/eyerest-mcp
import EyeRestCore
import EyeRestMCP
import Foundation

let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
let server = MCPServer(store: ActivityStore(), version: version)

while let line = readLine(strippingNewline: true) {
    guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
    if let response = server.handle(line) {
        print(response)
        fflush(stdout)
    }
}
