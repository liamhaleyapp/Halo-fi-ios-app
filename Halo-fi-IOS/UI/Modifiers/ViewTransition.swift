//
//  ViewTransition.swift
//  Halo-fi-IOS
//
//  Reusable view transition styles for consistent animations throughout the app.
//

import SwiftUI

enum TransitionStyle {
    case fade
    case slideForward    // trailing → leading (step forward)
    case slideBack       // leading → trailing (step back)
    case slideUp         // bottom → top (overlays/modals)
    case scaleAndFade    // subtle scale + opacity
}

struct ViewTransitionModifier: ViewModifier {
    let style: TransitionStyle

    func body(content: Content) -> some View {
        content.transition(makeTransition())
    }

    private func makeTransition() -> AnyTransition {
        switch style {
        case .fade:
            return .opacity
        case .slideForward:
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        case .slideBack:
            return .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        case .slideUp:
            return .move(edge: .bottom).combined(with: .opacity)
        case .scaleAndFade:
            return .scale(scale: 0.95).combined(with: .opacity)
        }
    }
}

extension View {
    func viewTransition(_ style: TransitionStyle = .fade) -> some View {
        modifier(ViewTransitionModifier(style: style))
    }
}
