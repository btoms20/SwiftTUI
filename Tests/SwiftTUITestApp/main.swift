import SwiftTUI

/// A small app that end-to-end tests run in a pseudo-terminal: it echoes
/// submitted text, so tests can check input reaches the views and redraws.
struct EchoView: View {
    @State private var submitted = ""

    var body: some View {
        Text("ready")
        TextField(placeholder: "type here") { submitted = $0 }
        Text("echo: \(submitted)")
    }
}

Application(rootView: EchoView()).start()
