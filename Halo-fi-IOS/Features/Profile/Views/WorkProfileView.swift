//
//  WorkProfileView.swift
//  Halo-fi-IOS
//
//  Settings → Work Profile. Captures the SSI work-context fields
//  the backend BWE/IRWE classifier needs to score deduction
//  candidates accurately — Plaid descriptions don't carry intent
//  (Uber to work vs Uber to dinner read identically), so we ask
//  the user once and reference the answers on every transaction
//  scan.
//
//  Auto-saves on each change (matches the PreferencesView pattern).
//  Shown for all users; non-SSI users can still fill it out — the
//  classifier just doesn't run for them.
//

import SwiftUI

struct WorkProfileView: View {
  // MARK: - Loaded state
  @State private var profile: WorkProfile = .empty
  @State private var isLoading = true
  @State private var loadError: String?

  // MARK: - Form-local state (mirrors profile, drives binding-friendly toggles)
  @State private var commutesToWorkplace: Bool = false
  @State private var hasWorkServiceAnimal: Bool = false
  @State private var requiresWorkMeds: Bool = false
  @State private var usesAssistiveTechForWork: Bool = false
  /// Set of method codes from {rideshare, paratransit, bus, family_drive, taxi, walk}.
  @State private var commuteMethods: Set<String> = []
  /// Set of weekday codes mon-sun.
  @State private var commuteDays: Set<String> = []

  // MARK: - Save UX
  @State private var saveTask: Task<Void, Never>?
  @State private var saveError: String?

  // MARK: - Options

  private let methodOptions: [(id: String, label: String)] = [
    ("rideshare", "Rideshare (Uber, Lyft)"),
    ("paratransit", "Paratransit / Access-A-Ride"),
    ("bus", "Bus"),
    ("taxi", "Taxi"),
    ("family_drive", "Family or friend drives me"),
    ("walk", "I walk"),
  ]

  private let dayOptions: [(id: String, label: String)] = [
    ("mon", "Mon"),
    ("tue", "Tue"),
    ("wed", "Wed"),
    ("thu", "Thu"),
    ("fri", "Fri"),
    ("sat", "Sat"),
    ("sun", "Sun"),
  ]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        explainerCard

