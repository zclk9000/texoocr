import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var selectedItem: HistoryItem?
    @State private var formulaHeight: CGFloat = 80
    @State private var editedLatex = ""

    var filteredHistory: [HistoryItem] {
        if searchText.isEmpty {
            return appState.history
        }
        return appState.history.filter { $0.latex.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(filteredHistory, selection: Binding(
                    get: { selectedItem?.id },
                    set: { id in
                        selectedItem = appState.history.first { $0.id == id }
                        editedLatex = selectedItem?.latex ?? ""
                    }
                )) { item in
                    HStack(spacing: 8) {
                        if let data = item.imageData, let img = NSImage(data: data) {
                            Image(nsImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 40, height: 40)
                                .cornerRadius(4)
                                .background(Color.white.cornerRadius(4))
                        } else {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.quaternary)
                                .frame(width: 40, height: 40)
                                .overlay(Image(systemName: "function").foregroundStyle(.secondary))
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.latex)
                                .font(.system(size: 11, design: .monospaced))
                                .lineLimit(2)
                            Text(formatTimestamp(item.timestamp))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                    .tag(item.id)
                }
                .searchable(text: $searchText, prompt: L.searchPrompt)

                HStack {
                    Text("\(filteredHistory.count) \(L.items)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L.clearAll) {
                        appState.clearHistory()
                        selectedItem = nil
                    }
                    .font(.system(size: 11))
                    .disabled(appState.history.isEmpty)
                }
                .padding(8)
            }
            .frame(minWidth: 260)

            if let item = selectedItem {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let imageData = item.imageData, let image = NSImage(data: imageData) {
                            GroupBox(L.capturedImage) {
                                Image(nsImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxHeight: 180)
                                    .frame(maxWidth: .infinity)
                                    .background(Color.white)
                                    .cornerRadius(4)
                            }
                        }

                        GroupBox(L.renderedFormula) {
                            LaTeXRenderView(latex: editedLatex, contentHeight: $formulaHeight)
                                .frame(height: formulaHeight)
                                .frame(maxWidth: .infinity)
                        }

                        GroupBox(L.latexSource) {
                            VStack(alignment: .leading, spacing: 6) {
                                TextEditor(text: $editedLatex)
                                    .font(.system(size: 13, design: .monospaced))
                                    .frame(minHeight: 60, maxHeight: 160)
                                    .padding(2)
                                    .background(.background.opacity(0.5))
                                    .cornerRadius(4)
                                    .scrollContentBackground(.hidden)

                                HStack(spacing: 10) {
                                    if editedLatex != item.latex {
                                        Button(L.save) {
                                            appState.updateHistoryItem(id: item.id, latex: editedLatex)
                                            selectedItem = appState.history.first { $0.id == item.id }
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.small)

                                        Button(L.revert) {
                                            editedLatex = item.latex
                                        }
                                        .controlSize(.small)
                                    }

                                    Spacer()

                                    Button(L.copy) {
                                        appState.copyToClipboard(editedLatex)
                                    }
                                    Button(L.copyInline) {
                                        appState.copyToClipboard("$\(editedLatex)$")
                                    }
                                    Button(L.copyDisplay) {
                                        appState.copyToClipboard("$$\(editedLatex)$$")
                                    }
                                    Button(L.copyParens) {
                                        appState.copyToClipboard("\\(\(editedLatex)\\)")
                                    }
                                }
                                .font(.system(size: 11))
                            }
                        }

                        HStack {
                            Spacer()
                            Text(formatTimestamp(item.timestamp))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                }
                .frame(minWidth: 350)
            } else {
                VStack {
                    Spacer()
                    Image(systemName: "function")
                        .font(.system(size: 36))
                        .foregroundStyle(.quaternary)
                    Text(L.selectItem)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                    Spacer()
                }
                .frame(minWidth: 350)
            }
        }
    }

    private func formatTimestamp(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)

        if interval < 60 {
            return "\(Int(interval))s ago"
        } else if interval < 3600 {
            let m = Int(interval / 60)
            let s = Int(interval) % 60
            return String(format: "%d:%02d ago", m, s)
        } else if interval < 86400 {
            let h = Int(interval / 3600)
            let m = Int(interval / 60) % 60
            let s = Int(interval) % 60
            return String(format: "%d:%02d:%02d ago", h, m, s)
        } else {
            let days = Int(interval / 86400)
            return days == 1 ? "1 day ago" : "\(days) days ago"
        }
    }
}
