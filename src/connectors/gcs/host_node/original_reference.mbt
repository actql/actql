// Private typed Connector bridge. The caller supplies the original installed
// ReferenceIssuer, never an author-provided grant or a reconstructed Ref.

///|
#export_name("gcsCollectionReferenceFailureCode")
pub fn gcs_collection_reference_failure_code(
  issue : @original.CollectionReferenceIssue,
) -> String {
  match issue {
    InvalidLimits => "GcsCollectionReferenceInvalidLimits"
    ForeignSelection => "GcsForeignCollectionSelection"
    CapacityExceeded => "GcsCollectionReferenceCapacityExceeded"
    ReferenceRejected(_) => "GcsCollectionReferenceUnavailable"
  }
}

///|
#export_name("gcsCollectionIssueReference")
pub fn gcs_collection_issue_reference(
  original : @catalog.ObjectCollectionBinding,
  selected : @environment.StoreCommandBinding,
  declared_wire : String,
  connector_id : String,
  issuer : @admitted.ReferenceIssuer,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_work : Int,
) -> Result[@admitted.CheckedValue, @original.CollectionReferenceIssue] {
  @original.issue_collection_reference(
    original,
    selected,
    declared_wire,
    connector_id,
    issuer,
    { max_bytes, max_nodes, max_depth, max_work, },
  )
}
