//
//  OnboardingFlowView.swift
//  WithU
//
//  Three explainer pages followed by the permissions page.
//

import SwiftUI

struct OnboardingFlowView: View {
    @Environment(AppModel.self) private var model
    @State private var page = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(art: .logo,
                       title: "Travel Solo, Together",
                       body: "Explore Italy and share the moments with your circle.",
                       button: "Continue"),
        OnboardingPage(art: .symbol("bell.badge.fill"),
                       title: "We've Got Your Back",
                       body: "Stop for a while and we'll check in. Your circle hears only if you need them.",
                       button: "Continue"),
        OnboardingPage(art: .symbol("person.2.fill"),
                       title: "Pick Your People",
                       body: "Add friends and family to a circle.",
                       button: "Get Started")
    ]

    var body: some View {
        ZStack {
            ScreenBackground()
            if page < pages.count {
                explainer
                    .transition(.opacity)
            } else {
                PermissionsView {
                    model.hasCompletedOnboarding = true
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .overlay(alignment: .topLeading) {
            // Back to the previous page, including from the permissions page,
            // which had no way back before.
            if page > 0 {
                Button {
                    page -= 1
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .tint(Theme.ink)
                .padding(.leading, 16)
                .padding(.top, 8)
                .accessibilityLabel("Back")
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: page)
    }

    private var explainer: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, content in
                    OnboardingPageView(page: content)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: 6) {
                ForEach(pages.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? Theme.primary : Theme.primary.opacity(0.25))
                        .frame(width: index == page ? 18 : 6, height: 6)
                }
            }
            .padding(.bottom, 28)
            .accessibilityHidden(true)

            Button(pages[min(page, pages.count - 1)].button) {
                page += 1
            }
            .buttonStyle(.primary)
            .padding(.horizontal, 36)

            Button("Skip") {
                page = pages.count
            }
            .font(.footnote)
            .foregroundStyle(Theme.inkSecondary)
            .padding(.top, 14)
            .opacity(page < pages.count - 1 ? 1 : 0)
            .disabled(page >= pages.count - 1)
            .padding(.bottom, 24)
        }
    }
}

struct OnboardingPage: Hashable {
    enum Art: Hashable {
        /// The WithU logo, shown on the first page.
        case logo
        case symbol(String)
    }
    var art: Art
    var title: String
    var body: String
    var button: String
}

struct OnboardingPageView: View {
    var page: OnboardingPage

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            switch page.art {
            case .logo:
                Image("WithULogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 112, height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .shadow(color: Theme.primary.opacity(0.25), radius: 12, y: 6)
                    .accessibilityLabel("WithU")
            case .symbol(let name):
                SymbolBadge(systemImage: name)
            }
            Text(page.title)
                .font(.title2.bold())
                .foregroundStyle(Theme.ink)
            Text(page.body)
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 44)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    OnboardingFlowView()
        .environment(AppModel.shared)
}
