///|
/// Original selected component, independent of each Library borrow. The trusted
/// installed owner retains this receiver, including partial initialization.
type OriginalCryptoComponent

///|
extern "C" fn crypto_scope_available_ffi() -> Bool = "actql_native_crypto_component_scope_available"

///|
#borrow(path)
extern "C" fn crypto_component_load_ffi(
  path : Bytes,
  length : Int,
  heap_bytes : Int64,
  diagnostic_ceiling : Int,
) -> OriginalCryptoComponent = "actql_native_crypto_component_load"

///|
#borrow(component)
extern "C" fn crypto_component_ready_ffi(
  component : OriginalCryptoComponent,
) -> Bool = "actql_native_crypto_component_ready"

///|
#borrow(component)
extern "C" fn crypto_component_close_ffi(
  component : OriginalCryptoComponent,
) -> Int = "actql_native_crypto_component_close"

///|
#borrow(component)
extern "C" fn crypto_component_library_ffi(
  component : OriginalCryptoComponent,
) -> Library = "actql_native_crypto_component_library"

///|
#borrow(component, library)
extern "C" fn crypto_component_owns_library_ffi(
  component : OriginalCryptoComponent,
  library : Library,
) -> Bool = "actql_native_crypto_component_owns_library"

///|
/// Original association, not readiness or a scope/cleanup acknowledgement.
pub fn OriginalCryptoComponent::owns_library(
  self : OriginalCryptoComponent,
  library : Library,
) -> Bool {
  crypto_component_owns_library_ffi(self, library)
}

///|
/// Requires the selected scoped runtime and an already admitted original Read
/// context before dlopen or OpenSSL initialization. Heap bytes select one extent
/// inside that original holding; they do not supply funding or authority.
pub fn load_current_crypto_component(
  path : String,
  heap_bytes : Int64,
  diagnostic_ceiling : Int,
) -> Result[NativeCryptoComponentAcquisition, NativeSignatureIssue] {
  let encoded = @utf8.encode(path)
  if encoded.length() == 0 ||
    encoded.length() > 4096 ||
    heap_bytes <= 0 ||
    diagnostic_ceiling <= 0 {
    return Err(InvalidInput)
  }
  for byte in encoded {
    if byte == 0 {
      return Err(InvalidInput)
    }
  }
  if !crypto_scope_available_ffi() {
    return Err(LibraryLoad("original scoped Crypto provider unavailable"))
  }
  let original = crypto_component_load_ffi(
    encoded,
    encoded.length(),
    heap_bytes,
    diagnostic_ceiling,
  )
  if crypto_component_ready_ffi(original) {
    Ok(ReadyCryptoComponent(original))
  } else {
    Ok(
      PendingCryptoComponent(
        original,
        LibraryLoad("original Crypto component initialization failed"),
      ),
    )
  }
}

///|
/// Each outer/inner Library holds its own borrow. It cannot unload the component
/// or acknowledge its heap, context, Host, domain or parent loan.
pub fn OriginalCryptoComponent::new_library(
  self : OriginalCryptoComponent,
) -> Result[NativeCryptoLibraryAcquisition, NativeSignatureIssue] {
  if !crypto_component_ready_ffi(self) {
    return Err(InvalidInput)
  }
  let library = crypto_component_library_ffi(self)
  if library_ready_ffi(library) {
    Ok(ReadyCryptoLibrary(library))
  } else {
    Ok(
      PendingCryptoLibrary(
        library,
        LibraryLoad("original Crypto Library initialization failed"),
      ),
    )
  }
}

///|
/// Explicit original cleanup. Pending borrows and failed/unconfirmed module
/// close retain this receiver. GC, a Library close and thread join are not ACKs.
pub fn OriginalCryptoComponent::close_checked(
  self : OriginalCryptoComponent,
) -> Result[Unit, NativeSignatureIssue] {
  match crypto_component_close_ffi(self) {
    0 => Ok(())
    1 => Err(CleanupPending)
    3 => Err(CloseUnconfirmed("original Crypto module close unconfirmed"))
    _ => Err(InvalidInput)
  }
}
