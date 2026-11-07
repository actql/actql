///|
type CapturedContentCustody

///|
pub fn Store::prepare_captured_content_custody(
  _self : Store,
  _original : @publication.CapturedContentReference,
  _holding : String,
) -> Result[CapturedContentCustody, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn CapturedContentCustody::persist(
  _self : Self,
  _bytes : Bytes,
) -> Result[Unit, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn CapturedContentCustody::restore(
  _self : Self,
) -> Result[Unit, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn CapturedContentCustody::confirm(
  _self : Self,
  _chunk_bytes : Int,
) -> Result[Unit, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn CapturedContentCustody::matches_confirmed(
  _self : Self,
  _original : @publication.CapturedContentReference,
) -> Bool {
  false
}

///|
pub fn CapturedContentCustody::retry_cleanup(
  _self : Self,
) -> Result[Bool, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}
