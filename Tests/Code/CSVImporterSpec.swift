
//
//  CSVImporterSpec.swift
//  CSVImporterSpec
//
//  Created by Cihat Gündüz on 13.01.16.
//  Copyright © 2016 Flinesoft. All rights reserved.
//

import XCTest

@testable import CSVImporter


class CSVImporterSpec: XCTestCase {

    func test_imports_data_from_CSV_file_without_headers() {
        let e = expectation(description: "")

        let url = Bundle(for: CSVImporterSpec.classForCoder()).url(forResource: "Teams", withExtension: "csv")!
        var recordValues: [[String]]?

        let data = try! Data(contentsOf: url)
        let importer = CSVImporter<[String]>(data: data)

        importer.startImportingRecords { recordValues -> [String] in
            return recordValues
        }.onFail {
            XCTAssert(false)
            e.fulfill()
        }.onProgress { importedDataLinesCount in
            print("Progress: \(importedDataLinesCount)")
        }.onFinish { importedRecords in
            print("Did finish import, first array: \(importedRecords.first)")
            recordValues = importedRecords
            e.fulfill()
        }
        
        waitForExpectations(timeout: 10) { r in
            XCTAssert(recordValues != nil)
            XCTAssert(recordValues!.count == 2776)
        }
    }

    func test_imports_data_from_CSV_file_special_characters() {
        let e = expectation(description: "")

        let url = Bundle(for: CSVImporterSpec.classForCoder()).url(forResource: "CommaSemicolonQuotes", withExtension: "csv")!
        var recordValues: [[String]]?

        let data = try! Data(contentsOf: url)
        let importer = CSVImporter<[String]>(data: data, delimiter: ";")

        importer.startImportingRecords { recordValues -> [String] in
            return recordValues
        }.onFail {
            XCTAssert(false)
            e.fulfill()
        }.onProgress { importedDataLinesCount in
            print("Progress: \(importedDataLinesCount)")
        }.onFinish { importedRecords in
            print("Did finish import, first array: \(importedRecords.first)")
            recordValues = importedRecords
            e.fulfill()
        }

        waitForExpectations(timeout: 10) { r in
            XCTAssert(recordValues != nil)
            XCTAssert(recordValues?.first != nil)
            XCTAssert(recordValues!.first! == [
                "",
                "Text, with \"comma\"; and 'semicolon'.",
                "",
                "Another text with \"comma\"; and 'semicolon'!",
                "Text without special chars.",
                ""
                ])
        }
    }

    func test_imports_data_from_CSV_file_with_headers() {
        let e = expectation(description: "")

        let url = Bundle(for: CSVImporterSpec.classForCoder()).url(forResource: "Teams", withExtension: "csv")!
        var recordValues: [[String: String]]?

        let data = try! Data(contentsOf: url)
        let importer = CSVImporter<[String: String]>(data: data)

        importer.startImportingRecords(structure: { (headerValues) -> Void in
            print(headerValues)
        }, recordMapper: { (recordValues) -> [String : String] in
            return recordValues
        }).onFail {
            XCTAssert(false)
            e.fulfill()
        }.onProgress { importedDataLinesCount in
            print("Progress: \(importedDataLinesCount)")
        }.onFinish { importedRecords in
            print("Did finish import, first array: \(importedRecords.first)")
            recordValues = importedRecords
            e.fulfill()
        }

        waitForExpectations(timeout: 10) { r in
            XCTAssert(recordValues != nil)
            XCTAssert(recordValues!.count == 2775)
        }

    }
}
