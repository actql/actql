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
pub fn Store::model_raw_evidence_custody_construction(
  _self : Store,
  _original : @publication.BoundModelRawResponse,
) -> PrivateEvidenceCustodyConstruction? {
  None
}

///|
pub fn Store::prepare_model_raw_evidence_custody(
  _self : Store,
  _original : @publication.BoundModelRawResponse,
  _bytes : Bytes,
  _crypto : @signature.Library,
  _key : Bytes,
  retain? : (ModelEvidenceCustody) -> Unit = _ => (),
) -> Result[ModelEvidenceCustody, NativePublicationStoreIssue] {
  ignore(retain)
  Err(UnsupportedTarget)
}

///|
pub fn ModelEvidenceCustody::reconcile_original_store_return(
  _self : ModelEvidenceCustody,
) -> Result[Bool, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
type ModelEnteredRawReadExtent

///|
pub fn Store::model_entered_raw_read_construction(
  _self : Store,
  _raw : @publication.BoundModelRawResponse,
) -> Result[
  (ModelEnteredRawReadExtent, PrivateEvidenceCustodyConstruction),
  NativePublicationStoreIssue,
] {
  Err(UnsupportedTarget)
}

///|
pub fn ModelEnteredRawReadExtent::verify_original(
  _self : ModelEnteredRawReadExtent,
  _crypto : @signature.Library,
  _key : Bytes,
) -> Result[Unit, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
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
  raw_descriptor? : @publication.BoundModelRawResponse? = None,
) -> Result[ModelEvidenceCustody, NativePublicationStoreIssue] {
  ignore(raw_descriptor)
  Err(UnsupportedTarget)
}

///|
type ModelSettlementReadExtent

///|
pub fn Store::model_settlement_restore_construction(
  _self : Store,
  _definition : @publication.PublicationContract,
  _scope_cid : String,
  _slot_cid : String,
  _attempt_cid : String,
  _role : ModelSettlementReadRole,
  _evidence_cid : String,
) -> Result[
  (ModelSettlementReadExtent, PrivateEvidenceCustodyConstruction),
  NativePublicationStoreIssue,
] {
  Err(UnsupportedTarget)
}

///|
pub fn ModelSettlementReadExtent::read_original_wire(
  _self : ModelSettlementReadExtent,
  _crypto : @signature.Library,
  _key : Bytes,
) -> Result[String, NativePublicationStoreIssue] {
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
