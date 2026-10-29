import AppKit
import CoreText
import SwiftUI

/// Sistema visual de la web (app/globals.css): bordes negros rectos, sombra dura
/// desplazada, Oswald en mayúsculas y acento gris azulado.
enum Theme {
    static let bg = Color(hex: 0xD8D8DC)
    static let ink = Color(hex: 0x1C1C1A)
    static let muted = Color(hex: 0x6B6B66)
    static let line = Color(hex: 0xE2E2DE)
    static let surface = Color.white
    static let panel = Color(hex: 0xFAFAF8)
    static let accent = Color(hex: 0x768693)
    static let accentInk = Color(hex: 0xF7F7F5)
    static let danger = Color(hex: 0x8B3A3A)
    static let hover = Color(hex: 0xF0F0EC)
    static let chip = Color(hex: 0xEFEFEB)
    static let field = Color(hex: 0xFBFBFA)
    static let fieldFocus = Color(hex: 0xB0B0AA)
    static let buttonShadow = Color(hex: 0x555555)
    static let cardShadow = Color(hex: 0x888888)

    /// Oswald (variable) con fallback al sistema si no se pudo registrar.
    static func font(_ size: CGFloat = 14.5, _ weight: Font.Weight = .regular) -> Font {
        .custom("Oswald", size: size).weight(weight)
    }

    static func mono(_ size: CGFloat = 13.4) -> Font {
        .system(size: size, design: .monospaced)
    }

    /// Registra Oswald.ttf: dentro de la .app está en Contents/Resources;
    /// con `swift run` / Xcode, en el bundle de recursos de SwiftPM.
    static func registerFonts() {
        guard let url = Bundle.main.url(forResource: "Oswald", withExtension: "ttf")
            ?? Bundle.module.url(forResource: "Oswald", withExtension: "ttf") else {
            print("[theme] Oswald.ttf no encontrado")
            return
        }
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            print("[theme] no se pudo registrar Oswald", error?.takeRetainedValue() as Any)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension View {
    /// `.scale-y-80`: el texto condensado verticalmente de la web.
    func squish() -> some View {
        scaleEffect(x: 1, y: 0.8)
    }

    /// Sombra dura desplazada (`box-shadow: 4px 4px 0 0`).
    func hardShadow(_ color: Color = Theme.cardShadow, offset: CGFloat = 4) -> some View {
        background(Rectangle().fill(color).offset(x: offset, y: offset))
    }
}

// MARK: - Botones (.btn-hard)

struct HardButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, danger }

    var kind: Kind = .secondary
    var compact = false
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        HardButtonBody(configuration: configuration, kind: kind, compact: compact, fullWidth: fullWidth)
    }
}

private struct HardButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: HardButtonStyle.Kind
    let compact: Bool
    let fullWidth: Bool

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        let pressed = configuration.isPressed && isEnabled
        let active = hovering && isEnabled
        configuration.label
            .labelStyle(SquishedLabelStyle())
            .font(Theme.font(compact ? 12.5 : 14, .semibold))
            .textCase(.uppercase)
            .foregroundStyle(foreground)
            .padding(.horizontal, compact ? 10 : 14)
            .padding(.vertical, compact ? 5 : 8)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(background(active: active))
            .overlay(Rectangle().strokeBorder(.black, lineWidth: 1))
            .hardShadow(Theme.buttonShadow, offset: pressed ? 2 : 4)
            .scaleEffect(pressed ? 0.95 : active ? 1.05 : 1)
            .opacity(isEnabled ? (kind == .primary && active ? 0.92 : 1) : 0.4)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: pressed)
            .animation(.easeOut(duration: 0.12), value: active)
    }

    private var foreground: Color {
        switch kind {
        case .primary: Theme.accentInk
        case .secondary: Theme.ink
        case .danger: Theme.danger
        }
    }

    private func background(active: Bool) -> Color {
        switch kind {
        case .primary: Theme.accent
        case .secondary: active ? Theme.hover : .white
        case .danger: active ? Color(hex: 0xF8ECEC) : .white
        }
    }
}

/// Botón cuadrado de solo icono (cerrar, quitar archivo).
struct HardIconButtonStyle: ButtonStyle {
    var color: Color = Theme.ink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 26, height: 26)
            .background(.white)
            .overlay(Rectangle().strokeBorder(.black, lineWidth: 1))
            .hardShadow(Theme.buttonShadow, offset: configuration.isPressed ? 2 : 3)
            .contentShape(Rectangle())
    }
}

/// Enlace subrayado en mayúsculas ("Crear una", "Ver completo").
struct HardLinkStyle: ButtonStyle {
    var color: Color = Theme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(SquishedLabelStyle())
            .font(Theme.font(13, .semibold))
            .textCase(.uppercase)
            .underline()
            .foregroundStyle(color)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

/// Icono normal + título condensado (`scale-y-80` solo sobre el texto).
struct SquishedLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
            configuration.title.squish()
        }
    }
}

// MARK: - Campos

struct HardField: View {
    let placeholder: String
    @Binding var text: String
    var secure = false
    var contentType: NSTextContentType?
    var onSubmit: () -> Void = {}

    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if secure {
                SecureField("", text: $text, prompt: prompt)
            } else {
                TextField("", text: $text, prompt: prompt)
            }
        }
        .textFieldStyle(.plain)
        .textContentType(contentType)
        .font(Theme.font(14.5))
        .foregroundStyle(Theme.ink)
        .focused($focused)
        .onSubmit(onSubmit)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Theme.field)
        .overlay(Rectangle().strokeBorder(focused ? Theme.fieldFocus : Theme.line, lineWidth: 1))
    }

    private var prompt: Text {
        Text(placeholder.uppercased()).foregroundStyle(Theme.muted.opacity(0.6))
    }
}

