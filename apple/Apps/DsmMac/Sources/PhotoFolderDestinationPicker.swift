import AppKit
import DsmCore
import SwiftUI

/// 在时间轴或文件夹视图中移动照片时，供用户选择目标文件夹。
/// 使用独立的 PhotoLibraryModel 实例，避免影响主照片库状态。
struct PhotoFolderDestinationPicker: View {
    @State private var pickerModel: PhotoLibraryModel
    let sourcePath: String
    let onSelect: (String) -> Void
    let onCancel: () -> Void

    init(
        repository: any PhotoLibraryRepository,
        profileID: UUID?,
        sourcePath: String,
        onSelect: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._pickerModel = State(
            initialValue: PhotoLibraryModel(
                repository: repository,
                profileID: profileID
            )
        )
        self.sourcePath = sourcePath
        self.onSelect = onSelect
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("移动到…")
                    .font(.headline)
                Spacer()
                Button("取消") { onCancel() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            HStack(spacing: 6) {
                Button {
                    Task { await pickerModel.goBack() }
                } label: {
                    Image(systemName: "chevron.backward")
                }
                .buttonStyle(.plain)
                .disabled(!pickerModel.canGoBack)

                Button {
                    Task { await pickerModel.goUp() }
                } label: {
                    Image(systemName: "arrow.turn.up.left")
                }
                .buttonStyle(.plain)
                .disabled(!pickerModel.canGoUp)

                Text(pickerModel.locationTitle)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if pickerModel.isLoading && pickerModel.displayedItems.isEmpty {
                Spacer()
                ProgressView("正在载入文件夹…")
                Spacer()
            } else if let errorMessage = pickerModel.errorMessage {
                Spacer()
                ContentUnavailableView(
                    "无法读取文件夹",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
                Spacer()
            } else {
                folderList
            }

            Divider()

            HStack(spacing: 12) {
                Button("选择当前文件夹") {
                    onSelect(pickerModel.currentPath)
                }
                .buttonStyle(.borderedProminent)
                .disabled(pickerModel.currentPath.isEmpty)

                Spacer()

                Button("取消") { onCancel() }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 480, minHeight: 400)
        .task { await setupPicker() }
    }

    private var folderList: some View {
        List(pickerModel.displayedItems.filter(\.isFolder)) { folder in
            Button {
                Task { await pickerModel.open(folder) }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.blue)
                    Text(folder.name)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
    }

    private func setupPicker() async {
        await pickerModel.loadIfNeeded()

        guard let space = pickerModel.spaces.first(where: { sourcePath.hasPrefix($0.rootPath) }) ?? pickerModel.spaces.first else {
            return
        }
        pickerModel.selectedSpaceID = space.id
        await pickerModel.setBrowseMode(.folders)

        let parentPath = (sourcePath as NSString).deletingLastPathComponent
        let initialPath = parentPath.count >= space.rootPath.count ? parentPath : space.rootPath

        let folderItem = PhotoLibraryItem(
            id: initialPath,
            profileID: pickerModel.activeProfileID ?? UUID(),
            name: (initialPath as NSString).lastPathComponent,
            path: initialPath,
            kind: .folder,
            sizeBytes: nil,
            createdAt: nil,
            modifiedAt: nil,
            fileExtension: nil,
            thumbnailAvailable: nil
        )
        await pickerModel.open(folderItem)
    }
}
