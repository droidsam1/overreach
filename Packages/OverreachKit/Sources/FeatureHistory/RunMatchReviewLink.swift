import DesignSystem
import HistoryPresentation
import SwiftUI

struct RunMatchReviewLink: View {
    let history: HistoryModel
    let calendar: Bool

    private var reviews: [HistoryRunReview] { calendar ? history.calendar.runReviews : history.runReviews }

    var body: some View {
        if !reviews.isEmpty {
            NavigationLink {
                List {
                    ForEach(reviews) { review in
                        Section {
                            original(review.garmin)
                            original(review.appleHealth)
                            Button("Link these runs") {
                                history.chooseRunMatch(.linked, for: review.id)
                            }
                            if review.isSeparate {
                                Button("Allow automatic matching") {
                                    history.chooseRunMatch(nil, for: review.id)
                                }
                            } else {
                                Button("Keep runs separate") {
                                    history.chooseRunMatch(.separate, for: review.id)
                                }
                            }
                        }
                    }
                    if reviews.isEmpty {
                        Text("No run matches to review")
                            .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Review run matches")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
            } label: {
                MatchReviewCard(title: "Review run matches", symbol: "figure.run", count: reviews.count)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private func original(_ run: HistoryRunActivity) -> some View {
        VStack(alignment: .leading) {
            HistoryRunRow(run: run, showsDate: false)
            Text(run.startedAt, format: .dateTime.day().month().year().hour().minute())
                .font(.subheadline)
        }
        .accessibilityElement(children: .combine)
    }
}
