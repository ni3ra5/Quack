import SwiftUI
import MediaRemoteAdapter

/// The below-notch media panel: album art + title/artist + transport controls
/// when open and something is playing; a near-invisible hover target otherwise.
struct NotchMediaView: View {
    @ObservedObject var model: NotchMediaViewModel

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { model.onHoverChange?($0) }
    }

    @ViewBuilder
    private var content: some View {
        if model.isOpen {
            HStack(spacing: 12) {
                artwork
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.track?.payload.title ?? "Nothing playing")
                        .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(model.track?.payload.artist ?? "")
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                if model.track != nil {
                    HStack(spacing: 14) {
                        button("backward.fill") { model.onPrevious?() }
                        button((model.track?.payload.isPlaying ?? false) ? "pause.fill" : "play.fill") { model.onToggle?() }
                        button("forward.fill") { model.onNext?() }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, model.contentTopInset + 8)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(NotchShape().fill(Color.black))
            .foregroundStyle(.white)
        } else {
            Color.black.opacity(0.001)   // hover target only (below the notch)
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let art = model.track?.payload.artwork {
            Image(nsImage: art).resizable().aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28).clipShape(RoundedRectangle(cornerRadius: 5))
        } else {
            RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.12))
                .frame(width: 28, height: 28)
                .overlay(Image(systemName: "music.note").font(.system(size: 12)).foregroundStyle(.secondary))
        }
    }

    private func button(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Image(systemName: symbol).font(.system(size: 13))
            .contentShape(Rectangle()).onTapGesture(perform: action)
    }
}
