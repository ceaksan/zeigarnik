import SwiftUI
import ZeigarnikKit

struct GoToDateSheet: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Go to Date").font(.system(size: 14, weight: .semibold))
            DatePicker("Date", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .environment(\.locale, model.calendar.locale ?? .autoupdatingCurrent)
                .environment(\.timeZone, model.calendar.timeZone)
                .environment(\.calendar, model.calendar)
                .labelsHidden()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Go") {
                    model.goTo(day: dayKey(date, calendar: model.calendar))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 320)
        .onAppear { date = model.currentDate }
    }
}
