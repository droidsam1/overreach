import DesignSystem
import ExercisesPresentation
import SwiftUI

struct ExerciseArtworkSection: View {
    let model: ExerciseEditorModel

    var body: some View {
        if model.illustration != nil || model.canEditNames {
            Section {
                if let illustration = model.illustration {
                    HStack(spacing: Spacing.xSmall) {
                        ForEach(1...3, id: \.self) { index in
                            ExercisePose(illustration: illustration, index: index)
                        }
                    }
                    .accessibilityHidden(true)
                }
                if model.canEditNames {
                    NavigationLink("Choose illustration") {
                        ExerciseArtworkPicker(model: model)
                    }
                }
            } footer: {
                if model.illustration != nil, let url = model.illustrationCreditURL {
                    Link(destination: url) {
                        Text("Illustrations by Bryl Lim and Everkinetic")
                    }
                }
            }
        }
    }
}

private struct ExerciseArtworkPicker: View {
    @Bindable var model: ExerciseEditorModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if model.illustrationSearchText.isEmpty {
                Button {
                    select(nil)
                } label: {
                    HStack {
                        Text("Use equipment icon")
                        Spacer()
                        selectionMark(for: nil)
                    }
                }
                .accessibilityAddTraits(model.selectedIllustration == nil ? .isSelected : [])
                if !model.suggestedIllustrations.isEmpty {
                    Section("Suggested illustrations") {
                        ForEach(model.suggestedIllustrations, content: optionRow)
                    }
                }
            }
            Section("All illustrations") {
                ForEach(model.illustrationOptions, content: optionRow)
            }
        }
        .navigationTitle("Choose illustration")
        .searchable(text: $model.illustrationSearchText)
        .onAppear { model.illustrationSearchText = "" }
        .overlay {
            if model.illustrationOptions.isEmpty {
                ListEmptyState(
                    query: model.illustrationSearchText, title: "No illustrations", systemImage: "photo"
                )
            }
        }
    }

    private func optionRow(_ option: ExerciseIllustrationOption) -> some View {
        Button {
            select(option.id)
        } label: {
            HStack(spacing: Spacing.small) {
                ExercisePose(illustration: option.id, index: 1)
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
                Text(option.name)
                Spacer()
                selectionMark(for: option.id)
            }
        }
        .accessibilityAddTraits(model.selectedIllustration == option.id ? .isSelected : [])
    }

    private func selectionMark(for id: String?) -> some View {
        Group {
            if model.selectedIllustration == id {
                Image(systemName: "checkmark")
                    .accessibilityHidden(true)
            }
        }
    }

    private func select(_ id: String?) {
        model.selectIllustration(id)
        dismiss()
    }
}
