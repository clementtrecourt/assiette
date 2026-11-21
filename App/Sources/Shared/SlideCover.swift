import SwiftUI
import UIKit

// Full-page presentations that slide in from the right edge (and leave the same way) instead of
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
    static let enterDuration = 0.26
    /// Wait before the slide starts (about one frame, see `SlideCoverHost`).
    static let startDelay = 0.02
    static let enter = Animation.spring(duration: enterDuration, bounce: 0)
    static let exitDuration = 0.2
    /// Leaves fast from the start (an ease-out page that lingers feels slow).
    static let exit = Animation.timingCurve(0.3, 0, 0.6, 1, duration: exitDuration)

    /// Lowers the keyboard while the page leaves (a field left focused must not hold it up).
    static func endEditing() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// Runs `body` once the exit slide is over. A timer rather than the animation completion:
    /// the completion can be skipped (e.g. when the keyboard moves during the slide), which
    /// left an invisible cover on screen swallowing every touch.
    static func afterExit(_ body: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + exitDuration + 0.02, execute: body)
    }

    /// Waits until the page presented by `cover` has finished sliding in (at least `minimum`
    /// seconds). Fields focused on appear wait for it: bringing the keyboard up mid-slide (its
    /// first appearance blocks the main thread) makes the slide stutter.
    static func untilSettled(_ cover: SlideCoverState?, minimum: Double = 0.05) async {
        let wait = max(minimum, cover?.settledAt.timeIntervalSinceNow ?? 0)
        try? await Task.sleep(for: .seconds(wait))
    }

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
    /// When the current entrance slide ends.
    var settledAt = Date.distantPast

    /// Called right before the page is presented (still off screen).
    func prepareEntrance() {
        isVisible = false
        isHiding = false
        // One frame for the first render, then the slide.
        settledAt = .now + SlideCoverMotion.startDelay + SlideCoverMotion.enterDuration + 0.03
    }
}

private struct SlideCoverStateKey: EnvironmentKey {
    static let defaultValue: SlideCoverState? = nil
}

extension EnvironmentValues {
    /// The slide-in page this view lives in, if any (see `SlideCoverMotion.untilSettled`).
    var slideCover: SlideCoverState? {
        get { self[SlideCoverStateKey.self] }
        set { self[SlideCoverStateKey.self] = newValue }
    }
}

/// Draws the page off screen on the right, slides it in on appear, dims what is behind.
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
                    .environment(\.slideCover, state)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .background(Theme.background.ignoresSafeArea())
                    .offset(x: state.isVisible ? 0 : proxy.size.width + proxy.safeAreaInsets.trailing)
            }
        }
        .presentationBackground(.clear)
        .onAppear {
            guard !state.isVisible else { return }
            state.isHiding = false
            // Start one frame later, once the first (heaviest) render is committed: started in
            // the same frame, that render eats the first frames of the slide. A busy main
            // thread only delays the start, it no longer shows as a stutter mid-slide.
            DispatchQueue.main.asyncAfter(deadline: .now() + SlideCoverMotion.startDelay) {
                guard !state.isHiding else { return }
                withAnimation(SlideCoverMotion.enter) { state.isVisible = true }
            }
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
            .onAppear {
                if isPresented && !isShown {
                    state.prepareEntrance()
                    SlideCoverMotion.instantly { isShown = true }
                }
            }
            .onChange(of: isPresented) { _, presented in
                if presented {
                    guard !isShown else { return }
                    state.prepareEntrance()
                    SlideCoverMotion.instantly { isShown = true }
                } else {
                    hide()
                }
            }
    }

    private func hide() {
        guard isShown, !state.isHiding else { return }
        state.isHiding = true
        SlideCoverMotion.endEditing()
        withAnimation(SlideCoverMotion.exit) { state.isVisible = false }
        SlideCoverMotion.afterExit {
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
            .onAppear {
                if let item, shown == nil {
                    state.prepareEntrance()
                    SlideCoverMotion.instantly { shown = item }
                }
            }
            .onChange(of: item?.id) { _, id in
                if let item {
                    if shown == nil {
                        state.prepareEntrance()
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
        SlideCoverMotion.endEditing()
        withAnimation(SlideCoverMotion.exit) { state.isVisible = false }
        SlideCoverMotion.afterExit {
            SlideCoverMotion.instantly { shown = nil }
            if item != nil { item = nil }
            state.isHiding = false
        }
    }
}
