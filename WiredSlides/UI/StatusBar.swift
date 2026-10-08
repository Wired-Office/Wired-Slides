import SwiftUI

/// Slide position, view switches and zoom along the bottom of the window.
struct StatusBarView: View {
    @ObservedObject var controller: PresentationController
    @ObservedObject var settings = AppSettings.shared
    let onStartShow: () -> Void
    let onReadingView: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Circle()
                    .fill(controller.editingElement != nil ? Color.orange : Theme.accentColor)
                    .frame(width: 7, height: 7)
                Text("Slide \(controller.currentSlideIndex + 1) of \(controller.slides.count)")
                    .monospacedDigit()
                if let section = controller.presentation.section(forSlideAt: controller.currentSlideIndex) {
                    Text("·  \(section.name)").foregroundStyle(.secondary).lineLimit(1)
                }
                if let message = controller.statusMessage {
                    Text("·  \(message)").foregroundStyle(.secondary).lineLimit(1).monospacedDigit()
                } else if controller.pendingInsert != nil {
                    Text("·  Drag on the slide to draw. ⇧ constrains; Esc cancels.").foregroundStyle(.secondary).lineLimit(1)
                } else if controller.formatPainter != nil {
                    Text("·  Click an object to paste its formatting.").foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 10)
            toggle("Notes", "note.text", isOn: settings.showNotesPane) { settings.showNotesPane.toggle() }
            toggle("Comments", "text.bubble", isOn: controller.sidePane == .comments) {
                controller.sidePane = controller.sidePane == .comments ? nil : .comments
            }
            Divider().frame(height: 14)
            HStack(spacing: 2) {
                viewButton(.normal)
                viewButton(.sorter)
                Button(action: onReadingView) { Image(systemName: "book").frame(width: 24, height: 20) }
                    .buttonStyle(.plain).help("Reading View")
                Button(action: onStartShow) { Image(systemName: "play.rectangle").frame(width: 24, height: 20) }
                    .buttonStyle(.plain).help("Slide Show from Current Slide (⇧⌘↩)")
            }
            Divider().frame(height: 14)
            zoomControl
        }
        .font(.system(size: 11.5))
        .padding(.horizontal, 12)
        .frame(height: 26)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: Theme.barBackground))
    }

    private func toggle(_ title: String, _ symbol: String, isOn: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).labelStyle(.titleAndIcon)
                .foregroundStyle(isOn ? Theme.accentColor : Color.primary.opacity(0.75))
        }
        .buttonStyle(.plain)
    }

    private func viewButton(_ mode: ViewMode) -> some View {
        Button { controller.viewMode = mode } label: {
            Image(systemName: mode.symbol)
                .frame(width: 24, height: 20)
                .foregroundStyle(controller.viewMode == mode ? Theme.accentColor : Color.primary.opacity(0.75))
        }
        .buttonStyle(.plain)
        .help(mode.title)
    }

    private var zoomControl: some View {
        let zoom = controller.zoom
        return HStack(spacing: 6) {
            Button { setZoom(max(0.1, (zoom * 10).rounded(.down) / 10 - 0.1)) } label: { Image(systemName: "minus") }
                .buttonStyle(.plain).help("Zoom Out")
            Slider(value: Binding(get: { log2(zoom) }, set: { setZoom(pow(2, $0)) }), in: log2(0.1)...log2(4))
                .controlSize(.mini)
                .frame(width: 100)
            Button { setZoom(min(4, (zoom * 10).rounded(.up) / 10 + 0.1)) } label: { Image(systemName: "plus") }
                .buttonStyle(.plain).help("Zoom In")
            Menu {
                ForEach([0.33, 0.5, 0.66, 1, 1.5, 2, 3], id: \.self) { level in
                    Button("\(Int(level * 100))%") { setZoom(level) }
                }
                Divider()
                Button("Fit Slide to Window") { controller.fitToWindow = true }
            } label: {
                Text("\(Int((zoom * 100).rounded()))%").monospacedDigit().frame(width: 40, alignment: .trailing)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            Button { controller.fitToWindow = true } label: {
                Image(systemName: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left")
                    .foregroundStyle(controller.fitToWindow ? Theme.accentColor : Color.primary.opacity(0.75))
            }
            .buttonStyle(.plain)
            .help("Fit Slide to Current Window")
        }
    }

    private func setZoom(_ value: Double) {
        controller.fitToWindow = false
        controller.zoom = max(0.1, min(4, value))
    }
}
