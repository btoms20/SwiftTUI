import Benchmark
@_spi(Testing) import SwiftTUI

let benchmarks: @Sendable () -> Void = {
    Benchmark.defaultConfiguration = .init(
        metrics: [.wallClock, .cpuTotal, .throughput, .custom("writes"), .custom("bytes")],
        maxDuration: .seconds(5)
    )

    mainActorBenchmark("Full repaint 200x60") { benchmark in
        let output = CountingOutput()
        let app = Application(rootView: ColorGrid(columns: 20, lines: 60), output: output)
        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            // Resizing resets the screen cache, forcing every cell to be drawn.
            app.resize(columns: 200, lines: 60)
        }
        benchmark.stopMeasurement()
        output.record(in: benchmark)
    }

    mainActorBenchmark("Build 1k-row ForEach in ScrollView") { benchmark in
        for _ in benchmark.scaledIterations {
            let app = Application(rootView: LongList(count: 1_000), output: CountingOutput())
            app.resize(columns: 80, lines: 40)
            blackHole(app)
        }
    }

    mainActorBenchmark("Toggle deeply nested state") { benchmark in
        let output = CountingOutput()
        let app = Application(rootView: Nested(depth: 6), output: output)
        app.resize(columns: 80, lines: 40)
        output.reset()
        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            app.handleInput("\n")
            app.flushUpdates()
        }
        benchmark.stopMeasurement()
        output.record(in: benchmark)
    }

    mainActorBenchmark("Typing burst in TextField") { benchmark in
        let output = CountingOutput()
        let app = Application(rootView: TextField(placeholder: "Type here") { _ in }, output: output)
        app.resize(columns: 200, lines: 5)
        output.reset()
        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            for character in "The quick brown fox jumps over the lazy dog" {
                app.handleInput(String(character))
                app.flushUpdates()
            }
            // Submitting clears the field for the next iteration.
            app.handleInput("\n")
            app.flushUpdates()
        }
        benchmark.stopMeasurement()
        output.record(in: benchmark)
    }

    mainActorBenchmark("Layout nested stacks") { benchmark in
        let app = Application(rootView: NestedStacks(depth: 6), output: CountingOutput())
        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            app.resize(columns: 160, lines: 50)
        }
    }
}

/// Registers a benchmark whose body runs on the main actor.
///
/// SwiftTUI schedules its updates on the main queue, so driving it from the
/// runner's thread would race with them. The hop happens once per run, not
/// per iteration.
func mainActorBenchmark(_ name: String, _ body: @escaping @MainActor (Benchmark) -> Void) {
    Benchmark(name) { benchmark async in
        // `Benchmark` isn't Sendable, but the runner waits for us to finish,
        // so only one thread uses it at a time.
        nonisolated(unsafe) let benchmark = benchmark
        await MainActor.run { body(benchmark) }
    }
}

// MARK: - Output

/// Discards output, counting how many writes and bytes the renderer produced.
final class CountingOutput: TerminalOutput {
    private(set) var writes = 0
    private(set) var bytes = 0

    func write(_ string: String) {
        writes += 1
        bytes += string.utf8.count
    }

    func reset() {
        writes = 0
        bytes = 0
    }

    func record(in benchmark: Benchmark) {
        let iterations = max(benchmark.scaledIterations.count, 1)
        benchmark.measurement(.custom("writes"), writes / iterations)
        benchmark.measurement(.custom("bytes"), bytes / iterations)
    }
}

// MARK: - Views

struct ColorGrid: View {
    let columns: Int
    let lines: Int

    private static var colors: [Color] { [.red, .green, .yellow, .blue, .magenta, .cyan] }

    var body: some View {
        ForEach(0..<lines, id: \.self) { line in
            HStack(spacing: 0) {
                ForEach(0..<columns, id: \.self) { column in
                    Text("cell\(column % 10)  ")
                        .foregroundColor(Self.colors[(line + column) % Self.colors.count])
                        .bold(column.isMultiple(of: 2))
                }
            }
        }
    }
}

struct LongList: View {
    let count: Int

    var body: some View {
        ScrollView {
            ForEach(0..<count, id: \.self) { index in
                HStack {
                    Text("Row \(index)")
                    Spacer()
                    Text("detail").italic()
                }
            }
        }
    }
}

/// A button whose state change re-renders a subtree `depth` views deep.
struct Nested: View {
    @State private var toggled = false
    let depth: Int

    var body: some View {
        Button(toggled ? "On " : "Off") { toggled.toggle() }
        Level(depth: depth, toggled: toggled)
    }

    struct Level: View {
        let depth: Int
        let toggled: Bool

        var body: some View {
            if depth == 0 {
                Text(toggled ? "leaf on" : "leaf off")
            } else {
                VStack {
                    Text("level \(depth)")
                    Level(depth: depth - 1, toggled: toggled)
                        .padding(.left, 1)
                }
            }
        }
    }
}

/// Alternating horizontal and vertical stacks with flexible children.
struct NestedStacks: View {
    let depth: Int

    var body: some View {
        if depth == 0 {
            Text("x").frame(maxWidth: .infinity)
        } else if depth.isMultiple(of: 2) {
            HStack {
                NestedStacks(depth: depth - 1)
                Spacer()
                NestedStacks(depth: depth - 1)
            }
        } else {
            VStack {
                NestedStacks(depth: depth - 1)
                Divider()
                NestedStacks(depth: depth - 1)
            }
        }
    }
}
