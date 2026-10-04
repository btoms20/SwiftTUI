import Foundation

/// A pseudo-terminal pair, so terminal behavior can be tested without a real terminal.
///
/// The secondary end behaves like a terminal device for whatever is attached to
/// it; the primary end sees what it writes and can type into it.
struct PseudoTerminal {
    let primary: Int32
    let secondary: Int32

    init?() {
        primary = posix_openpt(O_RDWR | O_NOCTTY)
        guard primary >= 0, grantpt(primary) == 0, unlockpt(primary) == 0, let name = ptsname(primary) else {
            return nil
        }
        secondary = open(name, O_RDWR | O_NOCTTY)
        guard secondary >= 0 else { return nil }
    }

    var attributes: termios {
        var attributes = termios()
        tcgetattr(secondary, &attributes)
        return attributes
    }

    /// Sets the size reported to programs attached to the secondary end.
    func setSize(columns: Int, lines: Int) {
        var size = winsize(ws_row: UInt16(lines), ws_col: UInt16(columns), ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(primary, UInt(TIOCSWINSZ), &size)
    }

    func close() {
        Foundation.close(primary)
        Foundation.close(secondary)
    }
}
