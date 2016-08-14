//
//  CSVImporter.swift
//  CSVImporter
//
//  Created by Cihat Gündüz on 13.01.16.
//  Copyright © 2016 Flinesoft. All rights reserved.
//

import Foundation

/// Importer for CSV files that maps your lines to a specified data structure.
public class CSVImporter<T> {

    // MARK: - Stored Instance Properties

    let data: Data
    let delimiter: String

    var lastProgressReport: Date?

    var progressClosure: ((importedDataLinesCount: Int) -> Void)?
    var finishClosure: ((importedRecords: [T]) -> Void)?
    var failClosure: (() -> Void)?


    // MARK: - Computes Instance Properties

    var shouldReportProgress: Bool {
        get {
            return self.progressClosure != nil &&
                (self.lastProgressReport == nil || Date().timeIntervalSince(self.lastProgressReport!) > 0.1)
        }
    }


    // MARK: - Initializers

    /// Creates a `CSVImporter` object with required configuration options.
    ///
    /// - Parameters:
    ///   - path: The path to the CSV file to import.
    ///   - delimiter: The delimiter used within the CSV file for separating fields. Defaults to ",".
//    public init(path: String, delimiter: String = ",") {
//        self.csvFile = TextFile(path: Path(path))
//        self.delimiter = delimiter
//    }

    public init(data: Data, delimiter: String = ",") {
        self.data = data
        self.delimiter = delimiter
    }
    

    // MARK: - Instance Methods

    /// Starts importing the records within the CSV file line by line.
    ///
    /// - Parameters:
    ///   - mapper: A closure to map the data received in a line to your data structure.
    /// - Returns: `self` to enable consecutive method calls (e.g. `importer.startImportingRecords {...}.onProgress {...}`).
    public func startImportingRecords(mapper closure: (recordValues: [String]) -> T) -> Self {
        DispatchQueue.global(qos: DispatchQoS.QoSClass.userInitiated).async {
            var importedRecords: [T] = []

            let importedLinesWithSuccess = self.importLines { valuesInLine in
                let newRecord = closure(recordValues: valuesInLine)
                importedRecords.append(newRecord)

                self.reportProgressIfNeeded(importedRecords)
            }

            if importedLinesWithSuccess {
                self.reportFinish(importedRecords)
            } else {
                self.reportFail()
            }
        }

        return self
    }

    /// Starts importing the records within the CSV file line by line interpreting the first line as the data structure.
    ///
    /// - Parameters:
    ///   - structure: A closure for doing something with the found structure within the first line of the CSV file.
    ///   - recordMapper: A closure to map the dictionary data interpreted from a line to your data structure.
    /// - Returns: `self` to enable consecutive method calls (e.g. `importer.startImportingRecords {...}.onProgress {...}`).
    public func startImportingRecords(structure structureClosure: (headerValues: [String]) -> Void, recordMapper closure: (recordValues: [String: String]) -> T) -> Self {
        DispatchQueue.global(qos: DispatchQoS.QoSClass.userInitiated).async {
            var recordStructure: [String]?
            var importedRecords: [T] = []

            let importedLinesWithSuccess = self.importLines { valuesInLine in

                if recordStructure == nil {
                    recordStructure = valuesInLine
                    structureClosure(headerValues: valuesInLine)
                } else {
                    assert(recordStructure!.count == valuesInLine.count)
                    var structuredValuesInLine = [String: String]()
                    recordStructure!.enumerated().forEach { index, element in
                        structuredValuesInLine[element] = valuesInLine[index]
                    }
                    
                    let newRecord = closure(recordValues: structuredValuesInLine)
                    importedRecords.append(newRecord)

                    self.reportProgressIfNeeded(importedRecords)
                }
            }

            if importedLinesWithSuccess {
                self.reportFinish(importedRecords)
            } else {
                self.reportFail()
            }
        }

        return self
    }

    /// Imports all lines one by one and
    ///
    /// - Parameters:
    ///   - valuesInLine: The values found within a line.
    /// - Returns: `true` on finish or `false` if can't read file.
    func importLines(_ closure: (valuesInLine: [String]) -> Void) -> Bool {
        let stream = InputStream(data: data)
        stream.open()
        forEachLine(of: stream) { line in
            let valuesInLine = self.readValuesInLine(line)
            closure(valuesInLine: valuesInLine)
        }
        stream.close()
        
        // FIXME: importLines always returns true, there is no more file opening that can fail
        return true
    }

