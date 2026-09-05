//
//  DesignTokens.swift
//  Halo-fi-IOS
//
//  Centralized color and gradient tokens. Phase 2-7 of the SSI
//  rules-engine rebuild reads from here so new cards (earn-room,
//  BWE/IRWE confirmation sheet, §1619(b) banner, ABLE settings row)
//  stay visually consistent with the existing SSI hero cards.
//
//  When refactoring BudgetView's inline `Color(red:...)` values,
//  swap them for the matching token below — every value here is
//  taken verbatim from the existing inline usages so the visual
//  output is byte-for-byte identical.
//

import SwiftUI

enum DesignTokens {

    // MARK: - Adaptive surfaces & text (Light / Dark)
    //
    // HaloFi was built dark-only: ~70 hardcoded `Color.black` backgrounds
    // and ~260 hardcoded `.white` text colors. That looked right in Dark but
    // broke under System-following-Light (adaptive system chrome flipped to
    // light while the hardcoded blacks stayed dark → mismatched screens).
    //
    // These tokens map onto Apple's semantic UIColors. In DARK they resolve
    // to the exact near-black / white the app already used, so the dark
    // appearance is unchanged; in LIGHT they flip correctly. Replace
    // hardcoded `Color.black` screen backgrounds and `.white` primary text
    // with these — NOT white/black that sits on a colored fill (a gradient
    // button label stays `.white` in both modes).
    enum Surface {
        /// Primary screen background. Dark: #000 (matches old Color.black),
        /// Light: #FFF.
        static let background = Color(uiColor: .systemBackground)
        /// Cards / elevated rows over the background.
        static let secondary = Color(uiColor: .secondarySystemBackground)
        /// Inputs, chips, the third elevation level.
        static let tertiary = Color(uiColor: .tertiarySystemBackground)
        /// Grouped-list background (Form / settings screens).
        static let grouped = Color(uiColor: .systemGroupedBackground)
    }

    enum Text {
        /// Primary text. Dark: white (matches old `.white`), Light: black.
        static let primary = Color(uiColor: .label)
        /// Secondary text — replaces `.white.opacity(0.8...0.85)`.
        /// Light mode uses a deeper shade than Apple's secondaryLabel: on a
        /// card (#F2F2F7) the system value is ~3.3:1, below WCAG AA for the
        /// row lines that carry most of the app's meaning. 0.78 alpha ≈ 4.7:1.
        static let secondary = Color(uiColor: UIColor { t in
            t.userInterfaceStyle == .dark ? .secondaryLabel : UIColor(red: 60/255, green: 60/255, blue: 67/255, alpha: 0.78)
        })
        /// De-emphasized text — replaces `.white.opacity(~0.6)`.
        static let tertiary = Color(uiColor: .tertiaryLabel)
    }

    enum Fill {
        static let separator = Color(uiColor: .separator)
        /// Translucent fill for tracks / subtle chips on any background.
        static let subtle = Color(uiColor: .quaternarySystemFill)
    }

    /// Money +/- and pass/fail states, legible in both modes (system
    /// green/red already adapt their luminance per appearance).
    enum Status {
        static let positive = Color(uiColor: .systemGreen)
        static let negative = Color(uiColor: .systemRed)
    }

    /// Tone colors used as TEXT (not fills). System orange/green/red on a
    /// light card fall below WCAG AA for small text (2.1–2.9:1), so light
    /// mode uses deeper shades (≥ 4.6:1 on #F2F2F7); dark mode keeps the
    /// bright system colors, which pass on near-black.
    enum ToneText {
        static let watch = Color(uiColor: UIColor { t in
            t.userInterfaceStyle == .dark ? .systemOrange : UIColor(red: 0.60, green: 0.30, blue: 0.00, alpha: 1)
        })
        static let act = Color(uiColor: UIColor { t in
            t.userInterfaceStyle == .dark ? .systemRed : UIColor(red: 0.78, green: 0.06, blue: 0.10, alpha: 1)
        })
        static let positive = Color(uiColor: UIColor { t in
            t.userInterfaceStyle == .dark ? .systemGreen : UIColor(red: 0.09, green: 0.47, blue: 0.24, alpha: 1)
        })
        static let neutral = Color(uiColor: .secondaryLabel)
    }

    // MARK: - SSI hero cards

    enum SSI {
        /// Navy gradient used by every SSI hero card background.
        /// Source: BudgetView.swift inline gradient at the resource /
        /// income / next-deposit cards.
        static let heroGradientColors: [Color] = [
            Color(red: 0.16, green: 0.22, blue: 0.48),
            Color(red: 0.10, green: 0.14, blue: 0.32),
        ]

