import SwiftUI
import ZeigarnikKit

struct OtherBucketView: View {
    let model: AppModel

    var body: some View {
        let totals = model.activity.otherTotals()
        List {
            Section {
                ForEach(totals, id: \.label) { entry in
                    HStack {
                        Text(entry.label).truncationMode(.middle).lineLimit(1)
                        Spacer()
                        Text(Format.duration(entry.seconds)).foregroundStyle(Theme.muted)
                    }
                }
            } footer: {
                Text("Work not matched to a project: sessions opened from a root folder, or old or moved paths. Included in daily totals.")
                    .font(Theme.small).foregroundStyle(Theme.muted)
            }
        }
        .overlay {
            if totals.isEmpty { Text("No work outside projects").foregroundStyle(Theme.muted) }
        }
    }
}
