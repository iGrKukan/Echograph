import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(PurchaseManager.self) private var purchases
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Spacing.block) {
                    header

                    benefits

                    productsList
                        .padding(.top, 8)

                    Button("Restore Purchases") {
                        Task { await purchases.restorePurchases() }
                    }
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Color.textSecondary)
                    .padding(.top, 8)

                    Text("All processing happens on your iPhone. Echograph never uploads your audio or transcripts.")
                        .font(DS.Typography.secondary)
                        .foregroundStyle(DS.Color.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                }
                .padding(.horizontal, DS.Spacing.horizontal)
                .padding(.vertical, DS.Spacing.block)
            }
            .background(DS.Color.background)
            .navigationTitle("Upgrade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .tint(DS.Color.accent)
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
                .font(.system(size: 52))
                .foregroundStyle(DS.Color.accent)
            Text("Voicekeep Pro+")
                .font(DS.Typography.screenTitle)
                .foregroundStyle(DS.Color.textPrimary)
            Text("AI summaries, questions and tags for every recording. Everything stays on your iPhone.")
                .font(DS.Typography.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(DS.Color.textSecondary)
                .padding(.horizontal)
        }
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(benefitRows.enumerated()), id: \.offset) { index, row in
                row
                if index < benefitRows.count - 1 {
                    Hairline()
                }
            }
        }
    }

    private var benefitRows: [BenefitRow] {
        [
            BenefitRow(icon: "wand.and.stars",
                       title: "Unlimited transcription",
                       text: "Fast on-device transcription in 25 languages, without limits."),
            BenefitRow(icon: "sparkles",
                       title: "AI Summary",
                       text: "Turns any recording into a concise summary with action items."),
            BenefitRow(icon: "bubble.left.and.text.bubble.right",
                       title: "Ask AI",
                       text: "Ask questions about a recording and get answers drawn from the transcript."),
            BenefitRow(icon: "tag",
                       title: "Auto Tags",
                       text: "Get topic tags suggested automatically for every recording."),
            BenefitRow(icon: "checkmark.seal",
                       title: "Works on every iPhone",
                       text: "AI runs on Apple Intelligence where available, or on a downloadable on-device model everywhere else."),
            BenefitRow(icon: "person.2.wave.2",
                       title: "Speaker labels",
                       text: "Tag who is speaking in each segment of the transcript."),
            BenefitRow(icon: "lock.shield",
                       title: "Privacy by Design",
                       text: "Recordings, transcripts and summaries never leave your iPhone."),
        ]
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
    // LocalizedStringKey (not String) so `Text(title)` / `Text(text)` below
    // actually look these up in Localizable.xcstrings instead of displaying
    // the source-language literal verbatim regardless of device locale.
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(DS.Color.accent)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.Typography.body.weight(.medium))
                    .foregroundStyle(DS.Color.textPrimary)
                Text(text)
                    .font(DS.Typography.secondary)
                    .foregroundStyle(DS.Color.textSecondary)
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
                        .font(DS.Typography.body.weight(.semibold))
                        .foregroundStyle(DS.Color.textPrimary)
                    Text(product.description)
                        .font(DS.Typography.secondary)
                        .foregroundStyle(DS.Color.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(product.displayPrice)
                        .font(DS.Typography.body.weight(.semibold).monospacedDigit())
                        .foregroundStyle(DS.Color.textPrimary)
                    if let unit = subscriptionUnit {
                        Text(unit)
                            .font(DS.Typography.secondary)
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                }
            }
            .padding()
            .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.card))
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
