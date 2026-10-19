// The existing GCS temporal projection owns physical timestamp meaning.
// This private ABI neither admits a file nor issues a Resource or read grant.

///|
#export_name("gcsObjectTimestamp")
pub fn gcs_object_timestamp(text : String) -> String? {
  @catalog.object_source_timestamp(text)
}
