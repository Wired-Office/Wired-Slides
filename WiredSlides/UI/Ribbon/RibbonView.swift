import AppKit
import SwiftUI

/// The PowerPoint-style ribbon: tabs (plus contextual tabs for the selection) over commands.
/// Double-click a tab (or use the chevron) to collapse it to just the tabs.
struct RibbonView: View {
    @ObservedObject var model: RibbonModel
    @ObservedObject var controller: PresentationController

    /// Contextual tabs for what's selected.
    private var contextualTabs: [RibbonModel.Tab] {
        guard let e = controller.primaryElement else { return [] }
        switch e.content {
        case .shape, .line, .group, .icon: return [.shapeFormat]
        case .image: return [.shapeFormat, .pictureFormat]
        case .table: return [.tableDesign, .tableLayout]
        case .chart: return [.chartDesign, .shapeFormat]
        case .media(let m): return m.kind == .video ? [.pictureFormat, .playback] : [.playback]
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            tabStrip
            if !model.isCollapsed {
                ScrollView(.horizontal, showsIndicators: false) {
                    content
                        .padding(.horizontal, 10)
                        .frame(height: RibbonModel.contentHeight, alignment: .center)
                }
                .frame(height: RibbonModel.contentHeight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: Theme.barBackground))
        .onChange(of: contextualTabs) { _, tabs in
            // Leave a contextual tab that no longer applies.
            if model.tab.isContextual && !tabs.contains(model.tab) { model.tab = .home }
        }
    }

    private var tabStrip: some View {
        HStack(spacing: 2) {
            ForEach(RibbonModel.Tab.standard) { tab in
                tabButton(tab)
            }
            if !contextualTabs.isEmpty {
                Rectangle().fill(Color.primary.opacity(0.15)).frame(width: 1, height: 18).padding(.horizontal, 6)
                ForEach(contextualTabs) { tab in
                    tabButton(tab, contextual: true)
                }
            }
            Spacer(minLength: 8)
            Button {
                model.isCollapsed.toggle()
            } label: {
                Image(systemName: model.isCollapsed ? "chevron.down" : "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 26, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(RibbonButtonStyle())
            .help(model.isCollapsed ? "Show the Ribbon" : "Collapse the Ribbon")
        }
        .padding(.horizontal, 12)
        .frame(height: RibbonModel.tabHeight)
    }

    private func tabButton(_ tab: RibbonModel.Tab, contextual: Bool = false) -> some View {
        RibbonTabButton(title: tab.title, isSelected: model.tab == tab && !model.isCollapsed, contextual: contextual) {
            if model.tab == tab && !model.isCollapsed { return }
            model.tab = tab
            if model.isCollapsed { model.isCollapsed = false }
        } onDoubleClick: {
            model.tab = tab
            model.isCollapsed.toggle()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.tab {
        case .home: HomeTab(controller: controller)
        case .insert: InsertTab(controller: controller)
        case .design: DesignTab(controller: controller)
        case .transitions: TransitionsTab(controller: controller)
        case .animations: AnimationsTab(controller: controller)
        case .slideShow: SlideShowTab(controller: controller)
        case .review: ReviewTab(controller: controller)
        case .view: ViewTab(controller: controller)
        case .shapeFormat: ShapeFormatTab(controller: controller)
        case .pictureFormat: PictureFormatTab(controller: controller)
        case .tableDesign: TableDesignTab(controller: controller)
        case .tableLayout: TableLayoutTab(controller: controller)
        case .chartDesign: ChartDesignTab(controller: controller)
        case .playback: PlaybackTab(controller: controller)
        }
    }
}

private struct RibbonTabButton: View {
    let title: String
    let isSelected: Bool
    var contextual = false
    let action: () -> Void
    let onDoubleClick: () -> Void
    @State private var hovering = false

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
            .foregroundStyle(contextual ? Theme.accentColor : (isSelected ? Color.primary : Color.primary.opacity(0.78)))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hovering && !isSelected ? Color.primary.opacity(0.07) : contextual ? Theme.accentColor.opacity(0.08) : .clear)
            )
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(isSelected ? Theme.accentColor : .clear)
                    .frame(height: 3)
                    .padding(.horizontal, 10)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2, perform: onDoubleClick)
            .onTapGesture(count: 1, perform: action)
            .onHover { hovering = $0 }
            .accessibilityElement()
            .accessibilityLabel(title)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction(.default, action)
    }
}

/// A small caption under a ribbon group.
struct RibbonCaption: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
    }
}

/// A group with its caption underneath, like PowerPoint's.
struct CaptionedGroup<Content: View>: View {
    let title: String
    var showsDivider = true
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 3) {
                HStack(alignment: .center, spacing: 2) { content() }
                    .frame(maxHeight: .infinity)
                RibbonCaption(title: title)
            }
            .padding(.vertical, 4)
            if showsDivider {
                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 1, height: 70)
                    .padding(.horizontal, 7)
            }
        }
    }
}

/// A horizontally scrolling gallery of preview tiles, with a menu for more.
struct RibbonGallery<Item: Identifiable, Tile: View>: View {
    let items: [Item]
    var height: CGFloat = 62
    @ViewBuilder let tile: (Item) -> Tile

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(items) { item in tile(item) }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: height)
        .frame(maxWidth: 520)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
    }
}

/// A selectable tile in a gallery.
struct GalleryTile<Label: View>: View {
    var isSelected = false
    var help: String
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label()
                .padding(3)
                .background(RoundedRectangle(cornerRadius: 5).fill(isSelected ? Theme.accentColor.opacity(0.18) : hovering ? Color.primary.opacity(0.08) : .clear))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(isSelected ? Theme.accentColor : .clear, lineWidth: 1.5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}
