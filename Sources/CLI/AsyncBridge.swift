/// Shared async→sync bridge for ArgumentParser commands.
///
/// ArgumentParser's `run()` is synchronous, but our Infrastructure layer
/// (DisplayDetector, etc.) uses async/await. This utility bridges the two
/// worlds using a semaphore + Task, so every command doesn't need its own
/// copy of the pattern.
///
/// Usage:
///   let displays = try syncBridge { try await detector.connectedDisplays() }

import Foundation

/// Thread-safe box for passing a `Result` across the Task/semaphore boundary.
/// Marked `@unchecked Sendable` because access is serialised by the semaphore:
/// the Task writes `.value` before signalling, and the caller reads it only
/// after `sem.wait()` returns.
final class AsyncBox<T: Sendable>: @unchecked Sendable {
    var value: Result<T, Error>?
}

/// Execute an async throwing closure synchronously.
///
/// This is the single canonical way to call async code from ArgumentParser's
/// synchronous `run()`.  A `DispatchSemaphore` blocks the calling thread
/// while a detached `Task` performs the work.
///
/// - Parameter block: The async work to execute.
/// - Returns: The value produced by `block`.
/// - Throws: Any error thrown by `block`.
func syncBridge<T: Sendable>(_ block: @Sendable @escaping () async throws -> T) throws -> T {
    let sem = DispatchSemaphore(value: 0)
    let box = AsyncBox<T>()
    Task { @Sendable in
        do { box.value = .success(try await block()) }
        catch { box.value = .failure(error) }
        sem.signal()
    }
    sem.wait()
    switch box.value! {
    case .success(let v): return v
    case .failure(let e): throw e
    }
}
