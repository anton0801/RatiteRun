//
//  SupportView.swift
//  RatiteRun
//
//  Обращение в поддержку, не выходя из приложения. Веб-форма на
//  ratiterun.online/support-form делает то же самое для тех, у кого
//  приложение не запускается.
//

import SwiftUI
import UIKit

struct SupportView: View {
    @EnvironmentObject var store: AppStore

    @AppStorage("supportName") private var name = ""
    @AppStorage("supportEmail") private var email = ""

    @State private var subject = SupportSubject.problem
    @State private var message = ""
    @State private var sending = false
    @State private var sent = false
    @State private var toast: String? = nil
    @State private var fieldError: String? = nil

    enum SupportSubject: String, CaseIterable, Identifiable {
        case question = "Question about using the app"
        case problem  = "Something is broken"
        case sync     = "My flocks are missing or out of sync"
        case privacy  = "Data, privacy or account deletion"
        case figures  = "Species figures look wrong"
        case feature  = "Feature request"
        case other    = "Something else"

        var id: String { rawValue }

        var short: String {
            switch self {
            case .question: return "Question"
            case .problem:  return "Problem"
            case .sync:     return "Sync"
            case .privacy:  return "Privacy"
            case .figures:  return "Figures"
            case .feature:  return "Idea"
            case .other:    return "Other"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if sent {
                    successCard
                } else {
                    IntroText("Tell us what happened — we reply by email.", icon: "lifepreserver.fill")
                    selfHelpCard
                    formCard
                    sendButton
                    footer
                }
            }
            .padding(20).padding(.bottom, 80)
        }
        .screenBackground()
        .navigationBarTitle("Support", displayMode: .inline)
        .toast($toast)
    }

    // MARK: Секции

    private var selfHelpCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Quick answers", systemImage: "bolt.fill")

                hint("Flocks missing on another device?",
                     "An anonymous account belongs to one device. Link Sign in with Apple on both.")
                hint("Changes not saving?",
                     "Check the strip at the top. “Offline” means edits are held here until you have signal.")
                hint("Need your data?",
                     "Settings → Backup & Data → Export Data. No request needed.")
                hint("Health or welfare question?",
                     "We can't answer those — call a specialist ratite vet.")
            }
        }
    }

    private func hint(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(AppFont.rounded(14, .semibold)).foregroundColor(Palette.textPrimary)
            Text(body).font(AppFont.caption).foregroundColor(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var formCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Your message", systemImage: "envelope.fill")

                AppTextField(title: "Name", text: $name,
                             placeholder: "Who are we replying to?", systemImage: "person.fill")
                AppTextField(title: "Email", text: $email,
                             placeholder: "you@example.com", systemImage: "at")
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)

                Text("Topic").font(AppFont.caption).foregroundColor(Palette.textSecondary)
                FlowChips(SupportSubject.allCases) { option in
                    Chip(title: option.short, selected: subject == option, accent: Palette.action) {
                        subject = option
                    }
                }

                Text("What happened?").font(AppFont.caption).foregroundColor(Palette.textSecondary)
                TextEditor(text: $message)
                    .frame(height: 150)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 11).fill(Palette.bgSoft))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11)
                            .stroke(fieldError == nil ? Palette.border : Palette.danger, lineWidth: 1)
                    )

                if let fieldError {
                    Text(fieldError).font(AppFont.caption).foregroundColor(Palette.danger)
                }

                Text("Please don't include passwords or payment details — we never need them.")
                    .font(AppFont.caption).foregroundColor(Palette.textDisabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var sendButton: some View {
        VStack(spacing: 10) {
            PrimaryButton(title: sending ? "Sending…" : "Send Message",
                          systemImage: sending ? "hourglass" : "paperplane.fill") {
                guard !sending else { return }
                Task { await send() }
            }
            .disabled(sending)
            .opacity(sending ? 0.6 : 1)

            GhostButton(title: "Open the web form instead", systemImage: "safari") {
                WebLinks.open(.support)
            }
        }
    }

    private var successCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 24)).foregroundColor(Palette.norm)
                    Text("Message sent")
                        .font(AppFont.rounded(18, .bold)).foregroundColor(Palette.textPrimary)
                }
                Text("We have it. Expect a reply at \(email) within about two working days.")
                    .font(AppFont.body).foregroundColor(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                GhostButton(title: "Write another message", systemImage: "arrow.counterclockwise") {
                    message = ""
                    sent = false
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().background(Palette.divider)
            Text("Sending this stores your name, email and message so we can reply.")
                .font(AppFont.caption).foregroundColor(Palette.textDisabled)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: { WebLinks.open(.privacy) }) {
                Text("Privacy Policy & Terms")
                    .font(AppFont.rounded(13, .semibold)).foregroundColor(Palette.primaryActive)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    // MARK: Отправка

    private func send() async {
        fieldError = nil

        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)

        // Проверяем локально, чтобы не гонять заведомо плохой запрос —
        // сервер валидирует те же правила повторно.
        guard trimmedMessage.count >= 10 else {
            fieldError = "Please describe the problem in at least 10 characters."
            return
        }
        guard email.contains("@"), email.contains(".") else {
            fieldError = "That email address doesn't look right — we reply there."
            return
        }

        sending = true
        defer { sending = false }

        do {
            _ = try await RatiteAPI.shared.submitSupportRequest(
                name: name.isEmpty ? "Ratite Run user" : name,
                email: email,
                subject: subject.rawValue,
                message: trimmedMessage,
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
                deviceInfo: "\(UIDevice.current.model) / iOS \(UIDevice.current.systemVersion)"
            )
            sent = true
        } catch let error as APIError {
            toast = error.userMessage
        } catch {
            toast = "Could not send — check your connection"
        }
    }
}

// MARK: - Ссылки на сайт

/// Адреса публичных страниц. Берутся из Info.plist, чтобы дев-сборка
/// не вела на боевой домен.
enum WebLinks {
    enum Page: String {
        case privacy = "/privacy-terms"
        case support = "/support-form"
        case home    = "/"
    }

    static var base: String {
        (Bundle.main.object(forInfoDictionaryKey: "RatiteWebBaseURL") as? String)
            ?? "https://ratiterun.online"
    }

    static func url(_ page: Page) -> URL? {
        URL(string: base + page.rawValue)
    }

    static func open(_ page: Page) {
        guard let url = url(page) else { return }
        UIApplication.shared.open(url)
    }
}
