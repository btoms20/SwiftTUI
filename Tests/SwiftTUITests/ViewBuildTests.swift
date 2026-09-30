import Testing
@testable import SwiftTUI

@MainActor
@Suite struct ViewBuildTests {
    @Test func vStackWithTwoTexts() {
        struct MyView: View {
            var body: some View {
                VStack {
                    Text("One")
                    Text("Two")
                }
            }
        }

        #expect(TestHost(MyView()).controlTree == """
            → VStackControl
              → TextControl
              → TextControl
            """)
    }

    @Test func conditionalVStack() {
        struct MyView: View {
            @State var value = true

            var body: some View {
                if value {
                    VStack {
                        Text("One")
                    }
                }
            }
        }

        #expect(TestHost(MyView()).controlTree == """
            → VStackControl
              → TextControl
            """)
    }

    @Test func modifiersWrapControls() {
        let host = TestHost {
            Text("A")
                .padding(1)
                .border()
        }

        #expect(host.controlTree == """
            → BorderControl
              → PaddingControl
                → TextControl
            """)
    }

    @Test func forEachProducesOneControlPerElement() {
        let host = TestHost {
            ForEach(1...3, id: \.self) { Text("\($0)") }
        }

        #expect(host.controlTree == """
            → TextControl
            → TextControl
            → TextControl
            """)
    }
}
