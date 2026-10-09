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