/// Área de texto con el mismo estilo que los campos.
struct HardTextArea: View {
    let placeholder: String
    @Binding var text: String

    @FocusState private var focused: Bool

    var body: some View {
        TextEditor(text: $text)
            .scrollContentBackground(.hidden)
            .font(Theme.font(14.5))
            .foregroundStyle(Theme.ink)
            .focused($focused)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder.uppercased())
                        .font(Theme.font(14.5))
                        .foregroundStyle(Theme.muted.opacity(0.6))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
            .background(Theme.field)
            .overlay(Rectangle().strokeBorder(focused ? Theme.fieldFocus : Theme.line, lineWidth: 1))
    }
}

/// Etiqueta de campo: icono + texto en mayúsculas.
struct FieldLabel: View {
    let text: String
    var icon: String?

    var body: some View {
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon).font(.system(size: 11)) }
            Text(text).squish()
        }
        .font(Theme.font(12.8, .semibold))
        .textCase(.uppercase)
        .foregroundStyle(Theme.ink)
    }
}

// MARK: - Contenedores

/// Tarjeta de doble marco: blanco con borde + sombra dura, y un panel interior con borde.
struct HardCard<Content: View>: View {
    var inner: Color = .white
    var padding: CGFloat = 16
    var shadow = true
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(inner)
        .overlay(Rectangle().strokeBorder(.black, lineWidth: 1))
        .padding(6)
        .background(.white)
        .overlay(Rectangle().strokeBorder(.black, lineWidth: 1))
        .hardShadow(shadow ? Theme.cardShadow : .clear)
    }
}

/// Título de tarjeta ("CAMBIAR CONTRASEÑA").
struct CardTitle: View {
    let text: String
    var icon: String?
    var color: Color = Theme.ink

    var body: some View {
        HStack(spacing: 8) {
            if let icon { Image(systemName: icon).font(.system(size: 13, weight: .semibold)) }
            Text(text).squish()
        }
        .font(Theme.font(15.2, .bold))
        .textCase(.uppercase)
        .foregroundStyle(color)
    }
}

/// Texto secundario en mayúsculas.
struct MutedText: View {
    let text: String
    var size: CGFloat = 12.8

    var body: some View {
        Text(text)
            .font(Theme.font(size))
            .textCase(.uppercase)
            .foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Cuadrado con icono sobre el acento (marca, avatar).
struct IconTile: View {
    let systemImage: String
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Theme.accent)
    }
}

/// Pestañas rectangulares que se apoyan sobre la tarjeta de abajo.
struct HardTabs<ID: Hashable>: View {
    struct Tab: Identifiable {
        let id: ID
        let label: String
        var count: Int?
        var countColor: Color = Theme.ink
    }

    let tabs: [Tab]
    @Binding var selection: ID

    var body: some View {
        HStack(spacing: -1) {
            ForEach(tabs) { tab in
                let selected = tab.id == selection
                Button {
                    selection = tab.id
                } label: {
                    HStack(spacing: 6) {
                        Text(tab.label).squish()
                        if let count = tab.count, count > 0 {
                            Text("\(count)")
                                .font(Theme.font(11, .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .background(tab.countColor)
                        }
                    }
                    .font(Theme.font(13, selected ? .semibold : .regular))
                    .textCase(.uppercase)
                    .foregroundStyle(selected ? .white : Theme.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(selected ? Theme.accent : .white)
                    .overlay(Rectangle().strokeBorder(.black, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Caja de estado vacío con borde punteado.
struct EmptyBox<Actions: View>: View {
    let icon: String
    let title: String?
    let message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 26, weight: .light))
            if let title {
                Text(title).font(Theme.font(16.8, .bold)).textCase(.uppercase).foregroundStyle(Theme.ink).squish()
            }
            Text(message)
                .font(Theme.font(14))
                .textCase(.uppercase)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            actions.padding(.top, 4)
        }
        .foregroundStyle(Theme.muted)
        .padding(.horizontal, 20)
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
        .background(Theme.panel)
        .overlay(Rectangle().strokeBorder(.black, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }
}

/// Casilla cuadrada (compartir) o radio (encuesta) en el estilo de la web.
struct HardCheckRow<Label: View>: View {
    let checked: Bool
    var enabled = true
    let action: () -> Void
    @ViewBuilder var label: Label

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(checked ? .white : .clear)
                    .frame(width: 18, height: 18)
                    .background(checked ? Theme.accent : .white)
                    .overlay(Rectangle().strokeBorder(.black, lineWidth: 1))
                label
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }
}

/// Encabezado tipo modal de la web: barra de acento con título y botón cerrar.
struct HardModal<Content: View>: View {
    let title: String
    var subtitle: String?
    let onClose: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.font(16, .bold)).textCase(.uppercase).squish()
                    if let subtitle {
                        Text(subtitle).font(Theme.font(12)).textCase(.uppercase).opacity(0.85)
                    }
                }
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark") }
                    .buttonStyle(HardIconButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Theme.accent)
            .overlay(alignment: .bottom) { Rectangle().fill(.black).frame(height: 1) }

            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.panel)
        .overlay(Rectangle().strokeBorder(.black, lineWidth: 1))
        .padding(6)
        .background(.white)
        .overlay(Rectangle().strokeBorder(.black, lineWidth: 1))
        .environment(\.colorScheme, .light)
    }
}
