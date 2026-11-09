///|
type EffectCaptureCustody

///|
pub fn Store::prepare_effect_capture_custody(
  _self : Store,
  _binding : @publication.EffectCaptureHoldingBinding,
  _crypto : @signature.Library,
  _key : Bytes,
) -> Result[EffectCaptureCustody, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Store::restore_effect_capture_custody(
  _self : Store,
  _binding : @publication.EffectCaptureHoldingBinding,
  _crypto : @signature.Library,
  _key : Bytes,
) -> Result[EffectCaptureCustody, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn EffectCaptureCustody::persist(
  _self : EffectCaptureCustody,
) -> Result[Unit, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn EffectCaptureCustody::confirm(
  _self : EffectCaptureCustody,
) -> Result[@publication.PublicationContract, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn EffectCaptureCustody::retry_cleanup(
  _self : EffectCaptureCustody,
) -> Result[Bool, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn EffectCaptureCustody::reserved_bytes(
  _self : EffectCaptureCustody,
) -> Int64 {
  0L
}

///|
pub fn EffectCaptureCustody::same_binding(
  _self : EffectCaptureCustody,
  _other : EffectCaptureCustody,
) -> Bool {
  false
}

///|
type EffectPreviewCustody

///|
pub fn Store::prepare_effect_preview_custody(
  _self : Store,
  _identity : @publication.EffectPreviewIdentity,
  _wire : String,
  _authoring_cid : String,
  _store_authority : String,
  _crypto : @signature.Library,
  _key : Bytes,
  _max_bytes : Int,
  _max_nodes : Int,
  _max_depth : Int,
) -> Result[EffectPreviewCustody, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Store::restore_effect_preview_custody(
  _self : Store,
  _identity : @publication.EffectPreviewIdentity,
  _wire : String,
  _authoring_cid : String,
  _store_authority : String,
  _crypto : @signature.Library,
  _key : Bytes,
  _max_bytes : Int,
  _max_nodes : Int,
  _max_depth : Int,
) -> Result[EffectPreviewCustody, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn EffectPreviewCustody::persist(
  _self : EffectPreviewCustody,
) -> Result[Unit, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn EffectPreviewCustody::confirm(
  _self : EffectPreviewCustody,
) -> Result[
  (@publication.EffectPreviewIdentity, String),
  NativePublicationStoreIssue,
] {
  Err(UnsupportedTarget)
}

///|
pub fn EffectPreviewCustody::retry_cleanup(
  _self : EffectPreviewCustody,
) -> Result[Bool, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn EffectPreviewCustody::reserved_bytes(
  _self : EffectPreviewCustody,
) -> Int64 {
  0L
}

///|
pub fn EffectPreviewCustody::same_binding(
  _self : EffectPreviewCustody,
  _other : EffectPreviewCustody,
) -> Bool {
  false
}

///|
type EffectCheckpointCustody

///|
pub fn Store::prepare_effect_checkpoint_custody(
  _self : Store,
  _checkpoint : @checkpoint.SealedCheckpoint,
  _continuation_wire : String,
  _store_authority : String,
  _crypto : @signature.Library,
  _key : Bytes,
) -> Result[EffectCheckpointCustody, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Store::restore_effect_checkpoint_custody(
  _self : Store,
  _checkpoint : @checkpoint.SealedCheckpoint,
  _continuation_wire : String,
  _store_authority : String,
  _crypto : @signature.Library,
  _key : Bytes,
) -> Result[EffectCheckpointCustody, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Store::restore_confirmed_effect_checkpoint_custody(
  _self : Store,
  _checkpoint : @checkpoint.SealedCheckpoint,
  _store_authority : String,
  _crypto : @signature.Library,
  _key : Bytes,
  continuation_extent? : @sqlite.NativeJournalHeader? = None,
) -> Result[EffectCheckpointCustody, NativePublicationStoreIssue] {
  ignore(continuation_extent)
  Err(UnsupportedTarget)
}

///|
pub fn Store::effect_checkpoint_restore_construction(
  _self : Store,
  _checkpoint : @checkpoint.SealedCheckpoint,
) -> Result[
  (@sqlite.NativeJournalHeader, PrivateEvidenceCustodyConstruction),
  NativePublicationStoreIssue,
] {
  Err(UnsupportedTarget)
}

///|
pub fn EffectCheckpointCustody::persist(
  _self : EffectCheckpointCustody,
) -> Result[Unit, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn EffectCheckpointCustody::confirm(
  _self : EffectCheckpointCustody,
) -> Result[
  (@checkpoint.PersistedCheckpoint, String),
  NativePublicationStoreIssue,
] {
  Err(UnsupportedTarget)
}

///|
pub fn EffectCheckpointCustody::retry_cleanup(
  _self : EffectCheckpointCustody,
) -> Result[Bool, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn EffectCheckpointCustody::reserved_bytes(
  _self : EffectCheckpointCustody,
) -> Int64 {
  0L
}

///|
pub fn EffectCheckpointCustody::same_binding(
  _self : EffectCheckpointCustody,
  _other : EffectCheckpointCustody,
) -> Bool {
  false
}
