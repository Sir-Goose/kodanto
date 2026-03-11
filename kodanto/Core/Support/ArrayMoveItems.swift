import Foundation

extension Array {
    mutating func moveItems(fromOffsets source: IndexSet, toOffset destination: Int) {
        let movingItems = source.map { self[$0] }
        var insertionIndex = destination

        for index in source.sorted(by: >) {
            remove(at: index)
            if index < insertionIndex {
                insertionIndex -= 1
            }
        }

        insert(contentsOf: movingItems, at: insertionIndex)
    }
}
