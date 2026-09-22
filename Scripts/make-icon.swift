// make-icon.swift — NTFS Manager 앱 아이콘을 그려 PNG(1024)로 출력
// 사용: swift Scripts/make-icon.swift /path/to/AppIcon-1024.png
import AppKit

let size: CGFloat = 1024
let outPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "AppIcon-1024.png"

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { fatalError() }

let rect = CGRect(x: 0, y: 0, width: size, height: size)
ctx.clear(rect)

// --- Big Sur 스타일 squircle 배경 ---
let inset: CGFloat = 40
let iconRect = rect.insetBy(dx: inset, dy: inset)
let squircle = NSBezierPath(roundedRect: iconRect,
                            xRadius: size * 0.225, yRadius: size * 0.225)

// 다크 블루 그라디언트 배경
let bgGrad = NSGradient(colors: [
    NSColor(red: 0.16, green: 0.24, blue: 0.42, alpha: 1),
    NSColor(red: 0.07, green: 0.11, blue: 0.24, alpha: 1),
])!
bgGrad.draw(in: squircle, angle: -90)

// 은은한 상단 하이라이트
ctx.saveGState()
squircle.addClip()
let hl = NSGradient(colors: [
    NSColor.white.withAlphaComponent(0.18),
    NSColor.white.withAlphaComponent(0),
])!
hl.draw(in: NSBezierPath(rect: CGRect(x: inset, y: size * 0.6,
                                      width: size - inset * 2, height: size * 0.38)),
        angle: -90)
ctx.restoreGState()

// --- HDD 플래터 (디스크) ---
let cx = size / 2, cy = size * 0.60
let platterR = size * 0.30

let platterRect = CGRect(x: cx - platterR, y: cy - platterR,
                         width: platterR * 2, height: platterR * 2)
let platter = NSBezierPath(ovalIn: platterRect)

// 플래터 금속 그라디언트
let metal = NSGradient(colors: [
    NSColor(red: 0.88, green: 0.90, blue: 0.94, alpha: 1),
    NSColor(red: 0.55, green: 0.60, blue: 0.70, alpha: 1),
])!
metal.draw(in: platter, angle: -45)

// 플래터 테두리
NSColor(white: 0.15, alpha: 0.9).setStroke()
platter.lineWidth = size * 0.008
platter.stroke()

// 플래터 링 (트랙 느낌)
for scale in [0.86, 0.72, 0.58] as [CGFloat] {
    let r = platterR * scale
    let ring = NSBezierPath(ovalIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
    NSColor(white: 0.35, alpha: 0.35).setStroke()
    ring.lineWidth = size * 0.004
    ring.stroke()
}

// 허브(중심 스핀들)
let hubR = platterR * 0.30
let hub = NSBezierPath(ovalIn: CGRect(x: cx - hubR, y: cy - hubR,
                                      width: hubR * 2, height: hubR * 2))
let hubGrad = NSGradient(colors: [
    NSColor(red: 0.75, green: 0.78, blue: 0.85, alpha: 1),
    NSColor(red: 0.40, green: 0.44, blue: 0.54, alpha: 1),
])!
hubGrad.draw(in: hub, angle: 90)
NSColor(white: 0.15, alpha: 0.8).setStroke()
hub.lineWidth = size * 0.006
hub.stroke()

// 읽기 암 (액추에이터) — 우하단 피벗에서 플래터 가장자리를 향한 쐐기 형태
let pivot = NSPoint(x: cx + platterR * 0.92, y: cy - platterR * 0.92)
let tip   = NSPoint(x: cx + platterR * 0.28, y: cy - platterR * 0.28)
let arm = NSBezierPath()
arm.move(to: NSPoint(x: tip.x - size * 0.014, y: tip.y + size * 0.014))
arm.line(to: NSPoint(x: tip.x + size * 0.014, y: tip.y - size * 0.014))
arm.line(to: NSPoint(x: pivot.x + size * 0.045, y: pivot.y + size * 0.010))
arm.line(to: NSPoint(x: pivot.x + size * 0.010, y: pivot.y + size * 0.045))
arm.close()
NSColor(red: 0.62, green: 0.66, blue: 0.74, alpha: 1).setFill()
arm.fill()
NSColor(white: 0.15, alpha: 0.6).setStroke()
arm.lineWidth = size * 0.004
arm.stroke()

// 피벗 베어링
let pivR = size * 0.038
let pivotCircle = NSBezierPath(ovalIn: CGRect(x: pivot.x - pivR, y: pivot.y - pivR,
                                             width: pivR * 2, height: pivR * 2))
let pivGrad = NSGradient(colors: [
    NSColor(red: 0.80, green: 0.83, blue: 0.89, alpha: 1),
    NSColor(red: 0.45, green: 0.49, blue: 0.58, alpha: 1),
])!
pivGrad.draw(in: pivotCircle, angle: 90)
NSColor(white: 0.15, alpha: 0.7).setStroke()
pivotCircle.lineWidth = size * 0.005
pivotCircle.stroke()
let pivDotR = pivR * 0.35
NSColor(white: 0.12, alpha: 0.9).setFill()
NSBezierPath(ovalIn: CGRect(x: pivot.x - pivDotR, y: pivot.y - pivDotR,
                            width: pivDotR * 2, height: pivDotR * 2)).fill()

// --- "NTFS" 텍스트 ---
let font = NSFont.systemFont(ofSize: size * 0.16, weight: .heavy)
let attrs: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor.white,
]
let text = "NTFS"
let textSize = (text as NSString).size(withAttributes: attrs)
let textRect = CGRect(x: (size - textSize.width) / 2,
                      y: size * 0.115,
                      width: textSize.width, height: textSize.height)
// 텍스트 그림자
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.008),
              blur: size * 0.012, color: NSColor.black.withAlphaComponent(0.5).cgColor)
(text as NSString).draw(in: textRect, withAttributes: attrs)
ctx.restoreGState()

image.unlockFocus()

// PNG 저장
guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { fatalError("PNG 인코딩 실패") }
try png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
