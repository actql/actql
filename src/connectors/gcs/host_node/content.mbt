// Private ABI projection of the portable Connector admission, not an issuer.

///|
#export_name("gcsContentMetadataJson")
pub fn gcs_content_metadata_json(
  bytes : Bytes,
  bucket : String,
  name : String,
  generation : String,
  max_content_bytes : Int64,
  max_bytes : Int,
) -> Result[String, @catalog.ContentMetadataIssue] {
  @catalog.content_metadata_json(
    bytes,
    bucket,
    name,
    generation,
    max_content_bytes,
    {
      max_bytes,
      max_nodes: max_bytes,
      max_depth: 64,
      max_metadata_entries: max_bytes,
    },
  )
}

///|
#export_name("gcsContentMetadataFailureCode")
pub fn gcs_content_metadata_failure_code(
  issue : @catalog.ContentMetadataIssue,
) -> String {
  match issue {
    InvalidMetadata => "InvalidGcsContentMetadata"
    MetadataMismatch => "GcsContentMetadataMismatch"
    RepresentationUnsupported => "GcsContentRepresentationUnsupported"
    InvalidDigest => "InvalidGcsContentDigest"
  }
}
