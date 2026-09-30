import Foundation

/// A destination for the text and escape sequences produced by the renderer.
///
/// The default is ``StandardOutput``. Tests and benchmarks substitute their
/// own implementation to render without a real terminal.
@_spi(Testing)
public protocol TerminalOutput: AnyObject {
    func write(_ string: String)
}

/// Writes directly to the process's standard output.
final class StandardOutput: TerminalOutput {
    func write(_ string: String) {
        var string = string
        string.withUTF8 { Platform.write(UnsafeRawBufferPointer($0), to: STDOUT_FILENO) }
    }
}
