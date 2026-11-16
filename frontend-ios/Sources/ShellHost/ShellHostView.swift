import SwiftUI
import UniformTypeIdentifiers
import ShellUI

/// `LibraryView` on a `ShellHostModel`: the real shell screen, plus the read-only log sheet and the notice alert. The
/// launch arguments of the demo (initial selection and so on) are not part of it.
public struct ShellHostView: View {
    @Bindable private var model: ShellHostModel
    private let initialSelection: String?
    private let initialDetailOpen: Bool
    @State private var isImportingGameDump = false

    public init(model: ShellHostModel, initialSelection: String? = nil, initialDetailOpen: Bool = false) {
        self.model = model
        self.initialSelection = initialSelection
        self.initialDetailOpen = initialDetailOpen
    }

    public var body: some View {
        LibraryView(games: model.details, controllers: model.controllers, actions: model.actions, input: model.input,
                    initialSelection: initialSelection, initialDetailOpen: initialDetailOpen, globalPadMap: model.globalPadMap,
                    padMerge: model.padMerge, padSnapshot: model.padSnapshot,
                    signingWarning: model.signingWarning,
                    onDismissSigningWarning: { model.dismissSigningWarning() },
                    canOpenHomeButtonSettings: model.canOpenHomeButtonSettings)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Spacer()
                        Button {
                            model.refreshImportedGameDumps()
                        } label: {
                            Label("刷新游戏文件", systemImage: "arrow.clockwise")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(.thinMaterial, in: Capsule())
                        }
                        .accessibilityIdentifier("library.refresh-imported-games")
                        Button {
                            isImportingGameDump = true
                        } label: {
                            Label("导入 NSP/XCI", systemImage: "doc.badge.plus")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(.thinMaterial, in: Capsule())
                        }
                        .accessibilityIdentifier("library.import-game-dump")
                        Button {
                            model.importGameFramework()
                        } label: {
                            Label("导入已构建游戏", systemImage: "square.and.arrow.down")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(.thinMaterial, in: Capsule())
                        }
                        .accessibilityIdentifier("library.import-built-game")
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                        Text("ImportedGames：\(model.importedGameDumps.count) 个文件")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    Text("将 NSP/XCI 文件放入“文件”App 中的 ImportedGames 文件夹，然后点“刷新游戏文件”。当前版本仅支持存储和管理文件，暂不支持直接启动 NSP/XCI。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)
                    if !model.importedGameDumps.isEmpty {
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(model.importedGameDumps) { dump in
                                    HStack(spacing: 10) {
                                        Image(systemName: dump.fileType == "XCI" ? "externaldrive" : "doc.zipper")
                                            .foregroundStyle(.secondary)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(dump.name)
                                                .font(.caption)
                                                .lineLimit(1)
                                                .textSelection(.enabled)
                                            Text("\(dump.fileType) · \(dump.sizeLabel)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 4)
                                        Button(role: .destructive) {
                                            model.deleteImportedGameDump(dump)
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.caption.weight(.semibold))
                                                .padding(8)
                                        }
                                        .accessibilityLabel("删除 \(dump.name)")
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 5)
                                }
                            }
                        }
                        .frame(maxHeight: 132)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(ShellPalette.background)
            }
            .fileImporter(isPresented: $isImportingGameDump, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first { model.importGameDump(from: url) }
                case .failure(let error):
                    model.notice = error.localizedDescription
                }
            }
            .disabled(model.launchingGame)
            .overlay {
                if model.launchingGame {
                    ZStack {
                        Color.black.opacity(0.45).ignoresSafeArea()
                        ProgressView { Text("Preparing game…", bundle: .module) }
                            .padding(24)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                            .accessibilityIdentifier("launch.progress")
                    }
                }
            }
            .sheet(item: $model.cloudConflict, onDismiss: {
                model.cancelCloudConflictIfPending()
            }) { prompt in
                ScrollView {
                    CloudSaveConflictView(prompt: prompt) { decision in
                        model.resolveCloudConflict(decision)
                    }
                }
                .presentationDetents([.medium, .large])
                .presentationBackground(ShellPalette.background)
            }
            .sheet(item: $model.log) { LogView(log: $0) }
            .alert(Text(verbatim: hostText("NX2Apple")), isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
                Button(hostText("OK")) { model.notice = nil }
            } message: { Text(model.notice ?? "") }
            .onAppear { model.startControllers() }
            .onDisappear { model.stopControllers() }
    }
}

/// A game's log, read-only.
struct LogView: View {
    let log: LogPresentation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if log.truncated { Text(hostText("Only the end of the log is shown.")).font(.footnote).foregroundStyle(.secondary) }
                    Text(verbatim: log.text ?? hostText("This game has no log yet. It appears after the game has run."))
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(log.text == nil ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
            .navigationTitle(log.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(hostText("Done")) { dismiss() }.accessibilityIdentifier("log.close") } }
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("log.sheet")
    }
}
