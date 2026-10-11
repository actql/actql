///|
type LocalPreparationRawCustody

///|
pub fn Store::prepare_local_preparation_raw_observation(
  _self : Store,
  _grant : @credential.LocalPreparationCredentialGrant,
  _original_use : @credential.LocalPreparationCredentialUse,
  _client : @http.Client,
  _crypto : @signature.Library,
  _key : Bytes,
) -> Result[LocalPreparationRawCustody, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn LocalPreparationRawCustody::reserve(
  _self : LocalPreparationRawCustody,
) -> Result[Unit, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn LocalPreparationRawCustody::persist(
  _self : LocalPreparationRawCustody,
  _status : Int,
  _body : Bytes,
) -> Result[Unit, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn LocalPreparationRawCustody::confirm(
  _self : LocalPreparationRawCustody,
) -> Result[NativeLocalPreparationRawObservation, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn LocalPreparationRawCustody::reserved_bytes(
  _self : LocalPreparationRawCustody,
) -> Int64 {
  0L
}

///|
pub fn LocalPreparationRawCustody::retry_cleanup(
  _self : LocalPreparationRawCustody,
) -> Result[Bool, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Store::restore_local_preparation_raw_observation(
  _self : Store,
  _grant : @credential.LocalPreparationCredentialGrant,
  _original_use : @credential.LocalPreparationCredentialUse,
  _crypto : @signature.Library,
  _key : Bytes,
) -> Result[LocalPreparationRawCustody, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}
