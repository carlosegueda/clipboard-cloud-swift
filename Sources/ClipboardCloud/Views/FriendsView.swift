import SwiftUI

/// components/FriendsModal.tsx
struct FriendsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private enum Tab: Hashable { case friends, incoming, outgoing }

    @State private var tab: Tab = .friends
    @State private var email = ""
    @State private var inviting = false
    @State private var inviteError = ""
    @State private var busyId: String?
    @State private var removing: Friend?

    var body: some View {
        let loc = model.loc
        let store = model.friends
        HardModal(title: loc.t(.friends), subtitle: loc.t(.friendsSubtitle), onClose: { dismiss() }) {
            VStack(alignment: .leading, spacing: 6) {
                FieldLabel(text: loc.t(.inviteByEmail))
                HStack(spacing: 10) {
                    HardField(placeholder: loc.t(.invitePlaceholder), text: $email, onSubmit: invite)
                        .onChange(of: email) { inviteError = "" }
                    Button(action: invite) { Label(loc.t(.inviteSend), systemImage: "person.badge.plus") }
                        .buttonStyle(HardButtonStyle(kind: .primary))
                        .disabled(inviting || email.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text(inviteError.isEmpty ? loc.t(.inviteHint) : inviteError)
                    .font(Theme.font(11.5))
                    .textCase(.uppercase)
                    .foregroundStyle(inviteError.isEmpty ? Theme.muted : Theme.danger)
            }

            VStack(alignment: .leading, spacing: -1) {
                HardTabs(tabs: [
                    .init(id: Tab.friends, label: loc.t(.friendsTabFriends), count: store.friends?.count),
                    .init(id: Tab.incoming, label: loc.t(.friendsTabIncoming),
                          count: store.requests?.incoming.count, countColor: Theme.danger),
                    .init(id: Tab.outgoing, label: loc.t(.friendsTabOutgoing), count: store.requests?.outgoing.count),
                ], selection: $tab)

                Group {
                    if let friends = store.friends, let requests = store.requests {
                        switch tab {
                        case .friends:
                            list(friends, empty: loc.t(.noFriends), emptyIcon: "person") { friend in
                                row(email: friend.email ?? loc.t(.unknownUser),
                                    meta: friend.publicKey != nil ? loc.relative(friend.since) : loc.t(.friendNoKey)) {
                                    Button { removing = friend } label: {
                                        Label(loc.t(.removeFriend), systemImage: "person.badge.minus")
                                    }
                                    .buttonStyle(HardButtonStyle(kind: .danger, compact: true))
                                    .disabled(busyId == friend.id)
                                }
                            }
                        case .incoming:
                            list(requests.incoming, empty: loc.t(.noIncoming), emptyIcon: "tray") { request in
                                row(email: request.email ?? loc.t(.unknownUser), meta: loc.relative(request.createdAt)) {
                                    Button {
                                        run(request.id, success: loc.t(.friendAccepted)) { try await store.accept(request.id) }
                                    } label: {
                                        Label(loc.t(.accept), systemImage: "checkmark")
                                    }
                                    .buttonStyle(HardButtonStyle(compact: true))
                                    Button {
                                        run(request.id) { try await store.decline(request.id) }
                                    } label: {
                                        Label(loc.t(.decline), systemImage: "xmark")
                                    }
                                    .buttonStyle(HardButtonStyle(kind: .danger, compact: true))
                                }
                                .disabled(busyId == request.id)
                            }
                        case .outgoing:
                            list(requests.outgoing, empty: loc.t(.noOutgoing), emptyIcon: "paperplane") { request in
                                let meta = loc.relative(request.createdAt)
                                    + (request.registered == false ? " · \(loc.t(.notRegistered))" : "")
                                row(email: request.email ?? loc.t(.unknownUser), meta: meta) {
                                    Button {
                                        run(request.id) { try await store.cancel(request.id) }
                                    } label: {
                                        Label(loc.t(.cancelInvite), systemImage: "xmark")
                                    }
                                    .buttonStyle(HardButtonStyle(kind: .danger, compact: true))
                                    .disabled(busyId == request.id)
                                }
                            }
                        }
                    } else {
                        ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(.vertical, 16)
                    }
                }
                .frame(minHeight: 200, alignment: .top)
                .background(.white)
                .overlay(Rectangle().strokeBorder(.black, lineWidth: 1))
            }
        }
        .frame(width: 540)
        .background(Theme.bg)
        .task { await store.refresh() }
        .confirmationDialog(
            loc.confirmRemoveFriend(removing?.email ?? loc.t(.unknownUser)),
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })
        ) {
            Button(loc.t(.removeFriend), role: .destructive) {
                if let friend = removing {
                    run(friend.id) { try await store.remove(friend.id) }
                }
            }
        }
    }

    private func list<Item: Identifiable, Row: View>(
        _ items: [Item], empty: String, emptyIcon: String, @ViewBuilder row: @escaping (Item) -> Row
    ) -> some View {
        Group {
            if items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: emptyIcon).font(.system(size: 22, weight: .light))
                    MutedText(text: empty, size: 13.4)
                }
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            row(item)
                            if index < items.count - 1 {
                                Rectangle().fill(.black).frame(height: 1)
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
    }

    private func row<Actions: View>(email: String, meta: String, @ViewBuilder actions: () -> Actions) -> some View {
        HStack(spacing: 10) {
            IconTile(systemImage: "person.fill")
            VStack(alignment: .leading, spacing: 1) {
                Text(email).font(Theme.font(13.6)).lineLimit(1).truncationMode(.middle)
                Text(meta).font(Theme.font(11.5)).textCase(.uppercase).foregroundStyle(Theme.muted)
            }
            Spacer()
            HStack(spacing: 8) { actions() }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func invite() {
        let loc = model.loc
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !inviting else { return }
        inviting = true
        inviteError = ""
        Task {
            do {
                let result = try await model.friends.invite(email: trimmed)
                if result.ok {
                    email = ""
                    let accepted = result.status == "accepted"
                    model.showToast(loc.t(accepted ? .inviteAccepted : .inviteSent))
                    tab = accepted ? .friends : .outgoing
                } else {
                    let key: L = switch result.reason {
                    case "invalidEmail": .inviteInvalidEmail
                    case "self": .inviteSelf
                    case "alreadyFriends": .inviteAlreadyFriends
                    case "alreadyInvited": .inviteAlreadyInvited
                    default: .inviteFailed
                    }
                    inviteError = loc.t(key)
                }
            } catch {
                print("[friends] invite", error)
                inviteError = loc.t(.inviteFailed)
            }
            inviting = false
        }
    }

    private func run(_ id: String, success: String? = nil, _ action: @escaping () async throws -> Void) {
        busyId = id
        Task {
            do {
                try await action()
                if let success { model.showToast(success) }
            } catch {
                print("[friends]", error)
                model.showToast(model.loc.t(.friendActionFailed))
            }
            busyId = nil
        }
    }
}

/// components/ShareModal.tsx
struct ShareView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let item: HistoryItem
    let onOpenFriends: () -> Void

    @State private var selected: Set<String> = []
    @State private var sending = false

    var body: some View {
        let loc = model.loc
        HardModal(title: loc.t(.shareTitle), onClose: { if !sending { dismiss() } }) {
            if let friends = model.friends.friends {
                if friends.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "person").font(.system(size: 22, weight: .light))
                        MutedText(text: loc.t(.shareNoFriends), size: 13.4)
                        Button(action: onOpenFriends) { Label(loc.t(.friends), systemImage: "person.2") }
                            .buttonStyle(HardButtonStyle(kind: .primary, compact: true))
                    }
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(friends.enumerated()), id: \.element.id) { index, friend in
                                HardCheckRow(
                                    checked: selected.contains(friend.id),
                                    enabled: friend.publicKey != nil && !sending,
                                    action: { toggle(friend.id) }
                                ) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(friend.email ?? loc.t(.unknownUser)).font(Theme.font(13.6))
                                        if friend.publicKey == nil {
                                            Text(loc.t(.friendNoKey))
                                                .font(Theme.font(11.5)).textCase(.uppercase).foregroundStyle(Theme.muted)
                                        }
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                                if index < friends.count - 1 {
                                    Rectangle().fill(.black).frame(height: 1)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 280)
                    .background(.white)
                    .overlay(Rectangle().strokeBorder(.black, lineWidth: 1))

                    HStack {
                        if sending { ProgressView().controlSize(.small) }
                        Spacer()
                        Button(action: send) {
                            Label(sending ? loc.t(.sharing) : loc.shareSend(selected.count), systemImage: "paperplane")
                        }
                        .buttonStyle(HardButtonStyle(kind: .primary))
                        .disabled(selected.isEmpty || sending)
                    }
                }
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(.vertical, 16)
            }
        }
        .frame(width: 440)
        .background(Theme.bg)
        .task { await model.friends.refresh() }
    }

    private func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func send() {
        let recipients = (model.friends.friends ?? []).filter { selected.contains($0.id) }
        sending = true
        Task {
            let close = await model.share(item, with: recipients)
            sending = false
            if close { dismiss() }
        }
    }
}
