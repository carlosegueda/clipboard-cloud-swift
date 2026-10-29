import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case add, history, about, settings

    var id: String { rawValue }

    var title: L {
        switch self {
        case .add: .navAdd
        case .history: .navHistory
        case .about: .navAbout
        case .settings: .navSettings
        }
    }

    var icon: String {
        switch self {
        case .add: "plus"
        case .history: "clock.arrow.circlepath"
        case .about: "info.circle"
        case .settings: "gearshape"
        }
    }
}

/// App con sesión: sidebar + sección (AuthenticatedApp en app/page.tsx).
struct MainView: View {
    @Environment(AppModel.self) private var model
    @State private var section: AppSection = .history
    @State private var friendsOpen = false
    @State private var sharingItem: HistoryItem?

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Sidebar(section: $section)
                .frame(width: 241)

            VStack(alignment: .trailing, spacing: 10) {
                FriendsButton(count: model.friends.incomingCount) { friendsOpen = true }

                switch section {
                case .history:
                    HistoryView(onShare: { sharingItem = $0 }, onGoAdd: { section = .add })
                case .add:
                    AddView(onSaved: { section = .history })
                case .settings:
                    SettingsView()
                case .about:
                    AboutView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(16)
        .sheet(isPresented: $friendsOpen) {
            FriendsView()
        }
        .sheet(item: $sharingItem) { item in
            ShareView(item: item, onOpenFriends: {
                sharingItem = nil
                friendsOpen = true
            })
        }
    }
}

private struct FriendsButton: View {
    @Environment(AppModel.self) private var model
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(model.loc.t(.friends), systemImage: "person.2")
        }
        .buttonStyle(HardButtonStyle(compact: true))
        .overlay(alignment: .topTrailing) {
            if count > 0 {
                Text("\(count)")
                    .font(Theme.font(11, .semibold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(Theme.danger)
                    .overlay(Rectangle().strokeBorder(.black, lineWidth: 1))
                    .offset(x: 8, y: -8)
            }
        }
    }
}

/// components/Sidebar.tsx
private struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @Binding var section: AppSection

    var body: some View {
        let loc = model.loc
        VStack(spacing: 16) {
            HardCard(inner: Theme.panel, padding: 14) {
                Button {
                    section = .history
                } label: {
                    BrandHeader(subtitle: loc.t(.brandSubtitle))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.bottom, 12)

                VStack(spacing: 2) {
                    ForEach(AppSection.allCases) { item in
                        NavItem(title: loc.t(item.title), icon: item.icon, selected: section == item) {
                            section = item
                        }
                    }
                }
            }

            HardCard(inner: Theme.panel, padding: 12) {
                PollView()
            }

            Spacer(minLength: 0)

            HardCard(inner: Theme.panel, padding: 12) {
                HStack(spacing: 10) {
                    IconTile(systemImage: "person.fill")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.session.viewer?.email ?? loc.t(.account))
                            .font(Theme.font(12.8))
                            .textCase(.uppercase)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button {
                            Task { await model.session.signOut() }
                        } label: {
                            Label(loc.t(.logout), systemImage: "rectangle.portrait.and.arrow.right")
                                .labelStyle(SquishedLabelStyle())
                        }
                        .buttonStyle(.plain)
                        .font(Theme.font(12.5, .semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .padding(.trailing, 5)
        .padding(.bottom, 5)
    }
}

private struct NavItem: View {
    let title: String
    let icon: String
    let selected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 14)).frame(width: 18)
                Text(title).squish()
                Spacer(minLength: 0)
            }
            .font(Theme.font(14.5, .semibold))
            .textCase(.uppercase)
            .foregroundStyle(selected ? .white : Theme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(selected ? Theme.accent : hovering ? Theme.chip : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// components/VotingPoll.tsx
private struct PollView: View {
    @Environment(AppModel.self) private var model
    @State private var open = false
    @State private var selected: Int?
    @State private var showResults = false
    @State private var submitting = false

    private let options: [L] = [.excellent, .good, .regular, .bad]

    var body: some View {
        let loc = model.loc
        let poll = model.poll
        VStack(alignment: .leading, spacing: 10) {
            Button {
                open.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "questionmark.bubble").font(.system(size: 12))
                    Text(loc.t(.pollTitle)).squish()
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .font(Theme.font(13.6, .semibold))
                .textCase(.uppercase)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if open {
                if !poll.loaded {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        MutedText(text: loc.t(.loadingPoll))
                    }
                } else if showResults {
                    results(loc: loc, poll: poll)
                } else {
                    let current = selected ?? poll.myVote
                    VStack(spacing: 6) {
                        ForEach(options.indices, id: \.self) { index in
                            Button {
                                selected = index
                            } label: {
                                HStack(spacing: 8) {
                                    Circle()
                                        .strokeBorder(.black, lineWidth: 1)
                                        .background(Circle().fill(current == index ? Theme.ink : .white).padding(4))
                                        .frame(width: 14, height: 14)
                                    Text(loc.t(options[index])).squish()
                                    Spacer()
                                }
                                .font(Theme.font(13.6))
                                .textCase(.uppercase)
                                .foregroundStyle(current == index ? .white : Theme.ink)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(current == index ? Theme.accent : .white)
                                .overlay(Rectangle().strokeBorder(.black, lineWidth: 1))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    HStack(spacing: 10) {
                        Button { submit() } label: { Label(loc.t(.submit), systemImage: "checkmark") }
                            .buttonStyle(HardButtonStyle(kind: .primary, compact: true))
                            .disabled(current == nil || submitting)
                        Button { showResults = true } label: { Label(loc.t(.view), systemImage: "chart.bar") }
                            .buttonStyle(HardButtonStyle(compact: true))
                    }
                    .padding(.top, 2)
                }
            }
        }
        .onChange(of: open) { _, isOpen in
            if isOpen { Task { await poll.refresh() } }
        }
    }

    private func results(loc: Localizer, poll: PollStore) -> some View {
        let total = poll.results?.total ?? 0
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(options.indices, id: \.self) { index in
                let count = poll.results?.counts[safe: index] ?? 0
                let pct = total > 0 ? Int((Double(count) / Double(total) * 100).rounded()) : 0
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(loc.t(options[index])).squish()
                        Spacer()
                        Text("\(count) · \(pct)%").foregroundStyle(Theme.muted)
                    }
                    .font(Theme.font(12.5))
                    .textCase(.uppercase)
                    GeometryReader { proxy in
                        Rectangle()
                            .fill(Theme.accent)
                            .frame(width: proxy.size.width * CGFloat(pct) / 100)
                    }
                    .frame(height: 8)
                    .background(.white)
                    .overlay(Rectangle().strokeBorder(.black, lineWidth: 1))
                }
            }
            MutedText(text: loc.totalVotes(total), size: 12)
            Button { showResults = false } label: { Label(loc.t(.back), systemImage: "arrow.uturn.backward") }
                .buttonStyle(HardLinkStyle(color: Theme.muted))
        }
    }

    private func submit() {
        guard let option = selected ?? model.poll.myVote else { return }
        submitting = true
        Task {
            try? await model.poll.vote(option)
            showResults = true
            submitting = false
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
