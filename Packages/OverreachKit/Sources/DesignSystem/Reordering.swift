import SwiftUI

// Touch-and-hold, then drag, to reorder vertically stacked items. Domain-free: the caller names items by any
// hashable id, shows a normal view while idle and a `ReorderCardList` while reordering, and decides what a drop does.

/// Where a dragged item is while the finger is down.
public struct ReorderDrag<ID: Hashable & Sendable>: Equatable, Sendable {
    public let id: ID
    /// Ids of the items in their current order.
    public let order: [ID]
    public let from: Int
    /// The place the item takes if released now.
    public let target: Int
    /// Finger position in the reordering space.
    public let fingerY: CGFloat
    /// Vertical room one item takes, to slide the neighbours.
    let slot: CGFloat
    /// Where the dragged item sits in the layout, before any offset.
    let layoutMidY: CGFloat

    /// How far the dragged card moves to sit under the finger.
    var dragOffset: CGFloat { fingerY - layoutMidY }

    /// How far a neighbour slides to make room for the dragged item.
    func shift(of id: ID) -> CGFloat {
        guard let index = order.firstIndex(of: id) else { return 0 }
        if from < target, index > from, index <= target { return -slot }
        if target < from, index >= target, index < from { return slot }
        return 0
    }
}

/// Where each handle is, in the reordering space.
private struct ReorderHandle<ID: Hashable & Sendable>: Hashable, Sendable {
    let id: ID
    /// A card of `ReorderCardList` (true) or the view pressed to start reordering (false).
    let isCard: Bool
}

private struct ReorderFrames<ID: Hashable & Sendable>: PreferenceKey {
    static var defaultValue: [ReorderHandle<ID>: CGRect] { [:] }

    static func reduce(value: inout [ReorderHandle<ID>: CGRect], nextValue: () -> [ReorderHandle<ID>: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private let reorderSpace = "overreach.reorder"

extension View {
    /// Marks the view a person presses to start reordering `id`. Apply it after any `offset`, so it reports the
    /// layout position, not the dragged one.
    public func reorderHandle<ID: Hashable & Sendable>(_ id: ID) -> some View {
        reorderFrame(ReorderHandle(id: id, isCard: false))
    }

    fileprivate func reorderFrame<ID: Hashable & Sendable>(_ handle: ReorderHandle<ID>) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ReorderFrames<ID>.self, value: [handle: proxy.frame(in: .named(reorderSpace))]
                )
            }
        }
    }

    /// Reorders by touching a handle (`reorderHandle`, or a card while `isCollapsed`) for 0.35 s and dragging
    /// without lifting the finger. The gesture runs next to scrolling: moving before the hold ends scrolls.
    ///
    /// - Parameters:
    ///   - isCollapsed: whether the cards of `ReorderCardList` are on screen, so they are the handles.
    ///   - drag: set while an item is being dragged, for `ReorderCardList` to draw.
    ///   - onBegin: the hold ended on `id`: show the cards (when not already shown).
    ///   - onEnd: the finger lifted; the drag, when the item was lifted, says where it was dropped.
    public func reordersOnLongPress<ID: Hashable & Sendable>(
        isCollapsed: Bool,
        drag: Binding<ReorderDrag<ID>?>,
        onBegin: @escaping (ID) -> Void,
        onEnd: @escaping (ReorderDrag<ID>?) -> Void
    ) -> some View {
        modifier(ReorderModifier(isCollapsed: isCollapsed, drag: drag, onBegin: onBegin, onEnd: onEnd))
    }
}

/// What one touch is doing. A reference, so the hold timer and the gesture see the same values.
private final class ReorderTouch<ID: Hashable & Sendable> {
    var start = CGPoint.zero
    var fingerY: CGFloat = 0
    var id: ID?
    var hasBegun = false
    var hold: Task<Void, Never>?
}

private struct ReorderModifier<ID: Hashable & Sendable>: ViewModifier {
    static var holdDuration: Duration { .milliseconds(350) }
    /// Movement that turns the touch into a scroll before the hold ends.
    static var slop: CGFloat { 10 }

    let isCollapsed: Bool
    @Binding var drag: ReorderDrag<ID>?
    let onBegin: (ID) -> Void
    let onEnd: (ReorderDrag<ID>?) -> Void
    @State private var frames: [ReorderHandle<ID>: CGRect] = [:]
    @State private var touch = ReorderTouch<ID>()

    init(
        isCollapsed: Bool, drag: Binding<ReorderDrag<ID>?>, onBegin: @escaping (ID) -> Void,
        onEnd: @escaping (ReorderDrag<ID>?) -> Void
    ) {
        self.isCollapsed = isCollapsed
        _drag = drag
        self.onBegin = onBegin
        self.onEnd = onEnd
    }

