import SwiftUI

struct ExercisePose: View {
    let illustration: String
    let index: Int

    var body: some View {
        Image("\(illustration)-\(index)", bundle: .module)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(.primary)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}
