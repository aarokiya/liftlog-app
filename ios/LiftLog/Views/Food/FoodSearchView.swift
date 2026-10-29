import Supabase
import SwiftUI
import VisionKit

/// Search the foods databank, scan a barcode, or add a missing food to your own list.
struct FoodSearchView: View {
    @Environment(AuthService.self) private var auth
    @State private var query = ""
    @State private var results: [FoodItem] = []
    @State private var searching = false
    @State private var message: String?
    @State private var picked: FoodItem?
    @State private var scanning = false
    @State private var creating: String?

    var body: some View {
        List {
            Section {
                if DataScannerViewController.isSupported {
                    Button { scanning = true } label: { Label("Scan a barcode", systemImage: "barcode.viewfinder") }
                        .disabled(!auth.isSignedIn)
                }
                Button { creating = "" } label: { Label("Create a food", systemImage: "plus.square.on.square") }
                    .disabled(!auth.isSignedIn)
            } footer: {
                if !auth.isSignedIn {
                    Text("Sign in (Settings → Sign in to sync) to search the food databank, scan barcodes and add foods.")
                }
            }
            if let message {
                Text(message).foregroundStyle(.secondary)
            }
            if searching { ProgressView() }
            ForEach(results) { item in
                FoodRow(item: item, showBrand: item.brand != nil) { picked = item }
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search foods")
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await search()
        }
        .navigationTitle("All foods")
        .logFoodSheet($picked, source: "outside", place: \.brand)
        .sheet(isPresented: $scanning) {
            BarcodeScanner { code in
                scanning = false
                Task { await lookup(code) }
            }
            .ignoresSafeArea()
        }
        .sheet(item: Binding(get: { creating.map { IdentifiedCode(code: $0) } }, set: { creating = $0?.code })) { c in
            CreateFoodSheet(barcode: c.code) { item in picked = item }
        }
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        // The databank is readable only when signed in; an anonymous search would just come back empty.
        guard q.count >= 2, auth.isSignedIn, let client = auth.client else {
            results = []
            message = nil
            return
        }
        searching = true
        defer { searching = false }
        do {
            results = try await FoodDatabank.search(q, client: client).uniqued()
            message = results.isEmpty ? "No matches. Create it and it'll be saved to your account." : nil
        } catch {
            message = "Search failed: \(error.localizedDescription)"
        }
    }

    private func lookup(_ code: String) async {
        guard let client = auth.client, let userId = auth.userId else {
            message = "Sign in to look up barcodes."
            return
        }
        searching = true
        defer { searching = false }
        do {
            if let item = try await FoodDatabank.lookup(barcode: code, client: client, userId: userId) {
                picked = item
            } else {
                message = "Barcode \(code) isn't in the databank yet."
                creating = code
            }
        } catch {
            message = "Lookup failed: \(error.localizedDescription)"
        }
    }
}

private struct IdentifiedCode: Identifiable {
    let code: String
    var id: String { code }
}

struct BarcodeScanner: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128])],
            qualityLevel: .balanced, isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        private var done = false

        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for case let .barcode(code) in items {
                if let value = code.payloadStringValue {
                    done = true
                    scanner.stopScanning()
                    onScan(value)
                    return
                }
            }
        }
    }
}

struct CreateFoodSheet: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    let barcode: String
    let onCreated: (FoodItem) -> Void
    @State private var name = ""
    @State private var brand = ""
    @State private var serving = ""
    @State private var kcal: Double?
    @State private var protein: Double?
    @State private var carbs: Double?
    @State private var fat: Double?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Brand (optional)", text: $brand)
                TextField("Serving (e.g. 1 bar, 40 g)", text: $serving)
                if !barcode.isEmpty { LabeledContent("Barcode", value: barcode) }
                Section("Per serving") {
                    TextField("Calories", value: $kcal, format: .number).keyboardType(.decimalPad)
                    TextField("Protein (g)", value: $protein, format: .number).keyboardType(.decimalPad)
                    TextField("Carbs (g)", value: $carbs, format: .number).keyboardType(.decimalPad)
                    TextField("Fat (g)", value: $fat, format: .number).keyboardType(.decimalPad)
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Create food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || kcal == nil)
                }
            }
        }
    }

    private func save() async {
        guard let client = auth.client, let userId = auth.userId else {
            error = "Sign in to add foods."
            return
        }
        let trimmedBrand = brand.trimmingCharacters(in: .whitespaces)
        let trimmedServing = serving.trimmingCharacters(in: .whitespaces)
        let food = FoodDatabank.NewFood(
            source: "user", source_id: nil, barcode: FoodDatabank.normalize(barcode),
            name: String(name.trimmingCharacters(in: .whitespaces).prefix(200)),
            brand: trimmedBrand.isEmpty ? nil : String(trimmedBrand.prefix(120)),
            serving: trimmedServing.isEmpty ? "1 serving" : String(trimmedServing.prefix(120)), serving_g: nil,
            kcal: max(0, kcal ?? 0), protein: max(0, protein ?? 0), carbs: max(0, carbs ?? 0), fat: max(0, fat ?? 0),
            created_by: userId
        )
        do {
            let item = try await FoodDatabank.create(food, client: client)
            dismiss()
            onCreated(item)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
