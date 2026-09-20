///|
type Library

///|
#borrow(path)
extern "C" fn load_library_ffi(path : Bytes, length : Int) -> Library = "actql_native_signature_load_library"

///|
#borrow(library)
extern "C" fn library_ready_ffi(library : Library) -> Bool = "actql_native_signature_library_ready"

///|
#borrow(library)
extern "C" fn library_error_ffi(library : Library) -> Bytes = "actql_native_signature_library_error"

///|
#borrow(library, public_key, message, signature)
extern "C" fn verify_ed25519_ffi(
  library : Library,
  public_key : Bytes,
  public_key_length : Int,
  message : Bytes,
  message_length : Int,
  signature : Bytes,
  signature_length : Int,
) -> Int = "actql_native_signature_verify_ed25519"

///|
fn library_message(library : Library) -> String {
  @utf8.decode_lossy(library_error_ffi(library))
}

///|
pub fn load_library(path : String) -> Result[Library, NativeSignatureIssue] {
  if path.is_empty() || path.length() > 4096 {
    return Err(InvalidInput)
  }
  let encoded = @utf8.encode(path)
  let library = load_library_ffi(encoded, encoded.length())
  if library_ready_ffi(library) {
    Ok(library)
  } else {
    Err(LibraryLoad(library_message(library)))
  }
}

///|
/// Verify one canonical Ed25519 signature. The adapter accepts an SPKI PEM
/// public key and an unpadded base64url signature. Scheme selection, key
/// authority and the signed preimage remain portable MoonBit decisions.
pub fn Library::verify_ed25519(
  self : Library,
  public_key_pem : String,
  message : Bytes,
  signature_base64url : String,
) -> Result[Bool, NativeSignatureIssue] {
  let public_key = @utf8.encode(public_key_pem)
  let signature = @utf8.encode(signature_base64url)
  if public_key.length() == 0 ||
    public_key.length() > 16384 ||
    message.length() > 1048576 ||
    signature.length() != 86 {
    return Err(InvalidInput)
  }
  match
    verify_ed25519_ffi(
      self,
      public_key,
      public_key.length(),
      message,
      message.length(),
      signature,
      signature.length(),
    ) {
    0 => Ok(true)
    1 => Ok(false)
    2 => Err(InvalidInput)
    3 => Err(InvalidPublicKey(library_message(self)))
    4 => Err(UnsupportedKey(library_message(self)))
    _ => Err(Verification(library_message(self)))
  }
}
