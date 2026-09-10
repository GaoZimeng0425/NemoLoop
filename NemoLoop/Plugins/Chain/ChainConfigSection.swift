// NemoLoop/Plugins/Chain/ChainConfigSection.swift
import AppKit
import Luminare
import SwiftUI

/// Plugins-tab config area for Chains: the saved-chain list, each row
/// expanding inline into the editor (name, icon chips, steps with reorder,
/// repeat count, inter-step delay). "Add Step" opens the shared action
/// picker in .chainStep context. Every edit writes straight through the
/// store binding — the store clamps, and mounted blades follow via the
/// op id (the chain's UUID).
struct ChainConfigSection: View {
    @Bindable var store: ChainStore
    @State private var editingID: UUID?
    @State private var stepPicker: StepPickerTarget?

    /// `popover(item:)` needs an Identifiable anchor; UUID has none built in.
    private struct StepPickerTarget: Identifiable {
        let chainID: UUID
        var id: UUID { chainID }
    }

    var body: some View {
        VStack(spacing: 6) {
            ForEach(store.chains) { chain in
                if chain.id == editingID {
                    ChainEditor(chain: binding(for: chain),
                                onAddStep: { stepPicker = StepPickerTarget(chainID: chain.id) },
                                onDelete: {
                                    store.remove(id: chain.id)
                                    editingID = nil
                                })
                } else {
                    chainRow(chain)
                }
            }
            Button {
                let chain = ChainDefinition(name: "New Chain")
                if store.add(chain) {
                    withAnimation(.smooth(duration: 0.2)) { editingID = chain.id }
                }
            } label: {
                Label("New Chain", systemImage: "plus")
            }
            .buttonStyle(.luminareCompact)
            .disabled(store.chains.count >= ChainStore.maxChains)
        }
        .popover(item: $stepPicker) { target in
            ActionPickerPopover(
                context: .chainStep,
                onPick: { outcome in
                    // chainStep context never yields .wholePlugin; the guard
                    // keeps the exhaustive switch honest anyway.
                    guard case .action(let action) = outcome,
                          let index = store.chains.firstIndex(where: { $0.id == target.chainID }),
                          store.chains[index].steps.count < ChainDefinition.maxSteps else { return }
                    var chain = store.chains[index]
                    chain.steps.append(action)
                    store.update(chain)
                },
                onDismiss: { stepPicker = nil })
        }
    }

    private func chainRow(_ chain: ChainDefinition) -> some View {
        Button {
            withAnimation(.smooth(duration: 0.2)) { editingID = chain.id }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: chain.symbolName)
                    .font(.system(size: 14))
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(chain.name)
                    Text("\(chain.steps.count) step\(chain.steps.count == 1 ? "" : "s") × \(chain.repeatCount)×")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(90))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func binding(for chain: ChainDefinition) -> Binding<ChainDefinition> {
        Binding(
            get: { store.chains.first { $0.id == chain.id } ?? chain },
            set: { store.update($0) }   // store-side clamp keeps fields in spec range
        )
    }
}

/// One expanded chain: identity, icon, steps, repeat/delay, delete.
private struct ChainEditor: View {
    @Binding var chain: ChainDefinition
    let onAddStep: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Name", text: $chain.name)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 6) {
                ForEach(ChainDefinition.presetSymbols, id: \.self) { symbol in
                    Button {
                        chain.symbolName = symbol
                    } label: {
                        Image(systemName: symbol)
                            .font(.system(size: 12))
                            .frame(width: 26, height: 20)
                    }
                    .buttonStyle(.plain)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(chain.symbolName == symbol ? Color.accentColor.opacity(0.3) : .clear)
                    )
                }
            }

            ForEach(chain.steps.indices, id: \.self) { index in
                stepRow(index)
            }

            HStack {
                Button(action: onAddStep) {
                    Label("Add Step", systemImage: "plus")
                }
                .buttonStyle(.luminareCompact)
                .disabled(chain.steps.count >= ChainDefinition.maxSteps)
                Spacer()
                Stepper("×\(chain.repeatCount)", value: $chain.repeatCount,
                        in: ChainDefinition.minRepeatCount...ChainDefinition.maxRepeatCount)
                    .fixedSize()
                Stepper("\(chain.interStepDelay, format: .number.precision(.fractionLength(1)))s",
                        value: $chain.interStepDelay,
                        in: 0...ChainDefinition.maxDelaySeconds, step: 0.1)
                    .fixedSize()
            }

            Button(role: .destructive, action: onDelete) {
                Label("Delete Chain", systemImage: "trash")
            }
            .buttonStyle(.luminareCompact)
        }
        .padding(.vertical, 4)
    }

    private func stepRow(_ index: Int) -> some View {
        let step = chain.steps[index]
        return HStack(spacing: 6) {
            Text("\(index + 1).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .trailing)
            stepIcon(step)
            Text(ActionResolver.name(for: step))
                .lineLimit(1)
            Spacer()
            Button { move(index, by: -1) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.luminareCompact)
                .disabled(index == 0)
            Button { move(index, by: 1) } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.luminareCompact)
                .disabled(index == chain.steps.count - 1)
            Button { chain.steps.remove(at: index) } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.luminareCompact)
        }
    }

    @ViewBuilder
    private func stepIcon(_ step: SlotAction) -> some View {
        switch step {
        case .app(let url), .folder(let url):
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false)))
                .resizable()
                .frame(width: 16, height: 16)
        case .plugin, .pluginOp:
            Image(systemName: ActionResolver.symbolName(for: step) ?? "circle.dashed")
                .frame(width: 16)
        }
    }

    private func move(_ index: Int, by delta: Int) {
        let target = index + delta
        guard chain.steps.indices.contains(index), chain.steps.indices.contains(target) else { return }
        chain.steps.swapAt(index, target)
    }
}
