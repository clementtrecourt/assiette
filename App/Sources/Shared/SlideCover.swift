import SwiftUI

// Full-page presentations that slide in from the left edge (and leave the same way) instead of
// rising from the bottom. Drop-in for `.sheet` / `.fullScreenCover`: same bindings, `onDismiss`,
// and `@Environment(\.dismiss)` inside the content still closes it (with the slide).
// Half-height panels (presentationDetents) stay as bottom sheets.

extension View {
    func slideCover<Content: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil,
                                   @ViewBuilder content: @escaping () -> Content) -> some View {
        modifier(SlideCoverPresenter(isPresented: isPresented, onDismiss: onDismiss, cover: content))
    }

    func slideCover<Item: Identifiable, Content: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil,
                                                       @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        modifier(SlideCoverItemPresenter(item: item, onDismiss: onDismiss, cover: content))
    }
}

enum SlideCoverMotion {
    static let enter = Animation.smooth(duration: 0.34)
    static let exit = Animation.smooth(duration: 0.28)

    /// Runs `body` without any animation (the system cover must appear / vanish instantly:
    /// the slide is drawn by `SlideCoverHost`).
    static func instantly(_ body: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, body)
    }
}

/// Shared between the presenter and the presented host: is the page on screen.
final class SlideCoverState: ObservableObject {
    @Published var isVisible = false
    var isHiding = false
}

/// Draws the page off screen on the left, slides it in on appear, dims what is behind.
private struct SlideCoverHost<Content: View>: View {
    @ObservedObject var state: SlideCoverState
    let content: Content

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                    .opacity(state.isVisible ? 0.35 : 0)
                    .ignoresSafeArea()
                content
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .background(Theme.background.ignoresSafeArea())
                    .offset(x: state.isVisible ? 0 : -(proxy.size.width + proxy.safeAreaInsets.leading + 40))
            }
        }
        .presentationBackground(.clear)
        .onAppear {
            guard !state.isVisible else { return }
            state.isHiding = false
            withAnimation(SlideCoverMotion.enter) { state.isVisible = true }
        }
    }
}

private struct SlideCoverPresenter<Cover: View>: ViewModifier {
    @Binding var isPresented: Bool
    let onDismiss: (() -> Void)?
    let cover: () -> Cover

    @State private var isShown = false
    @StateObject private var state = SlideCoverState()

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: Binding(get: { isShown }, set: { if !$0 { hide() } }),
                             onDismiss: onDismiss) {
                SlideCoverHost(state: state, content: cover())
            }
            .onAppear { if isPresented && !isShown { SlideCoverMotion.instantly { isShown = true } } }
            .onChange(of: isPresented) { _, presented in
                if presented {
                    guard !isShown else { return }
                    state.isVisible = false
                    SlideCoverMotion.instantly { isShown = true }
                } else {
                    hide()
                }
            }
    }

    private func hide() {
        guard isShown, !state.isHiding else { return }
        state.isHiding = true
        withAnimation(SlideCoverMotion.exit) {
            state.isVisible = false
        } completion: {
            SlideCoverMotion.instantly { isShown = false }
            if isPresented { isPresented = false }
            state.isHiding = false
        }
    }
}

private struct SlideCoverItemPresenter<Item: Identifiable, Cover: View>: ViewModifier {
    @Binding var item: Item?
    let onDismiss: (() -> Void)?
    let cover: (Item) -> Cover

    @State private var shown: Item?
    @StateObject private var state = SlideCoverState()

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: Binding(get: { shown }, set: { if $0 == nil { hide() } else { shown = $0 } }),
                             onDismiss: onDismiss) { value in
                SlideCoverHost(state: state, content: cover(value))
            }
            .onAppear { if let item, shown == nil { SlideCoverMotion.instantly { shown = item } } }
            .onChange(of: item?.id) { _, id in
                if let item {
                    if shown == nil {
                        state.isVisible = false
                        SlideCoverMotion.instantly { shown = item }
                    } else if shown?.id != id, !state.isHiding {
                        SlideCoverMotion.instantly { shown = item }
                    }
                } else {
                    hide()
                }
            }
    }

    private func hide() {
        guard shown != nil, !state.isHiding else { return }
        state.isHiding = true
        withAnimation(SlideCoverMotion.exit) {
            state.isVisible = false
        } completion: {
            SlideCoverMotion.instantly { shown = nil }
            if item != nil { item = nil }
            state.isHiding = false
        }
    }
}
