///|
type OriginalCryptoComponent

///|
pub fn OriginalCryptoComponent::owns_library(
  _self : OriginalCryptoComponent,
  _library : Library,
) -> Bool {
  false
}

///|
pub fn load_current_crypto_component(
  _path : String,
  _heap_bytes : Int64,
  _diagnostic_ceiling : Int,
) -> Result[NativeCryptoComponentAcquisition, NativeSignatureIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn OriginalCryptoComponent::new_library(
  _self : OriginalCryptoComponent,
) -> Result[NativeCryptoLibraryAcquisition, NativeSignatureIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn OriginalCryptoComponent::close_checked(
  _self : OriginalCryptoComponent,
) -> Result[Unit, NativeSignatureIssue] {
  Err(UnsupportedTarget)
}
