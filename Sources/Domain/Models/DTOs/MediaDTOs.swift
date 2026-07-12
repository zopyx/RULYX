import Foundation

// MARK: - Blob Upload & Feed Post

/// Response from `com.atproto.repo.uploadBlob`.
struct UploadBlobResponse: Decodable {
    let blob: UploadedBlob
}

/// A blob that has been uploaded to the PDS.
struct UploadedBlob: Decodable, Encodable {
    let ref: BlobRef
    let mimeType: String
    let size: Int
    let blobType: String?

    enum CodingKeys: String, CodingKey {
        case ref
        case mimeType
        case size
        case blobType = "$type"
    }
}

/// Reference to a blob on the PDS (CID link).
struct BlobRef: Decodable, Encodable {
    let link: String

    enum CodingKeys: String, CodingKey {
        case link = "$link"
    }
}
