import Foundation

/// Per-task state, isolated by an actor so concurrent writes from the pipe and
/// process-termination callbacks can't trip Swift's exclusivity check.
private actor StreamState {
    private var buffer = Data()
    private var finished = false
    private var continuation: AsyncStream<String>.Continuation?

    func setContinuation(_ c: AsyncStream<String>.Continuation) { self.continuation = c }

    func handle(_ data: Data) {
        if finished || data.isEmpty { return }
        buffer.append(data)
        while let idx = buffer.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            let lineData = buffer.subdata(in: 0..<idx)
            buffer.removeSubrange(0...idx)
            if !lineData.isEmpty, let line = String(data: lineData, encoding: .utf8) {
                continuation?.yield(line)
            }
        }
    }

    func finish(exitCode: Int32) {
        if finished { return }
        if !buffer.isEmpty, let tail = String(data: buffer, encoding: .utf8) {
            continuation?.yield(tail)
        }
        buffer.removeAll(keepingCapacity: false)
        continuation?.yield("[exit \(exitCode)]")
        continuation?.finish()
        finished = true
        continuation = nil
    }

    func failLaunch(_ message: String) {
        if finished { return }
        continuation?.yield("[failed to launch: \(message)]")
        continuation?.finish()
        finished = true
        continuation = nil
    }
}

final class ShellTask {
    let process: Process
    let stream: AsyncStream<String>
    private let state = StreamState()

    init(executable: String, arguments: [String], environment: [String: String]? = nil) {
        let process = Process()
        self.process = process
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["LC_ALL"] = "C"
        env["LANG"] = "C"
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        if let extra = environment { for (k, v) in extra { env[k] = v } }
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        let readHandle = pipe.fileHandleForReading

        var contRef: AsyncStream<String>.Continuation!
        self.stream = AsyncStream { cont in contRef = cont }
        let stateRef = self.state
        Task { await stateRef.setContinuation(contRef) }

        readHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            Task { await stateRef.handle(data) }
        }

        process.terminationHandler = { proc in
            readHandle.readabilityHandler = nil
            let code = proc.terminationStatus
            Task { await stateRef.finish(exitCode: code) }
        }

        do {
            try process.run()
        } catch {
            let msg = error.localizedDescription
            Task { await stateRef.failLaunch(msg) }
        }

        contRef.onTermination = { [weak self] _ in
            self?.cancel()
        }
    }

    func cancel() {
        if process.isRunning { process.terminate() }
    }
}

enum ShellRunner {
    /// Spawn a streaming task. Returns a ShellTask the caller can cancel().
    static func task(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil
    ) -> ShellTask {
        ShellTask(executable: executable, arguments: arguments, environment: environment)
    }

    /// Convenience.
    static func stream(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil
    ) -> AsyncStream<String> {
        ShellTask(executable: executable, arguments: arguments, environment: environment).stream
    }

    /// Run the entire command as root via one admin password prompt. Blocks until done.
    /// Returns combined stdout+stderr and exit code. Use Task.detached for off-main execution.
    /// Output is NOT streamed — caller should show a spinner and dump the result on completion.
    static func runAsAdmin(shell command: String) -> (output: String, exit: Int32) {
        let tmpDir = NSTemporaryDirectory()
        let scriptFile = (tmpDir as NSString).appendingPathComponent("meisterproper-\(UUID().uuidString).sh")
        let scriptBody = """
        #!/bin/bash
        set -o pipefail
        { \(command); } 2>&1
        """
        try? scriptBody.write(toFile: scriptFile, atomically: true, encoding: .utf8)
        _ = run(executable: "/bin/chmod", arguments: ["+x", scriptFile])
        let appleScript = "do shell script \"/bin/bash \(scriptFile)\" with administrator privileges"
        let r = run(executable: "/usr/bin/osascript", arguments: ["-e", appleScript])
        try? FileManager.default.removeItem(atPath: scriptFile)
        return r
    }

    /// Open a command in Terminal.app for interactive use.
    static func openInTerminal(_ command: String) {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = "tell application \"Terminal\" to activate\n" +
                     "tell application \"Terminal\" to do script \"\(escaped)\""
        _ = run(executable: "/usr/bin/osascript", arguments: ["-e", script])
    }

    /// Run a one-shot command, return combined stdout+stderr and exit code.
    @discardableResult
    static func run(executable: String, arguments: [String]) -> (output: String, exit: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        env["LC_ALL"] = "C"; env["LANG"] = "C"
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return ("[failed: \(error.localizedDescription)]", -1) }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (String(data: data, encoding: .utf8) ?? "", process.terminationStatus)
    }

    /// Execute a shell command with admin privileges (one-shot, no stream). Convenience wrapper.
    static func runWithAdmin(shell: String) -> (output: String, exit: Int32) {
        let escaped = shell
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"
        return run(executable: "/usr/bin/osascript", arguments: ["-e", script])
    }
}
