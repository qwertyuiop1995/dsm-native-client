import FileProvider
import Foundation

final class FileProviderExtension:
    NSObject,
    NSFileProviderReplicatedExtension,
    @unchecked Sendable
{
    private let runtime: ProviderRuntime
    private let operations = ProviderOperationRegistry()

    required init(domain: NSFileProviderDomain) {
        let mappingIdentifier: String
        if #available(macOS 15.0, *),
           let value = domain.userInfo?["mappingID"] as? String {
            mappingIdentifier = value
        } else {
            mappingIdentifier = domain.identifier.rawValue
        }
        runtime = ProviderRuntime(mappingIdentifier: mappingIdentifier)
        super.init()
    }

    func invalidate() {
        operations.cancelAll()
        Task {
            await runtime.invalidate()
        }
    }

    func item(
        for identifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest,
        completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void
    ) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        let completionBox = UncheckedSendableBox(completionHandler)
        let operationID = UUID()
        let operation = Task {
            defer { operations.remove(operationID) }
            do {
                completionBox.value(try await runtime.item(for: identifier), nil)
                progress.completedUnitCount = 1
            } catch {
                completionBox.value(
                    nil,
                    ProviderErrorMapper.map(error, itemIdentifier: identifier)
                )
            }
        }
        operations.insert(operation, id: operationID)
        progress.cancellationHandler = {
            operation.cancel()
        }
        return progress
    }

    func fetchContents(
        for itemIdentifier: NSFileProviderItemIdentifier,
        version requestedVersion: NSFileProviderItemVersion?,
        request: NSFileProviderRequest,
        completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void
    ) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        let completionBox = UncheckedSendableBox(completionHandler)
        let sendableRequestedVersion = requestedVersion.map {
            ProviderRequestedVersion(
                content: $0.contentVersion,
                metadata: $0.metadataVersion
            )
        }
        let operationID = UUID()
        let operation = Task {
            defer { operations.remove(operationID) }
            do {
                let result = try await runtime.fetchContents(
                    for: itemIdentifier,
                    requestedVersion: sendableRequestedVersion
                ) { completedBytes, totalBytes in
                    if let totalBytes, totalBytes > 0 {
                        progress.totalUnitCount = totalBytes
                    }
                    progress.completedUnitCount = min(
                        max(completedBytes, 0),
                        progress.totalUnitCount
                    )
                }
                completionBox.value(result.0, result.1, nil)
                progress.completedUnitCount = progress.totalUnitCount
            } catch {
                completionBox.value(
                    nil,
                    nil,
                    ProviderErrorMapper.map(
                        error,
                        itemIdentifier: itemIdentifier
                    )
                )
            }
        }
        operations.insert(operation, id: operationID)
        progress.cancellationHandler = {
            operation.cancel()
        }
        return progress
    }

    func createItem(
        basedOn itemTemplate: NSFileProviderItem,
        fields: NSFileProviderItemFields,
        contents url: URL?,
        options: NSFileProviderCreateItemOptions = [],
        request: NSFileProviderRequest,
        completionHandler: @escaping (
            NSFileProviderItem?,
            NSFileProviderItemFields,
            Bool,
            Error?
        ) -> Void
    ) -> Progress {
        completionHandler(nil, [], false, CocoaError(.featureUnsupported))
        return Progress(totalUnitCount: 0)
    }

    func modifyItem(
        _ item: NSFileProviderItem,
        baseVersion version: NSFileProviderItemVersion,
        changedFields: NSFileProviderItemFields,
        contents newContents: URL?,
        options: NSFileProviderModifyItemOptions = [],
        request: NSFileProviderRequest,
        completionHandler: @escaping (
            NSFileProviderItem?,
            NSFileProviderItemFields,
            Bool,
            Error?
        ) -> Void
    ) -> Progress {
        completionHandler(nil, [], false, CocoaError(.featureUnsupported))
        return Progress(totalUnitCount: 0)
    }

    func deleteItem(
        identifier: NSFileProviderItemIdentifier,
        baseVersion version: NSFileProviderItemVersion,
        options: NSFileProviderDeleteItemOptions = [],
        request: NSFileProviderRequest,
        completionHandler: @escaping (Error?) -> Void
    ) -> Progress {
        completionHandler(CocoaError(.featureUnsupported))
        return Progress(totalUnitCount: 0)
    }

    func enumerator(
        for containerItemIdentifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest
    ) throws -> NSFileProviderEnumerator {
        ProviderEnumerator(
            containerIdentifier: containerItemIdentifier,
            runtime: runtime
        )
    }
}

final class ProviderOperationRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var operations: [UUID: Task<Void, Never>] = [:]
    private var completedBeforeInsert: Set<UUID> = []

    func insert(_ operation: Task<Void, Never>, id: UUID) {
        lock.lock()
        if completedBeforeInsert.remove(id) == nil {
            operations[id] = operation
        }
        lock.unlock()
    }

    func remove(_ id: UUID) {
        lock.lock()
        if operations.removeValue(forKey: id) == nil {
            completedBeforeInsert.insert(id)
        }
        lock.unlock()
    }

    func cancelAll() {
        lock.lock()
        let pending = Array(operations.values)
        operations.removeAll()
        completedBeforeInsert.removeAll()
        lock.unlock()
        for operation in pending {
            operation.cancel()
        }
    }
}
