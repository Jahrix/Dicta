import Foundation

struct LocalWhisperSupportedFlags {
    let beamSizeFlag: String?
    let temperatureFlag: String?
    let bestOfFlag: String?
    let languageFlag: String?
    let promptFlag: String?
    let noTimestampsFlag: String?
    let threadsFlag: String?
}

enum LocalWhisperProcessError: Error {
    case nonZeroExit(code: Int, stderr: String, stdout: String)
}

struct WhisperCLIArgs {
    let modelURL: URL
    let wavURL: URL
    let languageCode: String
    let beamSize: Int
    let temperature: Double
    let bestOf: Int
    let threads: Int
    let prompt: String
    let supportedFlags: LocalWhisperSupportedFlags

    func makeArguments() -> [String] {
        var arguments: [String] = ["-m", modelURL.path, "-f", wavURL.path]
        if let flag = supportedFlags.noTimestampsFlag {
            arguments.append(flag)
        }
        if let flag = supportedFlags.languageFlag, !languageCode.isEmpty {
            arguments.append(contentsOf: [flag, languageCode])
        }
        if let flag = supportedFlags.beamSizeFlag {
            arguments.append(contentsOf: [flag, String(beamSize)])
        }
        if let flag = supportedFlags.temperatureFlag {
            arguments.append(contentsOf: [flag, String(temperature)])
        }
        if let flag = supportedFlags.bestOfFlag {
            arguments.append(contentsOf: [flag, String(bestOf)])
        }
        if let flag = supportedFlags.threadsFlag, threads > 0 {
            arguments.append(contentsOf: [flag, String(threads)])
        }
        if let flag = supportedFlags.promptFlag, !prompt.isEmpty {
            arguments.append(contentsOf: [flag, prompt])
        }
        return arguments
    }

    var redactedDescription: String {
        var output: [String] = []
        var redactNext: String?
        for arg in makeArguments() {
            if let token = redactNext {
                output.append(token)
                redactNext = nil
                continue
            }
            switch arg {
            case "-m":
                output.append(arg)
                redactNext = "<model>"
            case "-f":
                output.append(arg)
                redactNext = "<wav>"
            case "-p", "--prompt":
                output.append(arg)
                redactNext = "<prompt>"
            default:
                output.append(arg)
            }
        }
        return output.joined(separator: " ")
    }
}
