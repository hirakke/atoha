import SwiftUI

/// ウィジェット・ライブアクティビティの見本（DEBUG の `-atohaWidgetGallery`、2枚目は `-atohaGalleryPage 2`）。
/// 本物と同じビューを実寸で並べ、シミュレータの画面写真で確かめる。
struct WidgetGalleryView: View {
    private var page: Int {
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-atohaGalleryPage"), i + 1 < a.count { return Int(a[i + 1]) ?? 1 }
        return 1
    }

    private let item = WidgetSnapshot.sample.display(at: .now)
    private let focus = WidgetSnapshot.sampleFocus.display(at: .now)

    var body: some View {
        ScrollView {
            if page == 2 { lockPage } else if page == 3 { mediumPage } else { homePage }
        }
        .background(Color(hex: page == 2 ? 0x1F2A44 : 0x8EA8DE).ignoresSafeArea())
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: ホーム画面

    private var homePage: some View {
        VStack(spacing: 18) {
            HStack(spacing: 20) {
                card { SmallNowWidgetView(display: item) } background: { SmallNowBackground(display: item) }
                card { SmallCaptureWidgetView() } background: { WaterBackground() }
            }
            card(width: 360) { MediumNowWidgetView(display: item) } background: { MediumNowBackground(display: item) }
            HStack(spacing: 20) {
                card { SmallNowWidgetView(display: focus) } background: { SmallNowBackground(display: focus) }
                card { SmallNowWidgetView(display: .empty) } background: { SmallNowBackground(display: .empty) }
            }
            HStack(spacing: 20) {
                card { SmallNowWidgetView(display: .done(text: "母に電話")) } background: { SmallNowBackground(display: .done(text: "")) }
                tinted { SmallNowWidgetView(display: item, accented: true) }
            }
        }
        .padding(.top, 70).padding(.bottom, 40)
        .frame(maxWidth: .infinity)
        .background(LinearGradient(colors: [Color(hex: 0x8EA8DE), Color(hex: 0xB9C9EC), Color(hex: 0xEBD3D3)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private var mediumPage: some View {
        VStack(spacing: 18) {
            card(width: 360) { MediumNowWidgetView(display: focus) } background: { MediumNowBackground(display: focus) }
            card(width: 360) { MediumNowWidgetView(display: .empty) } background: { MediumNowBackground(display: .empty) }
            card(width: 360) { MediumNowWidgetView(display: .done(text: "母に電話")) } background: { MediumNowBackground(display: .done(text: "")) }
            tinted(width: 360) { MediumNowWidgetView(display: item, accented: true) }
            tinted { SmallCaptureWidgetView(accented: true) }
        }
        .padding(.top, 70).padding(.bottom, 40)
        .frame(maxWidth: .infinity)
    }

    private func card<C: View, B: View>(width: CGFloat = 170, @ViewBuilder _ content: () -> C, @ViewBuilder background: () -> B) -> some View {
        content()
            .frame(width: width, height: 170)
            .background(background())
            .clipShape(.rect(cornerRadius: 24))
            .shadow(color: K.navy.opacity(0.16), radius: 9, y: 6)
    }

    private func tinted<C: View>(width: CGFloat = 170, @ViewBuilder _ content: () -> C) -> some View {
        content()
            .frame(width: width, height: 170)
            .background(RoundedRectangle(cornerRadius: 24).fill(.white.opacity(0.22)))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.5), lineWidth: 1))
            .background(RoundedRectangle(cornerRadius: 24).fill(LinearGradient(colors: [Color(hex: 0x5E77AE), Color(hex: 0x9DB3DE)], startPoint: .topLeading, endPoint: .bottomTrailing)))
    }

    // MARK: ロック画面とライブアクティビティ

    private var lockPage: some View {
        VStack(spacing: 16) {
            LockInlineView(display: item).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
            Text("9:41").font(.system(size: 92, weight: .bold)).foregroundStyle(.white)
            HStack(spacing: 14) {
                LockRectangularView(display: item)
                    .frame(width: 158, height: 68)
                    .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.16)))
                LockCircularView()
                    .frame(width: 68, height: 68)
                    .background(Circle().fill(.white.opacity(0.16)))
            }
            HStack(spacing: 14) {
                LockRectangularView(display: focus)
                    .frame(width: 158, height: 68)
                    .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.16)))
                LockRectangularView(display: .empty)
                    .frame(width: 158, height: 68)
                    .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.16)))
            }
            LiveBannerView(text: "母に電話", start: .now.addingTimeInterval(-754), ended: nil)
                .background(.white)
                .clipShape(.rect(cornerRadius: 26))
                .padding(.horizontal, 14)
            HStack(spacing: 12) {
                HStack {
                    IslandCompactLeading()
                    Spacer()
                    IslandCompactTrailing(start: .now.addingTimeInterval(-754), ended: nil)
                }
                .padding(.horizontal, 14)
                .frame(width: 250, height: 37)
                .background(Capsule().fill(.black))
                IslandMinimal().frame(width: 37, height: 37).background(Circle().fill(.black))
            }
            IslandDoneView()
                .padding(.horizontal, 14)
                .frame(width: 250, height: 37)
                .background(Capsule().fill(.black))
            VStack(spacing: 12) {
                IslandExpandedRow(text: "母に電話", start: .now.addingTimeInterval(-754), ended: nil)
                IslandButtons()
            }
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 16)
            .background(RoundedRectangle(cornerRadius: 40).fill(.black))
            .padding(.horizontal, 14)
        }
        .padding(.top, 60).padding(.bottom, 40)
        .frame(maxWidth: .infinity)
        .background(LinearGradient(colors: [Color(hex: 0x1F2A44), Color(hex: 0x34436B), Color(hex: 0x6E5A7A)],
                                   startPoint: .top, endPoint: .bottom))
    }
}
