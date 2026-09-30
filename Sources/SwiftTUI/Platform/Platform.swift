#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// Thin wrappers around the POSIX calls SwiftTUI needs, so the rest of the
/// package doesn't have to care which C library it is linked against.
enum Platform {
    /// Writes all of `bytes` to `fileDescriptor`, retrying on partial writes
    /// and interrupted system calls.
    static func write(_ bytes: UnsafeRawBufferPointer, to fileDescriptor: Int32) {
        guard var pointer = bytes.baseAddress else { return }
        var remaining = bytes.count
        while remaining > 0 {
            let written = systemWrite(fileDescriptor, pointer, remaining)
            if written < 0 {
                if errno == EINTR { continue }
                return
            }
            pointer += written
            remaining -= written
        }
    }

    /// The size of the terminal attached to `fileDescriptor`, or `nil` if it
    /// isn't a terminal.
    static func terminalSize(of fileDescriptor: Int32) -> Size? {
        var size = winsize()
        guard ioctl(fileDescriptor, UInt(TIOCGWINSZ), &size) == 0,
              size.ws_col > 0, size.ws_row > 0 else {
            return nil
        }
        return Size(width: Extended(Int(size.ws_col)), height: Extended(Int(size.ws_row)))
    }
}

// `write` is shadowed by `Platform.write` inside the enum.
private func systemWrite(_ fd: Int32, _ buffer: UnsafeRawPointer, _ count: Int) -> Int {
    write(fd, buffer, count)
}
