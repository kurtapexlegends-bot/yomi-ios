import SwiftUI
import YomiCore

public struct SourceFilterSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var workingFilters: [Filter]
    private let initialFilters: [Filter]
    private let onApply: ([Filter]) -> Void
    private let onReset: () -> Void

    public init(
        currentFilters: [Filter],
        defaultFilters: [Filter],
        onApply: @escaping ([Filter]) -> Void,
        onReset: @escaping () -> Void
    ) {
        self._workingFilters = State(initialValue: currentFilters)
        self.initialFilters = defaultFilters
        self.onApply = onApply
        self.onReset = onReset
    }

    public var body: some View {
        NavigationStack {
            Form {
                ForEach(0..<workingFilters.count, id: \.self) { idx in
                    renderFilterRow(at: idx)
                }
            }
            .scrollContentBackground(.hidden)
            .background(YomiTheme.pureBlack)
            .navigationTitle("Filters")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        workingFilters = initialFilters
                        onReset()
                        dismiss()
                    }
                    .foregroundStyle(YomiTheme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply(workingFilters)
                        dismiss()
                    }
                    .font(.headline)
                    .foregroundStyle(YomiTheme.accent)
                }
            }
        }
    }

    @ViewBuilder
    private func renderFilterRow(at index: Int) -> some View {
        let filter = workingFilters[index]
        Section {
            switch filter {
            case .select(let id, let name, let values, let selectedIndex):
                Picker(name, selection: Binding(
                    get: { selectedIndex },
                    set: { newIndex in
                        workingFilters[index] = .select(id: id, name: name, values: values, selectedIndex: newIndex)
                    }
                )) {
                    ForEach(0..<values.count, id: \.self) { valIdx in
                        Text(values[valIdx]).tag(valIdx)
                    }
                }
                .pickerStyle(.menu)

            case .triState(let id, let name, let state):
                HStack {
                    Text(name)
                        .foregroundStyle(YomiTheme.textPrimary)
                    Spacer()
                    Button {
                        let nextState: TriState
                        switch state {
                        case .ignored: nextState = .included
                        case .included: nextState = .excluded
                        case .excluded: nextState = .ignored
                        }
                        workingFilters[index] = .triState(id: id, name: name, state: nextState)
                    } label: {
                        HStack(spacing: 6) {
                            switch state {
                            case .ignored:
                                Image(systemName: "circle")
                                    .foregroundStyle(YomiTheme.textSecondary)
                                Text("Any")
                                    .font(.subheadline)
                                    .foregroundStyle(YomiTheme.textSecondary)
                            case .included:
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.green)
                                Text("Included")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.green)
                            case .excluded:
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(Color.red)
                                Text("Excluded")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.red)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(YomiTheme.surface)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

            case .sort(let id, let name, let values, let selectedIndex, let ascending):
                HStack {
                    Picker(name, selection: Binding(
                        get: { selectedIndex },
                        set: { newIndex in
                            workingFilters[index] = .sort(id: id, name: name, values: values, selectedIndex: newIndex, ascending: ascending)
                        }
                    )) {
                        ForEach(0..<values.count, id: \.self) { valIdx in
                            Text(values[valIdx]).tag(valIdx)
                        }
                    }
                    .pickerStyle(.menu)

                    Spacer()

                    Button {
                        workingFilters[index] = .sort(id: id, name: name, values: values, selectedIndex: selectedIndex, ascending: !ascending)
                    } label: {
                        Image(systemName: ascending ? "arrow.up" : "arrow.down")
                            .font(.subheadline.bold())
                            .foregroundStyle(YomiTheme.accent)
                            .padding(8)
                            .background(YomiTheme.surface)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

            case .text(let id, let name, let text):
                HStack {
                    Text(name)
                        .font(.subheadline)
                        .foregroundStyle(YomiTheme.textPrimary)
                    TextField(name, text: Binding(
                        get: { text },
                        set: { newText in
                            workingFilters[index] = .text(id: id, name: name, state: newText)
                        }
                    ))
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.plain)
                    .foregroundStyle(YomiTheme.textPrimary)
                }
            }
        }
    }
}
