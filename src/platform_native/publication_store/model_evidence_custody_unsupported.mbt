///|
type ModelEvidenceCustody

///|
pub fn Store::private_evidence_custody_construction(
  _self : Store,
  _wire : String,
) -> PrivateEvidenceCustodyConstruction? {
  None
}

///|
pub fn Store::prepare_model_evidence_custody(
  _self : Store,
  _definition : @publication.PublicationContract,
  _scope_cid : String,
  _slot_cid : String,
  _attempt_cid : String,
  _original : @publication.RunEvidenceValue,
  _crypto : @signature.Library,
  _key : Bytes,
) -> Result[ModelEvidenceCustody, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Store::restore_model_evidence_custody(
  _self : Store,
  _definition : @publication.PublicationContract,
  _scope_cid : String,
  _slot_cid : String,
  _attempt_cid : String,
  _original : @publication.RunEvidenceValue,
  _crypto : @signature.Library,
  _key : Bytes,
) -> Result[ModelEvidenceCustody, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn ModelEvidenceCustody::persist(
  _self : ModelEvidenceCustody,
) -> Result[Unit, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn ModelEvidenceCustody::confirm(
  _self : ModelEvidenceCustody,
) -> Result[@publication.RunEvidenceValue, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn ModelEvidenceCustody::retry_cleanup(
  _self : ModelEvidenceCustody,
) -> Result[Bool, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn ModelEvidenceCustody::reserved_bytes(
  _self : ModelEvidenceCustody,
) -> Int64 {
  0L
}
