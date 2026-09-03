import SwiftUI

/// Единая система оформления Voicekeep — светлый, воздушный вид документа
/// (жанр современных ИИ-диктофонов). Все цвета/шрифты/отступы/радиусы
/// заводятся здесь, чтобы экраны не расходились друг с другом.
///
/// Цвета заданы через динамический провайдер (light/dark), а не через
/// Asset Catalog, чтобы держать всю палитру в одном файле, который проще
/// поддерживать в коде.
enum DS {

    // MARK: - Colors

    enum Color {
        /// Фон экрана: чистый белый в светлой теме, #0E0E10 в тёмной.
        static let background = SwiftUI.Color.dynamic(
            light: SwiftUI.Color(hex: 0xFFFFFF),
            dark: SwiftUI.Color(hex: 0x0E0E10)
        )

        /// Фон приподнятых поверхностей (карточек, полей ввода) — почти
        /// не отличим от фона в светлой теме (мы не используем карточки),
        /// но явно выделен в тёмной, чтобы тема не читалась как инверсия.
        static let surface = SwiftUI.Color.dynamic(
            light: SwiftUI.Color(hex: 0xFAFAFA),
            dark: SwiftUI.Color(hex: 0x17171A)
        )

        /// Основной текст.
        static let textPrimary = SwiftUI.Color.dynamic(
            light: SwiftUI.Color(hex: 0x111114),
            dark: SwiftUI.Color(hex: 0xF4F4F5)
        )
        /// Вторичный текст (даты, подписи, метаданные).
        static let textSecondary = SwiftUI.Color.dynamic(
            light: SwiftUI.Color(hex: 0x6B6B72),
            dark: SwiftUI.Color(hex: 0x9A9AA2)
        )
        /// Третичный текст (плейсхолдеры, самые тихие подписи).
        static let textTertiary = SwiftUI.Color.dynamic(
            light: SwiftUI.Color(hex: 0x9A9AA2),
            dark: SwiftUI.Color(hex: 0x6B6B72)
        )

        /// Спокойный индиго — единственный акцент приложения.
        static let accent = SwiftUI.Color(hex: 0x5B5BD6)

        /// Пастельные подсветки — только для статусов, тегов, выделений.
        /// Не использовать для крупных плоскостей.
        static let mint = SwiftUI.Color.dynamic(
            light: SwiftUI.Color(hex: 0xD8F3E6),
            dark: SwiftUI.Color(hex: 0x1B3A2C)
        )
        static let lavender = SwiftUI.Color.dynamic(
            light: SwiftUI.Color(hex: 0xE8E2FB),
            dark: SwiftUI.Color(hex: 0x2A2440)
        )
        static let sky = SwiftUI.Color.dynamic(
            light: SwiftUI.Color(hex: 0xDDEBFB),
            dark: SwiftUI.Color(hex: 0x1C2E42)
        )

        /// Красный записи — узнаваемо, не трогаем.
        static let record = SwiftUI.Color(hex: 0xE5484D)

        /// Волосяной разделитель: 8% непрозрачности поверх основного цвета —
        /// сам становится тоньше и заметнее в тёмной теме благодаря белому.
        static let hairline = SwiftUI.Color.primary.opacity(0.08)
    }

    // MARK: - Typography

    enum Typography {
        /// Заголовок экрана (крупный "Voicekeep" на главном экране).
        static let screenTitle = Font.system(size: 34, weight: .bold)
        /// Заголовок записи на экране записи.
        static let recordingTitle = Font.system(size: 28, weight: .bold)
        /// Тело — расшифровка, конспект.
        static let body = Font.system(size: 16, weight: .regular)
        /// Вторичный текст — даты, метаданные, подписи.
        static let secondary = Font.system(size: 13, weight: .regular)
        /// Таймкоды — моноширинные цифры.
        static let timecode = Font.system(size: 12, weight: .regular).monospacedDigit()
        /// Название записи в строке списка.
        static let rowTitle = Font.system(size: 17, weight: .semibold)
        /// Мелкие пастельные пилюли (теги, метки говорящего).
        static let pill = Font.system(size: 12, weight: .medium)
    }

    // MARK: - Layout

    enum Spacing {
        /// Базовый горизонтальный отступ экрана.
        static let horizontal: CGFloat = 20
        /// Отступ между крупными блоками.
        static let block: CGFloat = 24
    }

    enum Radius {
        static let pill: CGFloat = 999
        static let field: CGFloat = 14
        static let card: CGFloat = 16
    }
}

extension SwiftUI.Color {
    /// Провайдер, различающий light/dark без Asset Catalog — так вся
    /// палитра остаётся в одном файле. Named `dynamic` (not `init(light:dark:)`)
    /// to avoid an ambiguity with MarkdownUI's own `Color.init(light:dark:)`.
    static func dynamic(light: SwiftUI.Color, dark: SwiftUI.Color) -> SwiftUI.Color {
        SwiftUI.Color(UIColor(light: UIColor(light), dark: UIColor(dark)))
    }

    /// Цвет из hex-литерала вида 0xRRGGBB.
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

private extension UIColor {
    convenience init(light: UIColor, dark: UIColor) {
        self.init { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        }
    }
}

/// Волосяной разделитель — вместо `Divider()`, который на iOS рисует более
/// заметную линию, чем нужно для документного, воздушного вида.
struct Hairline: View {
    var body: some View {
        DS.Color.hairline
            .frame(height: 0.5)
    }
}

/// Мелкая пастельная пилюля — теги, метки говорящего, статусы.
struct PastelPill: View {
    let text: String
    var tint: SwiftUI.Color = DS.Color.lavender
    var foreground: SwiftUI.Color = DS.Color.textPrimary

    var body: some View {
        Text(text)
            .font(DS.Typography.pill)
            .foregroundStyle(foreground)
            .padding(.vertical, 3)
            .padding(.horizontal, 8)
            .background(tint, in: Capsule())
    }
}
