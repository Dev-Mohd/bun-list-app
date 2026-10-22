import BunnListCore
import SwiftUI

/// Add a brew experience for a lot: method, the attempt's own star rating, date, and a note.
/// Its stars rate this attempt and do not change the lot's rating average.
struct ExperienceEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let lotID: LotID

    @State private var methodCode = "V60"
    @State private var stars = 0
    @State private var brewedAt = Date()
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("الطريقة") {
                    Picker("الطريقة", selection: $methodCode) {
                        ForEach(ReferenceCodes.brewMethods, id: \.code) { Text($0.nameAr).tag($0.code) }
                    }
                    .accessibilityIdentifier("experience-method")
                }
                Section("تقييم هذه التجربة") {
                    StarRatingControl(value: stars, label: "نجوم التجربة") { stars = $0 }
                    Text("نجوم التجربة لهذا التحضير، ولا تدخل في متوسط تقييم المحصول.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Section("التفاصيل") {
                    DatePicker("التاريخ", selection: $brewedAt, displayedComponents: .date)
                    VStack(alignment: .leading) {
                        Text("ملاحظة").font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: $note).frame(minHeight: 90).accessibilityIdentifier("experience-note")
                    }
                }
            }
            .navigationTitle("تجربة تحضير")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("نشر") {
                        if model.addExperience(lot: lotID, methodCode: methodCode, stars: stars, brewedAt: brewedAt, note: note) {
                            dismiss()
                        }
                    }
                    .disabled(stars < 1)
                    .accessibilityIdentifier("experience-publish")
                }
            }
        }
    }
}
