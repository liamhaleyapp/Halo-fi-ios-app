//
//  TransactionNameFormatterTests.swift
//  Halo-fi-IOSTests
//

import Foundation
import Testing
@testable import Halo_fi_IOS

@Suite struct TransactionNameFormatterTests {
    @Test func achDescriptorUsesEntryDescription() {
        let raw = "ORIG CO NAME:GARNALTD ORIG ID:1371913769 DESC DATE:260807 CO ENTRY DESCR:Garna LTD SEC:PPD TRACE#:026073154770111 EED:260806 IND ID: IND NAME:Liam Michael Haley TRN: 2184770111TC"
        #expect(TransactionNameFormatter.clean(raw) == "Garna LTD")
        #expect(TransactionNameFormatter.display(name: raw, merchant: nil) == "Garna LTD")
    }

    @Test func achWithoutEntryFallsBackToOriginator() {
        #expect(TransactionNameFormatter.clean("ORIG CO NAME:ACME PAYROLL ORIG ID:99 DESC DATE:260901 SEC:PPD") == "Acme Payroll")
    }

    @Test func idsAndTrailersAreStripped() {
        #expect(TransactionNameFormatter.clean("ACME PAYROLL PPD ID: 2291") == "Acme Payroll")
        #expect(TransactionNameFormatter.clean("TD ZELLE SENT 624300L0M5ML Z") == "TD Zelle Sent Z")
        #expect(TransactionNameFormatter.clean("SQ *BLUE BOTTLE COFFEE") == "Blue Bottle Coffee")
        #expect(TransactionNameFormatter.clean("AMAZON MKTPL*5Q3F74900") == "Amazon Mktpl")
    }

    @Test func merchantWinsAndMixedCaseIsKept() {
        #expect(TransactionNameFormatter.display(name: "UBER *TRIP 8827", merchant: "Uber") == "Uber")
        #expect(TransactionNameFormatter.clean("Whole Foods Market") == "Whole Foods Market")
    }

    @Test func longNamesAreTruncated() {
        let long = String(repeating: "Verylongname ", count: 8)
        #expect(TransactionNameFormatter.clean(long).count <= TransactionNameFormatter.maxLength)
    }
}


@Suite @MainActor struct TransactionSearchTests {
    private func page(_ name: String) -> TransactionsResponse {
        UITestArchetype.transactionSearchPage(query: name, offset: 0)
    }

    @Test func staleSearchCannotReplaceANewerQueryOrClear() async throws {
        var pending: CheckedContinuation<TransactionsResponse, Error>?
        let oldPage = page("workspace")
        let newPage = page("uber")
        let store = TransactionSearchStore(debounce: .zero) { query, _ in
            if query == "workspace" { return try await withCheckedThrowingContinuation { pending = $0 } }
            return newPage
        }
        let first = Task { await store.search("workspace") }
        while pending == nil { await Task.yield() }
        await store.search("uber")
        #expect(store.results.map(\.name) == newPage.transactions.map(\.name))
        pending?.resume(returning: oldPage)
        await first.value
        #expect(store.query == "uber")
        #expect(store.results.map(\.name) == newPage.transactions.map(\.name))
        await store.search("  ")
        #expect(store.results.isEmpty && !store.isLoading && store.error == nil)
    }

    @Test func paginationPreservesResultsOnFailureAndRetriesSameOffset() async {
        let all = page("workspace").transactions
        var offsets: [Int] = []
        let store = TransactionSearchStore(debounce: .zero) { _, offset in
            offsets.append(offset)
            if offsets.count == 2 { throw URLError(.notConnectedToInternet) }
            return TransactionsResponse(added: 0, cursor: nil, hasMore: offset == 0,
                transactions: offset == 0 ? [all[0]] : [all[1]])
        }
        await store.search("workspace")
        await store.loadMore()
        #expect(store.results.count == 1 && store.error != nil && store.hasMore)
        await store.loadMore()
        #expect(offsets == [0, 1, 1])
        #expect(store.results.count == 2 && !store.hasMore && store.error == nil)
    }

    @Test func cancellingBeforeDebounceAvoidsTheRequest() async {
        var called = false
        let store = TransactionSearchStore(debounce: .seconds(60)) { _, _ in
            called = true
            return TransactionsResponse(added: 0, cursor: nil, hasMore: false, transactions: [])
        }
        let task = Task { await store.search("workspace") }
        await Task.yield()
        task.cancel()
        await task.value
        #expect(!called && !store.isLoading && store.error == nil)
    }
}
