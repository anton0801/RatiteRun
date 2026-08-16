//
//  SyncStatusBar.swift
//  RatiteRun
//
//  Полоска состояния синхронизации. Появляется только когда есть что сказать —
//  в норме экран выглядит ровно как раньше.
//

import SwiftUI

struct SyncStatusBar: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        Group {
            switch store.syncState {
            case .idle:
                EmptyView()

            case .loading:
                bar(text: "Loading your flocks…", color: Palette.primary, spinning: true)

            case .syncing:
                bar(text: "Syncing…", color: Palette.primary, spinning: true)

            case .offline:
                bar(text: "Offline — showing saved data", color: Palette.attention,
                    symbol: "wifi.slash")

            case .failed(let message):
                bar(text: message, color: Palette.danger,
                    symbol: "exclamationmark.triangle.fill", retry: true)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: store.syncState)
    }

    private func bar(text: String, color: Color, symbol: String? = nil,
                     spinning: Bool = false, retry: Bool = false) -> some View {
        HStack(spacing: 8) {
            if spinning {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: color))
                    .scaleEffect(0.7)
            } else if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(color)
            }

            Text(text)
                .font(AppFont.caption)
                .foregroundColor(Palette.textSecondary)
                .lineLimit(1)

            Spacer()

            if retry {
                Button("Retry") { Task { await store.refresh() } }
                    .font(AppFont.rounded(12, .semibold))
                    .foregroundColor(color)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(color.opacity(0.10))
        .overlay(Rectangle().fill(color.opacity(0.25)).frame(height: 1), alignment: .bottom)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Тост о синхронизации

/// Показывает разовые сообщения из store.syncMessage — конфликт версий,
/// завершённый перенос данных и т.п.
struct SyncMessageToast: ViewModifier {
    @EnvironmentObject var store: AppStore
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if visible, let message = store.syncMessage {
                    Text(message)
                        .font(AppFont.rounded(13, .semibold))
                        .foregroundColor(Palette.onPrimary)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Capsule().fill(Palette.primaryActive))
                        .padding(.bottom, 110)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .onChange(of: store.syncMessage) { message in
                guard message != nil else { return }
                withAnimation { visible = true }

                Task {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    withAnimation { visible = false }
                    store.syncMessage = nil
                }
            }
    }
}

extension View {
    func syncMessageToast() -> some View {
        modifier(SyncMessageToast())
    }
}
