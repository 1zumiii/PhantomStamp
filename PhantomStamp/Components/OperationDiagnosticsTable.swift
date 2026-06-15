//
//  OperationDiagnosticsTable.swift
//  PhantomStamp
//
//  Grouped key–value tables for history detail and list metric grids.
//

import SwiftUI

struct OperationDiagnosticsRow: Identifiable {
    let id: String
    let title: String
    let value: String
    var systemImage: String? = nil
    var valueMonospaced: Bool = true
}

struct OperationDiagnosticsSectionModel: Identifiable {
    let id: String
    let title: String
    let rows: [OperationDiagnosticsRow]
}

/// Sectioned table resembling Advanced Mode stat readouts (label left, value right).
struct OperationDiagnosticsTable: View {
    let sections: [OperationDiagnosticsSectionModel]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(sections) { section in
                if !section.rows.isEmpty {
                    sectionBlock(section)
                }
            }
        }
    }

    @ViewBuilder
    private func sectionBlock(_ section: OperationDiagnosticsSectionModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                    rowLine(row)
                    if index < section.rows.count - 1 {
                        Divider()
                            .padding(.leading, row.systemImage == nil ? 16 : 44)
                    }
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.phantomCardBackground)
            }
        }
    }

    private func rowLine(_ row: OperationDiagnosticsRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let icon = row.systemImage {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 20, alignment: .center)
            }

            Text(row.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(row.value)
                .font(row.valueMonospaced ? .subheadline.monospacedDigit().weight(.semibold) : .subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
