import Foundation

enum SpreadsheetExport {
    static func generateXLSX(headers: [String], rows: [[String]]) -> Data? {
        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
            <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
            <Default Extension="xml" ContentType="application/xml"/>
            <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
            <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
        </Types>
        """

        let rels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
        """

        let workbook = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
            <sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets>
        </workbook>
        """

        let workbookRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
        </Relationships>
        """

        var sheetRows = ""
        var rowIndex = 1
        let allRows = [headers] + rows
        for row in allRows {
            sheetRows += "<row r=\"\(rowIndex)\">"
            var colIndex = 1
            for cell in row {
                let escaped = cell
                    .replacingOccurrences(of: "&", with: "&amp;")
                    .replacingOccurrences(of: "<", with: "&lt;")
                    .replacingOccurrences(of: ">", with: "&gt;")
                    .replacingOccurrences(of: "\"", with: "&quot;")
                let colRef = columnRef(index: colIndex)
                sheetRows += "<c r=\"\(colRef)\(rowIndex)\" t=\"inlineStr\"><is><t>\(escaped)</t></is></c>"
                colIndex += 1
            }
            sheetRows += "</row>"
            rowIndex += 1
        }

        let sheet = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
            <cols><col min="1" max="\(headers.count)" width="30" customWidth="1"/></cols>
            <sheetData>\(sheetRows)</sheetData>
        </worksheet>
        """

        let entries: [(name: String, data: Data)] = [
            ("[Content_Types].xml", Data(contentTypes.utf8)),
            ("_rels/.rels", Data(rels.utf8)),
            ("xl/workbook.xml", Data(workbook.utf8)),
            ("xl/_rels/workbook.xml.rels", Data(workbookRels.utf8)),
            ("xl/worksheets/sheet1.xml", Data(sheet.utf8)),
        ]

        return createZip(entries: entries)
    }

    static func generateODS(headers: [String], rows: [[String]]) -> Data? {
        let manifest = """
        <?xml version="1.0" encoding="UTF-8"?>
        <manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" manifest:version="1.2">
            <manifest:file-entry manifest:full-path="/" manifest:version="1.2" manifest:media-type="application/vnd.oasis.opendocument.spreadsheet"/>
            <manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>
        </manifest:manifest>
        """

        var tableRows = ""
        let allRows = [headers] + rows
        for row in allRows {
            tableRows += "<table:table-row>"
            for cell in row {
                let escaped = cell
                    .replacingOccurrences(of: "&", with: "&amp;")
                    .replacingOccurrences(of: "<", with: "&lt;")
                    .replacingOccurrences(of: ">", with: "&gt;")
                    .replacingOccurrences(of: "\"", with: "&quot;")
                tableRows += "<table:table-cell office:value-type=\"string\"><text:p>\(escaped)</text:p></table:table-cell>"
            }
            tableRows += "</table:table-row>"
        }

        let content = """
        <?xml version="1.0" encoding="UTF-8"?>
        <office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
                                 xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0"
                                 xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"
                                 office:version="1.2">
            <office:body>
                <office:spreadsheet>
                    <table:table table:name="Sheet1">
                        <table:table-column table:number-columns-repeated="\(headers.count)" table:column-width="5cm"/>
                        \(tableRows)
                    </table:table>
                </office:spreadsheet>
            </office:body>
        </office:document-content>
        """

        let entries: [(name: String, data: Data)] = [
            ("META-INF/manifest.xml", Data(manifest.utf8)),
            ("content.xml", Data(content.utf8)),
        ]

        return createZip(entries: entries)
    }

    // MARK: - ZIP generation (stored method, no compression)

    private static func createZip(entries: [(name: String, data: Data)]) -> Data? {
        var zipData = Data()
        var centralDirectory = Data()
        var localHeaderOffset: UInt32 = 0

        for entry in entries {
            let nameData = Data(entry.name.utf8)
            let crc = crc32(data: entry.data)
            let size = UInt32(entry.data.count)

            var localHeader = Data()
            localHeader.append(contentsOf: [0x50, 0x4B, 0x03, 0x04]) // local file header signature
            localHeader.append(contentsOf: [0x14, 0x00]) // version needed
            localHeader.append(contentsOf: [0x00, 0x00]) // flags
            localHeader.append(contentsOf: [0x00, 0x00]) // compression (stored)
            localHeader.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // mod time/date
            localHeader.append(crc.littleEndianData) // crc-32
            localHeader.append(size.littleEndianData) // compressed size
            localHeader.append(size.littleEndianData) // uncompressed size
            localHeader.append(UInt16(nameData.count).littleEndianData) // filename length
            localHeader.append(contentsOf: [0x00, 0x00]) // extra field length
            localHeader.append(nameData)

            zipData.append(localHeader)
            zipData.append(entry.data)

            var centralEntry = Data()
            centralEntry.append(contentsOf: [0x50, 0x4B, 0x01, 0x02]) // central directory signature
            centralEntry.append(contentsOf: [0x14, 0x00]) // version made by
            centralEntry.append(contentsOf: [0x14, 0x00]) // version needed
            centralEntry.append(contentsOf: [0x00, 0x00]) // flags
            centralEntry.append(contentsOf: [0x00, 0x00]) // compression
            centralEntry.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // mod time/date
            centralEntry.append(crc.littleEndianData) // crc-32
            centralEntry.append(size.littleEndianData) // compressed size
            centralEntry.append(size.littleEndianData) // uncompressed size
            centralEntry.append(UInt16(nameData.count).littleEndianData) // filename length
            centralEntry.append(contentsOf: [0x00, 0x00]) // extra field length
            centralEntry.append(contentsOf: [0x00, 0x00]) // file comment length
            centralEntry.append(contentsOf: [0x00, 0x00]) // disk number start
            centralEntry.append(contentsOf: [0x00, 0x00]) // internal attributes
            centralEntry.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // external attributes
            centralEntry.append(localHeaderOffset.littleEndianData) // relative offset
            centralEntry.append(nameData)

            centralDirectory.append(centralEntry)
            localHeaderOffset += UInt32(localHeader.count) + size
        }

        let centralOffset = UInt32(zipData.count)
        zipData.append(centralDirectory)
        let centralSize = UInt32(centralDirectory.count)

        var eocd = Data()
        eocd.append(contentsOf: [0x50, 0x4B, 0x05, 0x06]) // end of central directory signature
        eocd.append(contentsOf: [0x00, 0x00]) // disk number
        eocd.append(contentsOf: [0x00, 0x00]) // disk number of central dir
        eocd.append(UInt16(entries.count).littleEndianData) // entries on this disk
        eocd.append(UInt16(entries.count).littleEndianData) // total entries
        eocd.append(centralSize.littleEndianData) // size of central directory
        eocd.append(centralOffset.littleEndianData) // offset of central directory
        eocd.append(contentsOf: [0x00, 0x00]) // comment length

        zipData.append(eocd)

        return zipData
    }

    private static func columnRef(index: Int) -> String {
        var result = ""
        var n = index
        while n > 0 {
            n -= 1
            result = String(UnicodeScalar(65 + (n % 26))!) + result
            n /= 26
        }
        return result
    }

    // MARK: - CRC-32 (table-based)

    private static let crcTable: [UInt32] = {
        var table = [UInt32](repeating: 0, count: 256)
        for n in 0 ..< 256 {
            var c = UInt32(n)
            for _ in 0 ..< 8 {
                if c & 1 != 0 {
                    c = 0xEDB8_8320 ^ (c >> 1)
                } else {
                    c >>= 1
                }
            }
            table[n] = c
        }
        return table
    }()

    private static func crc32(data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension UInt16 {
    var littleEndianData: Data {
        withUnsafeBytes(of: littleEndian) { Data($0) }
    }
}

private extension UInt32 {
    var littleEndianData: Data {
        withUnsafeBytes(of: littleEndian) { Data($0) }
    }
}
