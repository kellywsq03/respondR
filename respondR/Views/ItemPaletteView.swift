import SwiftUI
import RealityKit

struct ItemPaletteView: View {
    @Environment(SceneViewModel.self) var viewModel

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Text("Items")
                .font(.title3.bold())
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(ItemCategory.allCases, id: \.self) { category in
                        Text(category.rawValue)
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 18)
                            .padding(.bottom, 8)

                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(
                                ItemType.allTypes.filter { $0.category == category },
                                id: \.name
                            ) { item in
                                PaletteCell(
                                    item: item,
                                    isSelected: viewModel.selectedItemType == item
                                )
                                .onTapGesture {
                                    if viewModel.selectedItemType == item {
                                        viewModel.selectedItemType = nil
                                    } else {
                                        viewModel.selectedItemType = item
                                        viewModel.selectedPlacedItemID = nil
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                }
                .padding(.bottom, 16)
            }

            // Contextual footer
            if viewModel.selectedPlacedItemID != nil {
                Divider()
                Button(role: .destructive) {
                    if let id = viewModel.selectedPlacedItemID,
                       let anchor = viewModel.tabletopAnchor {
                        anchor.findEntity(named: "placed_\(id.uuidString)")?.removeFromParent()
                        viewModel.removeItem(id: id)
                    }
                } label: {
                    Label("Remove Selected", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .padding(14)
            }

            if viewModel.selectedItemType != nil {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "hand.tap.fill")
                        .foregroundStyle(.secondary)
                    Text("Tap the floor to place")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
            }
        }
        .frame(width: 280)
        .glassBackgroundEffect()
    }
}

// MARK: - Grid Cell

private struct PaletteCell: View {
    let item: ItemType
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            // Placeholder asset area — sized to accommodate future 3D renders
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(placeholderColor.opacity(0.55))

                Image(systemName: item.sfSymbol)
                    .font(.system(size: 26))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(height: 88)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.white.opacity(0.1), lineWidth: isSelected ? 2 : 1)
            )

            Text(item.name)
                .font(.caption2)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
        }
        .padding(6)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
    }

    private var placeholderColor: Color {
        switch item.category {
        case .furniture:  return .blue
        case .appliances: return .orange
        case .belongings: return .green
        }
    }
}