    func body(content: Content) -> some View {
        content
            .coordinateSpace(name: reorderSpace)
            .onPreferenceChange(ReorderFrames<ID>.self) { newFrames in
                frames = newFrames
                refresh()
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(reorderSpace))
                    .onChanged(changed)
                    .onEnded(ended)
            )
            .onDisappear { finish(commit: false) }
    }

    private func changed(_ value: DragGesture.Value) {
        touch.fingerY = value.location.y
        if touch.hold == nil && !touch.hasBegun {
            touch.start = value.startLocation
            touch.id = frames.first { $0.key.isCard == isCollapsed && $0.value.contains(value.startLocation) }?.key.id
            if touch.id != nil {
                touch.hold = Task { @MainActor in
                    try? await Task.sleep(for: Self.holdDuration)
                    guard !Task.isCancelled else { return }
                    begin()
                }
            }
        }
        if touch.hasBegun {
            refresh()
        } else if hypot(value.location.x - touch.start.x, value.location.y - touch.start.y) > Self.slop {
            touch.hold?.cancel()
            touch.id = nil
        }
    }

    private func ended(_ value: DragGesture.Value) {
        touch.fingerY = value.location.y
        refresh()
        finish(commit: true)
    }

    private func begin() {
        guard let id = touch.id else { return }
        touch.hasBegun = true
        onBegin(id)
        refresh()
    }

    private func finish(commit: Bool) {
        let result = commit ? drag : nil
        let hadBegun = touch.hasBegun
        touch.hold?.cancel()
        touch = ReorderTouch<ID>()
        drag = nil
        if hadBegun { onEnd(result) }
    }

    /// Recomputes the drag from the finger and the cards, which also move when the list scrolls.
    private func refresh() {
        guard touch.hasBegun, let id = touch.id else { return }
        let cards = frames.filter { $0.key.isCard }
            .map { (id: $0.key.id, frame: $0.value) }
            .sorted { $0.frame.minY < $1.frame.minY }
        guard let from = cards.firstIndex(where: { $0.id == id }) else { return }
        let target = cards.enumerated().filter { $0.offset != from && $0.element.frame.midY < touch.fingerY }.count
        let slot = cards.count > 1 ? abs(cards[1].frame.minY - cards[0].frame.minY) : cards[from].frame.height
        let next = ReorderDrag(
            id: id, order: cards.map(\.id), from: from, target: target, fingerY: touch.fingerY, slot: slot,
            layoutMidY: cards[from].frame.midY
        )
        if next != drag { drag = next }
    }
}

/// The items as compact cards, filling the space of the list they replace while reordering. The dragged card
/// follows the finger and the others slide out of its way; `reordersOnLongPress` owns the gesture.
public struct ReorderCardList<Item: Identifiable, Card: View>: View where Item.ID: Hashable & Sendable {
    private struct Metrics: Equatable {
        var offset: CGFloat = 0
        var maxOffset: CGFloat = 0
        var viewport: CGFloat = 0
    }

    /// Distance from the top or bottom edge where dragging starts to scroll, and the fastest scroll per frame.
    private static var edgeZone: CGFloat { 80 }
    private static var maxStep: CGFloat { 14 }

    private let items: [Item]
    private let drag: ReorderDrag<Item.ID>?
    private let card: (Item) -> Card
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var position = ScrollPosition()
    @State private var metrics = Metrics()
    @State private var fingerY: CGFloat?

    public init(items: [Item], drag: ReorderDrag<Item.ID>?, @ViewBuilder card: @escaping (Item) -> Card) {
        self.items = items
        self.drag = drag
        self.card = card
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: Spacing.small) {
                ForEach(items) { item in
                    let isDragged = drag?.id == item.id
                    let shift = drag?.shift(of: item.id) ?? 0
                    card(item)
                        .padding(Spacing.medium)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: Radius.tile))
                        .contentShape(Rectangle())
                        .scaleEffect(isDragged ? 1.03 : 1)
                        .shadow(color: .black.opacity(isDragged ? 0.25 : 0), radius: isDragged ? 10 : 0, y: 4)
                        .offset(y: isDragged ? (drag?.dragOffset ?? 0) : shift)
                        // The dragged card follows the finger; neighbours slide (not with Reduce Motion).
                        .animation(reduceMotion ? nil : .spring(duration: 0.25), value: shift)
                        .animation(reduceMotion ? nil : .spring(duration: 0.25), value: isDragged)
                        .zIndex(isDragged ? 1 : 0)
                        .reorderFrame(ReorderHandle(id: item.id, isCard: true))
                }
            }
            .padding(Spacing.medium)
        }
        .scrollDisabled(drag != nil)
        .scrollPosition($position)
        .onScrollGeometryChange(for: Metrics.self) { geometry in
            let content = geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom
            return Metrics(
                offset: geometry.contentOffset.y,
                maxOffset: max(0, content - geometry.containerSize.height),
                viewport: geometry.containerSize.height
            )
        } action: { _, new in
            metrics = new
        }
        .onChange(of: drag?.fingerY, initial: true) { _, newY in fingerY = newY }
        .task(id: drag != nil) { await autoScroll() }
    }

    /// Scrolls while the finger rests near the top or bottom edge, faster the closer it is.
    private func autoScroll() async {
        var offset = metrics.offset
        while !Task.isCancelled, let finger = fingerY {
            let top = Self.edgeZone - finger
            let bottom = finger - (metrics.viewport - Self.edgeZone)
            let speed = top > 0 ? -min(top, Self.edgeZone) : (bottom > 0 ? min(bottom, Self.edgeZone) : 0)
            if speed != 0 {
                offset = min(max(offset + speed / Self.edgeZone * Self.maxStep, 0), metrics.maxOffset)
                position.scrollTo(y: offset)
            } else {
                offset = metrics.offset
            }
            try? await Task.sleep(for: .milliseconds(16))
        }
    }
}
