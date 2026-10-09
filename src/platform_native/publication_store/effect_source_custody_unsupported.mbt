///|
type EffectSourceCustody

///|
pub fn Store::prepare_effect_source_custody(
  _self : Store,
  _run : @publication.PublicationContract,
  _source : @publication.CapturedEffectSourceArtifact,
  _request : @payload.PublicationPayloadRequest,
  _physical_digest : String,
  _physical_bytes : Int64,
) -> Result[EffectSourceCustody, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Store::restore_effect_source_custody(
  _self : Store,
  _run : @publication.PublicationContract,
  _source : @publication.CapturedEffectSourceArtifact,
  _request : @payload.PublicationPayloadRequest,
  _physical_digest : String,
  _physical_bytes : Int64,
) -> Result[EffectSourceCustody, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn EffectSourceCustody::retain(
  _self : EffectSourceCustody,
) -> Result[Unit, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn EffectSourceCustody::begin_payload(
  _self : EffectSourceCustody,
) -> Result[PayloadWriter, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn EffectSourceCustody::confirm_payload(
  _self : EffectSourceCustody,
) -> Result[NativePublicationPayloadInfo, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn EffectSourceCustody::open_reader(
  _self : EffectSourceCustody,
) -> Result[PayloadReader, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn EffectSourceCustody::cleanup_complete(
  _self : EffectSourceCustody,
) -> Result[Bool, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn EffectSourceCustody::retry_cleanup(
  _self : EffectSourceCustody,
) -> Result[Bool, NativePublicationStoreIssue] {
  Err(UnsupportedTarget)
}
