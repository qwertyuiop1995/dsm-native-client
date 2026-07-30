import FileProvider
import Foundation

final class ProviderEnumerator: NSObject, NSFileProviderEnumerator, @unchecked Sendable {
    private let containerIdentifier: NSFileProviderItemIdentifier
    private let runtime: ProviderRuntime
    private let operations = ProviderOperationRegistry()
    private let pageSize = 500
    private let anchor = NSFileProviderSyncAnchor(Data("v1".utf8))

    init(
        containerIdentifier: NSFileProviderItemIdentifier,
        runtime: ProviderRuntime
    ) {
        self.containerIdentifier = containerIdentifier
        self.runtime = runtime
        super.init()
    }

    func invalidate() {
        operations.cancelAll()
    }

    func enumerateItems(
        for observer: NSFileProviderEnumerationObserver,
        startingAt page: NSFileProviderPage
    ) {
        let offset = Int(String(data: page.rawValue, encoding: .utf8) ?? "") ?? 0
        let observerBox = UncheckedSendableBox(observer)
        let operationID = UUID()
        let operation = Task {
            defer { operations.remove(operationID) }
            do {
                let result = try await runtime.enumerate(
                    containerIdentifier: containerIdentifier,
                    offset: offset,
                    limit: pageSize
                )
                observerBox.value.didEnumerate(result.items)
                let nextPage = result.nextOffset.map {
                    NSFileProviderPage(Data(String($0).utf8))
                }
                observerBox.value.finishEnumerating(upTo: nextPage)
            } catch {
                observerBox.value.finishEnumeratingWithError(error)
            }
        }
        operations.insert(operation, id: operationID)
    }

    func enumerateChanges(
        for observer: NSFileProviderChangeObserver,
        from anchor: NSFileProviderSyncAnchor
    ) {
        observer.finishEnumeratingChanges(upTo: self.anchor, moreComing: false)
    }

    func currentSyncAnchor(
        completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void
    ) {
        completionHandler(anchor)
    }
}

final class UncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}
