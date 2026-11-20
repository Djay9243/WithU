//
//  NewCircleSheet.swift
//  WithU
//
//  One form to make a circle: a name and the people in it, then Create.
//

import SwiftUI

struct NewCircleSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var people: [ContactCandidate] = []
    @State private var choosingPeople = false
    @FocusState private var nameFocused: Bool

    private let suggestions = ["Family", "Friends", "Travel Buddies", "Flatmates"]

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                        .focused($nameFocused)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(suggestions, id: \.self) { suggestion in
                                Button(suggestion) { name = suggestion }
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(name == suggestion ? Theme.primary : Theme.lavender, in: Capsule())
                                    .foregroundStyle(name == suggestion ? .white : Theme.primary)
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                Section("People") {
                    ForEach(people) { person in
                        HStack(spacing: 12) {
                            AvatarView(name: person.name, colorIndex: people.firstIndex(of: person) ?? 0, size: 32)
                            Text(person.name)
                                .foregroundStyle(Theme.ink)
                        }
                    }
                    .onDelete { people.remove(atOffsets: $0) }

                    Button {
                        choosingPeople = true
                    } label: {
                        Label(people.isEmpty ? "Add From Contacts" : "Add More", systemImage: "person.crop.circle.badge.plus")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(ScreenBackground())
            .navigationTitle("New Circle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        model.createCircle(named: trimmedName, with: people)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(trimmedName.isEmpty)
                }
            }
            .onAppear { nameFocused = true }
        }
        .sheet(isPresented: $choosingPeople) {
            ContactPicker { picked in
                let known = Set(people.map(\.id))
                people.append(contentsOf: picked.filter { !known.contains($0.id) })
                choosingPeople = false
            }
            .ignoresSafeArea()
        }
    }
}

#Preview {
    NewCircleSheet()
        .environment(AppModel.shared)
}