        static var heroGradient: LinearGradient {
            LinearGradient(
                colors: heroGradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        // MARK: Subtext on navy background
        // The existing cards use white at 0.75 / 0.70 opacity. The
        // `bright` token bumps to 0.92 for any text that needs
        // higher contrast on the navy gradient (the user flagged the
        // current shade as too dim for comfortable reading).
        static let subtextPrimary: Color = .white.opacity(0.75)
        static let subtextSecondary: Color = .white.opacity(0.70)
        static let subtextBright: Color = .white.opacity(0.92)

        // MARK: Status chip colors (over / warning / safe)
        // Solid status colors — used as foreground on the hero card
        // body and in alert banners.
        static let statusOver: Color = Color(red: 1.00, green: 0.45, blue: 0.35)
        static let statusWarning: Color = Color(red: 1.00, green: 0.65, blue: 0.25)
        static let statusSafe: Color = Color(red: 0.40, green: 0.85, blue: 0.55)
        static let statusBehind: Color = Color(red: 1.00, green: 0.65, blue: 0.25)
        static let statusAhead: Color = Color(red: 0.40, green: 0.85, blue: 0.55)
        static let statusNeutral: Color = Color(red: 0.95, green: 0.80, blue: 0.35)

        // Status chip background (status color at 30% opacity on navy).
        static let chipBgOver: Color = statusOver.opacity(0.30)
        static let chipBgWarning: Color = statusWarning.opacity(0.30)
        static let chipBgSafe: Color = statusSafe.opacity(0.30)
        static let chipBgNeutral: Color = .white.opacity(0.20)

        // Status chip foreground (lighter shade for readable text on chip bg).
        static let chipFgOver: Color = Color(red: 1.00, green: 0.78, blue: 0.72)
        static let chipFgWarning: Color = Color(red: 1.00, green: 0.86, blue: 0.62)
        static let chipFgSafe: Color = Color(red: 0.74, green: 0.96, blue: 0.81)

        // Generic translucent fill used for progress-bar tracks and pill
        // backgrounds that overlay the navy gradient.
        static let translucentFill: Color = .white.opacity(0.22)
        static let translucentFillSubtle: Color = .white.opacity(0.18)
    }
}

// MARK: - Terse adaptive accessors
//
// Shorthand for the DesignTokens.Surface / Text tokens above so migrating
// a hardcoded color is a one-word swap: `Color.black` → `.haloBackground`,
// `.white` (primary text) → `.haloTextPrimary`.
extension Color {
    /// Primary screen background (Dark #000 / Light #FFF). Replaces
    /// `Color.black` used as a screen or ZStack background.
    static let haloBackground = DesignTokens.Surface.background
    /// Card / elevated surface over the background.
    static let haloSecondaryBackground = DesignTokens.Surface.secondary
    /// Input / chip surface.
    static let haloTertiaryBackground = DesignTokens.Surface.tertiary
    /// Grouped-list background.
    static let haloGroupedBackground = DesignTokens.Surface.grouped
    /// Primary text (Dark white / Light black). Replaces `.white` used as
    /// primary text ON the screen background — NOT on a colored fill.
    static let haloTextPrimary = DesignTokens.Text.primary
    /// Secondary text — replaces `.white.opacity(~0.85)`.
    static let haloTextSecondary = DesignTokens.Text.secondary
    /// De-emphasized text — replaces `.white.opacity(~0.6)`.
    static let haloTextTertiary = DesignTokens.Text.tertiary
    /// Hairline separators.
    static let haloSeparator = DesignTokens.Fill.separator
    /// Positive / negative money + status, adaptive in both modes.
    static let haloPositive = DesignTokens.Status.positive
    static let haloNegative = DesignTokens.Status.negative
}

// MARK: - Type (2026-09-05 style pass)
//
// One "number voice" for the app: rounded, heavy display figures; rounded
// bold titles. Body text stays the system face for legibility.
extension Font {
    /// Display figures (balances, totals). Scales with Dynamic Type via
    /// the caller's @ScaledMetric.
    static func haloDisplay(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .rounded)
    }
    /// Card verdicts ("Balance", "On pace").
    static let haloTitle = Font.system(.title3, design: .rounded).weight(.bold)
    /// Row titles.
    static let haloRowTitle = Font.system(.headline, design: .rounded)
}

// MARK: - Shared surfaces (2026-09-05 style pass)

/// The icon tile at the head of every row and attention card: a small
/// two-stop gradient of the tint with a white glyph and a soft colored
/// shadow. Decorative — always hidden from VoiceOver.
struct HaloIconTile: View {
    let icon: String
    let tint: Color
    @ScaledMetric(relativeTo: .headline) private var size: CGFloat = 44

    init(icon: String, tint: Color) {
        self.icon = icon
        self.tint = tint
    }

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [tint, tint.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .shadow(color: tint.opacity(0.35), radius: 6, y: 3)
            .accessibilityHidden(true)
    }
}

/// Card surface: continuous corners, hairline border, optional tint wash
/// (deadline cards) so state is felt and also written.
struct HaloCardModifier: ViewModifier {
    var tint: Color? = nil
    var radius: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    Color.haloSecondaryBackground
                    if let tint {
                        LinearGradient(colors: [tint.opacity(0.16), tint.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder((tint ?? Color.haloSeparator).opacity(tint == nil ? 0.5 : 0.45), lineWidth: tint == nil ? 0.5 : 1)
            )
    }
}

extension View {
    func haloCard(tint: Color? = nil, radius: CGFloat = 18) -> some View {
        modifier(HaloCardModifier(tint: tint, radius: radius))
    }
}

/// The tab's title drawn inside the scroll content (Liam, 2026-09-05: the
/// large-title navigation bar left too much empty space above "Money").
/// The root hides its navigation bar; pushed screens keep theirs. Hidden
/// from VoiceOver by default because the tab bar already names the tab
/// and the screen summary header is the first thing read.
struct TabTitle: View {
    let text: String
    var spokenAsHeader: Bool = false

    init(_ text: String, spokenAsHeader: Bool = false) {
        self.text = text
        self.spokenAsHeader = spokenAsHeader
    }

    var body: some View {
        Text(text)
            .font(.system(.largeTitle, design: .rounded).weight(.bold))
            .foregroundColor(.haloTextPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
            .padding(.bottom, 2)
            .accessibilityHidden(!spokenAsHeader)
            .accessibilityAddTraits(.isHeader)
    }
}
