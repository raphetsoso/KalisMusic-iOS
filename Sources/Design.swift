import SwiftUI
import UIKit
import MediaPlayer

// Identité visuelle de Kalis : à plat, sans arrondis (sauf les très petits rayons d'Android),
// icônes vectorielles identiques à celles de l'appli Android, inspiration « Musique » iOS 7-9.

extension Theme {
    static let iosBg = Color(red: 239 / 255, green: 239 / 255, blue: 244 / 255)       // #EFEFF4
    static let pressed = Color(red: 217 / 255, green: 217 / 255, blue: 217 / 255)     // #D9D9D9
    static let searchBg = Color(red: 228 / 255, green: 233 / 255, blue: 229 / 255)
}

/// Icône vectorielle (SVG repris des drawables Android), teintée.
struct Icon: View {
    let name: String
    var size: CGFloat = 24
    var color: Color = Theme.accent
    init(_ name: String, size: CGFloat = 24, color: Color = Theme.accent) {
        self.name = name
        self.size = size
        self.color = color
    }
    var body: some View {
        Image(name)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundColor(color)
    }
}

struct Hairline: View {
    var color: Color = Theme.separator
    var body: some View {
        Rectangle().fill(color).frame(height: 0.5)
    }
}

struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(configuration.isPressed ? Theme.pressed : Color.clear)
    }
}

struct PinkButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 22)
                .frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accent))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Barre de titre (52 dp)

struct TitleBar<Leading: View>: View {
    let title: String
    var search: Binding<String>? = nil
    var center: AnyView? = nil
    let leading: Leading
    @State private var searching = false
    @FocusState private var focused: Bool

    init(_ title: String, search: Binding<String>? = nil, center: AnyView? = nil,
         @ViewBuilder leading: () -> Leading) {
        self.title = title
        self.search = search
        self.center = center
        self.leading = leading()
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if let c = center {
                    c
                } else {
                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 96)
                }
                HStack(spacing: 0) {
                    leading
                    Spacer()
                    if let s = search {
                        Button {
                            searching.toggle()
                            if searching {
                                DispatchQueue.main.async { focused = true }
                            } else {
                                s.wrappedValue = ""
                                focused = false
                            }
                        } label: {
                            Icon("ic_search", size: 24, color: Theme.accent)
                                .frame(width: 52, height: 52)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 52)
            if let s = search, searching {
                HStack(spacing: 8) {
                    Icon("ic_search", size: 18, color: Theme.gray)
                    TextField("Rechercher", text: s)
                        .focused($focused)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.system(size: 16))
                }
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.searchBg))
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            Hairline()
        }
        .background(Theme.barBg.ignoresSafeArea(edges: .top))
    }
}

extension TitleBar where Leading == EmptyView {
    init(_ title: String, search: Binding<String>? = nil) {
        self.init(title, search: search) { EmptyView() }
    }
}

/// Barre des écrans empilés : bouton « Retour » à gauche, titre centré.
struct PageBar: View {
    let title: String
    var search: Binding<String>? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TitleBar(title, search: search) {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 0) {
                    Icon("ic_chevron_left", size: 28, color: Theme.accent)
                    Text("Retour").font(.system(size: 16)).foregroundColor(Theme.accent)
                }
                .padding(.leading, 6)
                .frame(height: 52)
            }
            .buttonStyle(.plain)
        }
    }
}

/// Enveloppe d'un onglet : pile de navigation sans barre système + barre de titre Android.
struct TabScreen<Leading: View, Content: View>: View {
    let title: String
    var search: Binding<String>? = nil
    var center: AnyView? = nil
    let leading: Leading
    let content: Content

    init(_ title: String, search: Binding<String>? = nil, center: AnyView? = nil,
         @ViewBuilder leading: () -> Leading, @ViewBuilder content: () -> Content) {
        self.title = title
        self.search = search
        self.center = center
        self.leading = leading()
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TitleBar(title, search: search, center: center) { leading }
                content
            }
            .background(Color.white)
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

extension TabScreen where Leading == EmptyView {
    init(_ title: String, search: Binding<String>? = nil, @ViewBuilder content: () -> Content) {
        self.init(title, search: search, leading: { EmptyView() }, content: content)
    }
}

// MARK: - Barre d'onglets (52 dp)

struct KTabBar: View {
    @Binding var tab: Int
    let showStore: Bool