        if isLoading {
          ProgressView("Loading…")
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        } else {
          commuteSection
          if commutesToWorkplace {
            commuteMethodsSection
            commuteDaysSection
          }
          serviceAnimalSection
          medsSection
          assistiveTechSection
          if let saveError {
            Text(saveError)
              .font(.caption)
              .foregroundColor(.red)
              .padding(.horizontal, 20)
          }
        }
        Spacer(minLength: 80)
      }
      .padding(.top, 16)
    }
    .navigationTitle("Work Profile")
    .navigationBarTitleDisplayMode(.inline)
    .task { await load() }
    .onDisappear { saveTask?.cancel() }
    // Each toggle/multi-select change schedules a debounced save. The
    // local state already updated synchronously so the UI is snappy;
    // the API roundtrip happens 350ms later in case the user is
    // toggling several things in quick succession.
    .onChange(of: commutesToWorkplace) { _, _ in scheduleSave() }
    .onChange(of: hasWorkServiceAnimal) { _, _ in scheduleSave() }
    .onChange(of: requiresWorkMeds) { _, _ in scheduleSave() }
    .onChange(of: usesAssistiveTechForWork) { _, _ in scheduleSave() }
    .onChange(of: commuteMethods) { _, _ in scheduleSave() }
    .onChange(of: commuteDays) { _, _ in scheduleSave() }
  }

  // MARK: - Sections

  private var explainerCard: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Why this matters")
        .font(.headline)
      Text("Halo uses these answers to spot SSI deductions in your bank activity. A blind work expense (BWE) only counts if the expense exists because of your work — your bank won't tell us that, so you do, once.")
        .font(.subheadline)
        .foregroundColor(.secondary)
    }
    .padding(16)
    .background(Color(.secondarySystemBackground))
    .cornerRadius(12)
    .padding(.horizontal, 20)
  }

  private var commuteSection: some View {
    sectionCard {
      Toggle(isOn: $commutesToWorkplace) {
        VStack(alignment: .leading, spacing: 4) {
          Text("I commute to a workplace")
            .font(.body)
          Text("Turn on if you go to a job site (not work-from-home).")
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
    }
  }

  private var commuteMethodsSection: some View {
    sectionCard {
      VStack(alignment: .leading, spacing: 8) {
        Text("How do you usually get there?")
          .font(.body)
        Text("Tap all that apply. Halo flags charges from these methods as BWE candidates.")
          .font(.caption)
          .foregroundColor(.secondary)
        FlowChips(
          options: methodOptions,
          selected: $commuteMethods
        )
        .padding(.top, 4)
      }
    }
  }

  private var commuteDaysSection: some View {
    sectionCard {
      VStack(alignment: .leading, spacing: 8) {
        Text("Which days?")
          .font(.body)
        Text("Charges on these days get a confidence boost; off-day charges still need confirmation.")
          .font(.caption)
          .foregroundColor(.secondary)
        FlowChips(
          options: dayOptions,
          selected: $commuteDays
        )
        .padding(.top, 4)
      }
    }
  }

  private var serviceAnimalSection: some View {
    sectionCard {
      Toggle(isOn: $hasWorkServiceAnimal) {
        VStack(alignment: .leading, spacing: 4) {
          Text("I have a service animal I use for work")
            .font(.body)
          Text("Vet visits, food, and training count as BWE for work-essential animals.")
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
    }
  }

  private var medsSection: some View {
    sectionCard {
      Toggle(isOn: $requiresWorkMeds) {
        VStack(alignment: .leading, spacing: 4) {
          Text("I take prescriptions to be able to work")
            .font(.body)
          Text("Pharmacy charges become high-confidence IRWE candidates.")
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
    }
  }

  private var assistiveTechSection: some View {
    sectionCard {
      Toggle(isOn: $usesAssistiveTechForWork) {
        VStack(alignment: .leading, spacing: 4) {
          Text("I use assistive tech for work")
            .font(.body)
          Text("Screen readers, magnifiers, dictation software — subscriptions to those count as BWE.")
            .font(.caption)
            .foregroundColor(.secondary)
        }
      }
    }
  }

  @ViewBuilder
  private func sectionCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    content()
      .padding(16)
      .background(Color(.secondarySystemBackground))
      .cornerRadius(12)
      .padding(.horizontal, 20)
  }

  // MARK: - Network

  private func load() async {
    isLoading = true
    defer { isLoading = false }
    do {
      let p = try await WorkProfileService.shared.fetch()
      profile = p
      commutesToWorkplace = p.commutesToWorkplace ?? false
      hasWorkServiceAnimal = p.hasWorkServiceAnimal ?? false
      requiresWorkMeds = p.requiresWorkMeds ?? false
      usesAssistiveTechForWork = p.usesAssistiveTechForWork ?? false
      commuteMethods = Set((p.commuteMethods ?? "")
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty })
      commuteDays = Set((p.commuteDays ?? "")
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty })
    } catch {
      loadError = "Couldn't load your work profile. Pull to retry."
    }
  }

  private func scheduleSave() {
    guard !isLoading else { return }
    saveTask?.cancel()
    saveTask = Task {
      try? await Task.sleep(nanoseconds: 350_000_000)
      guard !Task.isCancelled else { return }
      await save()
    }
  }

  private func save() async {
    saveError = nil
    let patch = WorkProfileUpdate(
      commutesToWorkplace: commutesToWorkplace,
      commuteMethods: commutesToWorkplace ? commuteMethods.sorted().joined(separator: ",") : nil,
      commuteDays: commutesToWorkplace ? commuteDays.sorted(by: weekdayOrder).joined(separator: ",") : nil,
      hasWorkServiceAnimal: hasWorkServiceAnimal,
      requiresWorkMeds: requiresWorkMeds,
      usesAssistiveTechForWork: usesAssistiveTechForWork
    )
    do {
      profile = try await WorkProfileService.shared.update(patch)
      Haptics.engine.play(.tapLight)
    } catch {
      saveError = "Couldn't save right now."
      Logger.error("WorkProfile save failed: \(error)")
    }
  }

  /// Sort weekdays mon → sun rather than alphabetically (which would
  /// give fri,mon,sat,sun,thu,tue,wed — ugly).
  private func weekdayOrder(_ a: String, _ b: String) -> Bool {
    let order = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
    let ai = order.firstIndex(of: a) ?? 99
    let bi = order.firstIndex(of: b) ?? 99
    return ai < bi
  }
}

// MARK: - Multi-select chip row

private struct FlowChips: View {
  let options: [(id: String, label: String)]
  @Binding var selected: Set<String>

  var body: some View {
    LazyVGrid(
      columns: [GridItem(.adaptive(minimum: 100), spacing: 8)],
      alignment: .leading,
      spacing: 8
    ) {
      ForEach(options, id: \.id) { opt in
        Button {
          if selected.contains(opt.id) {
            selected.remove(opt.id)
          } else {
            selected.insert(opt.id)
          }
        } label: {
          Text(opt.label)
            .font(.subheadline)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background(selected.contains(opt.id) ? Color.accentColor : Color(.tertiarySystemBackground))
            .foregroundColor(selected.contains(opt.id) ? .white : .primary)
            .cornerRadius(20)
        }
        .buttonStyle(.plain)
      }
    }
  }
}
