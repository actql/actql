///|
type CapturedContentCustody

///|
pub fn Store::prepare_lookup_raw_custody(
  _self : Store,
  _original : @publication.PublicationContract,
  _holding : String,
) -> Result[CapturedContentCustody, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn CapturedContentCustody::matches_lookup_raw_confirmed(
  _self : Self,
  _original : @publication.PublicationContract,
) -> Bool {
  false
}

///|
pub fn Store::lookup_raw_custody_construction_inventory(
  _self : Store,
  _chunk_bytes : Int,
  _original : @publication.PublicationContract,
) -> @execution.PreparationRepresentationUnits? {
  None
}

///|
pub fn Store::captured_content_custody_construction_inventory(
  _self : Store,
  _chunk_bytes : Int,
  candidate? : @publication.CapturedContentReference? = None,
) -> @execution.PreparationRepresentationUnits? {
  ignore(candidate)
  None
}

///|
pub fn Store::prepare_captured_content_custody(
  _self : Store,
  _original : @publication.CapturedContentReference,
  _holding : String,
) -> Result[CapturedContentCustody, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Store::prepare_generated_content_custody(
  _self : Store,
  _original : @publication.GeneratedContentReference,
  _holding : String,
) -> Result[CapturedContentCustody, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Store::generated_content_custody_construction_inventory(
  _self : Store,
  _chunk_bytes : Int,
  _original : @publication.GeneratedContentReference,
) -> @execution.PreparationRepresentationUnits? {
  None
}

///|
pub fn CapturedContentCustody::matches_generated_confirmed(
  _self : Self,
  _original : @publication.GeneratedContentReference,
) -> Bool {
  false
}

///|
pub fn Store::prepare_saved_generated_content_custody(
  _self : Store,
  _original : @publication.StoredGeneratedContentReference,
  _holding : String,
) -> Result[CapturedContentCustody, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Store::saved_generated_content_custody_construction_inventory(
  _self : Store,
  _chunk_bytes : Int,
  _original : @publication.StoredGeneratedContentReference,
) -> @execution.PreparationRepresentationUnits? {
  None
}

///|
pub fn CapturedContentCustody::matches_saved_generated_confirmed(
  _self : Self,
  _original : @publication.StoredGeneratedContentReference,
) -> Bool {
  false
}

///|
type NativeGeneratedContentOutput

///|
pub fn start_native_generated_content_output(
  _encoder : @publication.ContentByteEncoder,
) -> Result[NativeGeneratedContentOutput, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn NativeGeneratedContentOutput::advance(
  _self : Self,
  _quantum : Int,
) -> (Result[Bool, @publication.ContentSerializationIssue], Int) {
  (Err(@publication.ContentClosed), 0)
}

///|
pub fn CapturedContentCustody::persist(
  _self : Self,
  _bytes : Bytes,
) -> Result[Unit, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn CapturedContentCustody::matches_generated_selection(
  _self : Self,
  _store : Store,
  _candidate : @publication.GeneratedContentReference,
  _holding : String,
) -> Bool {
  false
}

///|
pub fn CapturedContentCustody::persist_generated_output(
  _self : Self,
  _output : NativeGeneratedContentOutput,
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
pub fn CapturedContentCustody::abandon_unpublished_generated(
  _self : Self,
) -> Result[Bool, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn CapturedContentCustody::retry_cleanup(
  _self : Self,
) -> Result[Bool, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn CapturedContentCustody::retained_inventory(
  _self : Self,
) -> @execution.PreparationRepresentationUnits? {
  None
}
