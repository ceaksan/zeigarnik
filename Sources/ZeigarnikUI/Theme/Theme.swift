import AppKit
import SwiftUI
import ZeigarnikKit

public enum Theme {
    public static let bg = color(light: 0xececec, dark: 0x1b1b1d)
    public static let window = color(light: 0xffffff, dark: 0x232325)
    public static let side = color(light: 0xf5f5f7, dark: 0x2a2a2d)
    public static let line = color(light: 0xe3e3e6, dark: 0x3a3a3d)
    public static let text = color(light: 0x1d1d1f, dark: 0xf2f2f4)
    public static let muted = color(light: 0x86868b, dark: 0x9a9aa0)
    public static let accent = color(light: 0x0a84ff, dark: 0x0a84ff)
    public static let accentSoft = color(light: 0xe5f0ff, dark: 0x16304f)
    public static let warn = color(light: 0xc2410c, dark: 0xfb923c)
    public static let danger = color(light: 0xd70015, dark: 0xff453a)
    public static let warnSoft = color(light: 0xfff1e6, dark: 0x3a2416)
    public static let ok = color(light: 0x1a7f37, dark: 0x4ade80)
    public static let okSoft = color(light: 0xe7f6ec, dark: 0x163222)
    public static let chips: [Color] = [
        color(light: 0xdbeafe, dark: 0x1e3a5f),
        color(light: 0xfce7f3, dark: 0x4a1d38),
        color(light: 0xdcfce7, dark: 0x173d26),
        color(light: 0xfef3c7, dark: 0x4a3a10),
        color(light: 0xede9fe, dark: 0x33275a),
        color(light: 0xe0f2fe, dark: 0x123a52),
    ]
    public static let live = color(light: 0x28c840, dark: 0x28c840)
    public static let star = color(light: 0xf5a524, dark: 0xf5a524)
    public static let today = color(light: 0xff3b30, dark: 0xff3b30)
    public static let onAccent = Color.white
    public static let specTrack = line

    public static let body = Font.system(size: 13)
    public static let small = Font.system(size: 11.5)
    public static let caption = Font.system(size: 11, weight: .semibold)
    public static let title = Font.system(size: 17, weight: .semibold)
    public static let chip = Font.system(size: 11)
    public static let dayTotal = Font.system(size: 10.5)
    public static let keyValue = Font.system(size: 12.5)

    public static let rowPadding = EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
    public static let inspectorPadding: CGFloat = 14
    public static let keyColumnWidth: CGFloat = 110
    public static let corner: CGFloat = 8
    public static let tagCorner: CGFloat = 5
    public static let chipCorner: CGFloat = 4

    private static func color(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(
                srgbRed: CGFloat((value >> 16) & 0xff) / 255,
                green: CGFloat((value >> 8) & 0xff) / 255,
                blue: CGFloat(value & 0xff) / 255,
                alpha: 1
            )
        }))
    }
}