    /// Reads the line and returns the fields found. Handles double quotes according to RFC 4180.
    ///
    /// - Parameters:
    ///   - line: The line to read values from.
    /// - Returns: An array of values found in line.
    func readValuesInLine(_ line: String) -> [String] {
        var correctedLine = line.replacingOccurrences(of: "\(delimiter)\"\"\(delimiter)", with: delimiter+delimiter)
        correctedLine = correctedLine.replacingOccurrences(of: "\r\n", with: "\n")

        if correctedLine.hasPrefix("\"\"\(delimiter)") {
            correctedLine = correctedLine.substring(from: correctedLine.index(correctedLine.startIndex, offsetBy: 2))
        }
        if correctedLine.hasSuffix("\(delimiter)\"\"") || correctedLine.hasSuffix("\(delimiter)\"\"\n") {
            correctedLine = correctedLine.substring(to: correctedLine.index(correctedLine.startIndex, offsetBy: correctedLine.utf16.count - 2))
        }

        let substitute = "\u{001a}"
        correctedLine = correctedLine.replacingOccurrences(of: "\"\"", with: substitute)
        var components = correctedLine.components(separatedBy: delimiter)

        var index = 0
        while index < components.count {
            let element = components[index]

            let startPartRegex = try! NSRegularExpression(pattern: "\\A\"[^\"]*\\z", options: .caseInsensitive) // swiftlint:disable:this force_try

            if index < components.count-1 && startPartRegex.firstMatch(in: element, options: .anchored, range: element.fullRange) != nil {
                var elementsToMerge = [element]

                let middlePartRegex = try! NSRegularExpression(pattern: "\\A[^\"]*\\z", options: .caseInsensitive) // swiftlint:disable:this force_try
                let endPartRegex = try! NSRegularExpression(pattern: "\\A[^\"]*\"\\z", options: .caseInsensitive) // swiftlint:disable:this force_try

                while middlePartRegex.firstMatch(in: components[index+1], options: .anchored, range: components[index+1].fullRange) != nil {
                    elementsToMerge.append(components[index+1])
                    components.remove(at: index+1)
                }

                if endPartRegex.firstMatch(in: components[index+1], options: .anchored, range: components[index+1].fullRange) != nil {
                    elementsToMerge.append(components[index+1])
                    components.remove(at: index+1)
                    components[index] = elementsToMerge.joined(separator: delimiter)
                } else {
                    print("Invalid CSV format in line, opening \" must be closed – line: \(line).")
                }
            }

            index += 1
        }

        components = components.map { $0.replacingOccurrences(of: "\"", with: "") }
        components = components.map { $0.replacingOccurrences(of: substitute, with: "\"") }

        return components
    }

    /// Defines callback to be called in case reading the CSV file fails.
    ///
    /// - Parameters:
    ///   - closure: The closure to be called on failure.
    /// - Returns: `self` to enable consecutive method calls (e.g. `importer.startImportingRecords {...}.onProgress {...}`).
    public func onFail(_ closure: () -> Void) -> Self {
        self.failClosure = closure
        return self
    }

    /// Defines callback to be called from time to time.
    /// Use this to indicate progress to a user when importing bigger files.
    ///
    /// - Parameters:
    ///   - closure: The closure to be called on progress. Takes the current count of imported lines as argument.
    /// - Returns: `self` to enable consecutive method calls (e.g. `importer.startImportingRecords {...}.onProgress {...}`).
    public func onProgress(_ closure: (importedDataLinesCount: Int) -> Void) -> Self {
        self.progressClosure = closure
        return self
    }

    /// Defines callback to be called when the import finishes.
    ///
    /// - Parameters:
    ///   - closure: The closure to be called on finish. Takes the array of all imported records mapped to as its argument.
    public func onFinish(_ closure: (importedRecords: [T]) -> Void) {
        self.finishClosure = closure
    }


    // MARK: - Helper Methods

    func reportFail() {
        if let failClosure = self.failClosure {
            DispatchQueue.main.async {
                failClosure()
            }
        }
    }

    func reportProgressIfNeeded(_ importedRecords: [T]) {
        if self.shouldReportProgress {
            self.lastProgressReport = Date()

            if let progressClosure = self.progressClosure {
                DispatchQueue.main.async {
                    progressClosure(importedDataLinesCount: importedRecords.count)
                }
            }
        }

    }

    func reportFinish(_ importedRecords: [T]) {
        if let finishClosure = self.finishClosure {
            DispatchQueue.main.async {
                finishClosure(importedRecords: importedRecords)
            }
        }
    }


}


// MARK: - Helpers

extension String {
    var fullRange: NSRange {
        return NSRange(location: 0, length: self.utf16.count)
    }
}



private func forEachLine(of stream:InputStream, block:(String) -> ()) {

    let delimiter = "\n"
    let encoding = String.Encoding.utf8
    let chunkSize: Int = 4096

    let delimData = delimiter.data(using: encoding)!
    var buffer = Data(capacity: chunkSize)
    
    while buffer.count > 0 || stream.hasBytesAvailable {
    
        // Read data chunks from file until a line delimiter is found.
        var range = buffer.range(of: delimData)
        while range == nil && stream.hasBytesAvailable {
            var tmpData = Data(capacity: chunkSize)
            
            // FIXME: this foo thing is bullshit, but tmpData does not get updated with the values from the stream.
            let foo = tmpData.withUnsafeMutableBytes { (bytes: UnsafeMutablePointer<UInt8>)->Data in
                let numberOfBytes = stream.read(bytes, maxLength: chunkSize)
                return Data(bytes: bytes, count: numberOfBytes)
            }
            
            tmpData = foo
            
            if tmpData.count == 0 {
                // EOF or read error.
                if buffer.count > 0 {
                    // Buffer contains last line in file (not terminated by delimiter).
                    if let line = String(data: buffer, encoding: encoding) {
                        block(line)
                    }
                    return
                }
                // No more lines.
                return
            }
            
            buffer.append(tmpData)
            range = buffer.range(of: delimData)
        }
        
        // Convert complete line (excluding the delimiter) to a string.
        if let range = range, let line = String(data: buffer.subdata(in: 0..<range.lowerBound), encoding: encoding) {
            block(line)
            
            // Remove line (and the delimiter) from the buffer.
            buffer.removeSubrange(0..<range.upperBound)
        } else if let line = String(data: buffer, encoding:encoding) {
            block(line)
            buffer.removeAll()
        }
        
        
    }

}

