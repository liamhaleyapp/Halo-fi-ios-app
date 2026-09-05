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
