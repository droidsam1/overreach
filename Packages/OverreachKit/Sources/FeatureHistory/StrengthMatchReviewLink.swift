import Foundation
import HistoryPresentation
import SwiftUI

struct StrengthMatchReviewLink: View {
    let history: HistoryModel
    let calendar: Bool

    private var reviews: [HistoryStrengthReview] {
        calendar ? history.calendar.strengthReviews : history.strengthReviews
    }

    var body: some View {
        if !reviews.isEmpty {
            NavigationLink("Review strength matches") {
                List {
                    ForEach(reviews) { review in
                        Section {
                            original(review.sessionName, source: review.sessionSource,
                                     start: review.sessionStart, duration: review.sessionDuration)
                            original(review.recording.title, source: review.recording.source,
                                     start: review.recording.startedAt, duration: review.recording.durationSeconds)
                            ForEach(review.recording.metrics) { metric in
                                LabeledContent(metric.label, value: metric.value)
                            }
                            Button("Link these workouts") {
                                history.chooseStrengthMatch(.linked, for: review.id)
                            }
                            if review.isSeparate {
                                Button("Allow automatic matching") {
                                    history.chooseStrengthMatch(nil, for: review.id)
                                }
                            } else {
                                Button("Keep workouts separate") {
                                    history.chooseStrengthMatch(.separate, for: review.id)
                                }
                            }
                        }
                    }
                    if reviews.isEmpty {
                        Text("No strength matches to review")
                            .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Review strength matches")
            }
        }
    }

    private func original(_ title: String, source: String, start: Date, duration: Double?) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.headline)
            Text(source)
            Text(start, format: .dateTime.day().month().year().hour().minute())
            if let duration {
                Text(Duration.seconds(duration), format: .units(allowed: [.hours, .minutes], width: .abbreviated))
            }
        }
        .accessibilityElement(children: .combine)
    }
}