    private struct Item { let tag: Int; let label: String; let icon: String; let iconOn: String }
    private var items: [Item] {
        var l: [Item] = [Item(tag: 0, label: "Pour vous", icon: "ic_heart", iconOn: "ic_heart_filled")]
        if showStore { l.append(Item(tag: 1, label: "KalisStore", icon: "ic_bag", iconOn: "ic_bag_filled")) }
        l.append(Item(tag: 2, label: "Radio", icon: "ic_radio", iconOn: "ic_radio"))
        l.append(Item(tag: 3, label: "Import", icon: "ic_import", iconOn: "ic_import"))
        l.append(Item(tag: 4, label: "Ma musique", icon: "ic_note", iconOn: "ic_note"))
        return l
    }

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: 0) {
                ForEach(items, id: \.tag) { it in
                    Button {
                        tab = it.tag
                    } label: {
                        VStack(spacing: 1) {
                            Icon(tab == it.tag ? it.iconOn : it.icon, size: 26,
                                 color: tab == it.tag ? Theme.accent : Theme.gray)
                            Text(it.label)
                                .font(.system(size: 10))
                                .foregroundColor(tab == it.tag ? Theme.accent : Theme.gray)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(Theme.barBg.ignoresSafeArea(edges: .bottom))
    }
}

// MARK: - Contrôle segmenté (Android : 176 × 26, rayon 6 aux extrémités)

struct KSegmented: View {
    let labels: [String]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<labels.count, id: \.self) { i in
                Button {
                    selection = i
                } label: {
                    Text(labels[i])
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(selection == i ? .white : Theme.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(selection == i ? Theme.accent : Color.clear)
                }
                .buttonStyle(.plain)
                if i < labels.count - 1 {
                    Rectangle().fill(Theme.accent).frame(width: 1)
                }
            }
        }
        .frame(width: 176, height: 26)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.accent, lineWidth: 1))
    }
}

// MARK: - Lignes (72 dp, pochette 56 dp, séparateur décalé de 86)

struct RowLabel<Art: View>: View {
    let art: Art
    let title: String
    let sub: String
    var highlight = false

    var body: some View {
        HStack(spacing: 14) {
            art.frame(width: 56, height: 56).clipped()
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 18))
                    .foregroundColor(highlight ? Theme.accent : .black)
                    .lineLimit(1)
                Text(sub)
                    .font(.system(size: 15))
                    .foregroundColor(Theme.gray)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 16)
        .frame(height: 72)
        .contentShape(Rectangle())
    }
}

struct RowShell<Main: View, Trailing: View>: View {
    let main: Main
    let trailing: Trailing

    init(@ViewBuilder main: () -> Main, @ViewBuilder trailing: () -> Trailing) {
        self.main = main()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 0) {
            main
            trailing
        }
        .overlay(Hairline().padding(.leading, 86), alignment: .bottom)
    }
}

extension RowShell where Trailing == EmptyView {
    init(@ViewBuilder main: () -> Main) {
        self.init(main: main, trailing: { EmptyView() })
    }
}

struct SectionHeader: View {
    let text: String
    var big = false
    init(_ t: String, big: Bool = false) { text = t; self.big = big }
    var body: some View {
        Text(text)
            .font(.system(size: big ? 22 : 13, weight: big ? .bold : .semibold))
            .foregroundColor(big ? .black : Theme.gray)
            .padding(.horizontal, 16)
            .padding(.top, big ? 18 : 14)
            .padding(.bottom, big ? 8 : 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ShuffleRow: View {
    var label = "Aléatoire"
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Icon("ic_shuffle", size: 24, color: Theme.accent)
                Text(label).font(.system(size: 18)).foregroundColor(Theme.accent)
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .contentShape(Rectangle())
            .overlay(Hairline().padding(.leading, 16), alignment: .bottom)
        }
        .buttonStyle(RowPressStyle())
    }
}

// MARK: - Curseur de volume (piste fine, curseur rond rose)

struct SystemVolumeSlider: UIViewRepresentable {
    private static func solid(_ color: UIColor, height: CGFloat) -> UIImage {
        let r = UIGraphicsImageRenderer(size: CGSize(width: 2, height: height))
        let img = r.image { ctx in
            color.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 2, height: height))
        }
        return img.resizableImage(withCapInsets: .zero, resizingMode: .stretch)
    }

    private static func thumb(_ d: CGFloat) -> UIImage {
        let r = UIGraphicsImageRenderer(size: CGSize(width: d, height: d))
        return r.image { _ in
            UIColor(Theme.accent).setFill()
            UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: d, height: d)).fill()
        }
    }

    func makeUIView(context: Context) -> MPVolumeView {
        let v = MPVolumeView(frame: .zero)
        v.showsRouteButton = false
        v.setMinimumVolumeSliderImage(Self.solid(UIColor(Theme.accent), height: 2), for: .normal)
        v.setMaximumVolumeSliderImage(Self.solid(UIColor(white: 0.78, alpha: 1), height: 2), for: .normal)
        v.setVolumeThumbImage(Self.thumb(14), for: .normal)
        return v
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}
