import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(PurchaseManager.self) private var purchases
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header

                    benefits

                    productsList
                        .padding(.top, 8)

                    Button("Restore Purchases") {
                        Task { await purchases.restorePurchases() }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)

                    Text("All processing happens on your iPhone. Echograph never uploads your audio or transcripts.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                }
                .padding()
            }
            .navigationTitle("Upgrade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Error", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(purchases.lastError ?? "")
            }
            .task {
                if purchases.products.isEmpty {
                    await purchases.loadProducts()
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Voicekeep Pro+")
                .font(.largeTitle.weight(.semibold))
            Text("Pro-quality on-device transcription with AI summary and Q&A. Everything stays on your iPhone.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 12) {
            BenefitRow(icon: "wand.and.stars",
                       title: "Parakeet v3",
                       text: "Fast multilingual transcription, fully on-device.")
            BenefitRow(icon: "person.2.wave.2",
                       title: "Speaker labels",
                       text: "Tag who is speaking in each segment of the transcript.")
            BenefitRow(icon: "sparkles",
                       title: "AI Summary",
                       text: "Apple Intelligence summarizes meetings into action items.")
            BenefitRow(icon: "lock.shield",
                       title: "Privacy by Design",
                       text: "Recordings, transcripts and summaries never leave your iPhone.")
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var productsList: some View {
        VStack(spacing: 12) {
            ForEach(purchases.products, id: \.id) { product in
                ProductCard(product: product) {
                    Task { await purchases.purchase(product) }
                }
                .disabled(purchases.isPurchasing || purchases.purchasedIdentifiers.contains(product.id))
            }

            if purchases.products.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { purchases.lastError != nil },
            set: { if !$0 { /* keep simple */ } }
        )
    }
}

private struct BenefitRow: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ProductCard: View {
    let product: Product
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.displayName)
                        .font(.headline)
                    Text(product.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(product.displayPrice)
                        .font(.headline.monospacedDigit())
                    if let unit = subscriptionUnit {
                        Text(unit)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var subscriptionUnit: String? {
        guard let subscription = product.subscription else { return "Lifetime" }
        switch subscription.subscriptionPeriod.unit {
        case .day: return "/day"
        case .week: return "/week"
        case .month: return "/month"
        case .year: return "/year"
        @unknown default: return nil
        }
    }
}
