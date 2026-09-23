///|
type Library

///|
type Sha256State

///|
#borrow(library)
extern "C" fn sha256_new_ffi(library : Library) -> Sha256State = "actql_native_signature_sha256_new"

///|
#borrow(state)
extern "C" fn sha256_ready_ffi(state : Sha256State) -> Bool = "actql_native_signature_sha256_ready"

///|
#borrow(library, state, bytes)
extern "C" fn sha256_update_ffi(
  library : Library,
  state : Sha256State,
  bytes : Bytes,
  length : Int,
) -> Bool = "actql_native_signature_sha256_update"

///|
#borrow(library, state)
extern "C" fn sha256_finish_ffi(
  library : Library,
  state : Sha256State,
) -> Bytes = "actql_native_signature_sha256_finish"

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
pub fn Library::sha256_hasher(
  self : Library,
) -> Result[Sha256Hasher, NativeSignatureIssue] {
  let state = sha256_new_ffi(self)
  if !sha256_ready_ffi(state) {
    return Err(Verification("SHA-256 initialization failed"))
  }
  Ok({ library: self, state, })
}

///|
pub fn Sha256Hasher::update(
  self : Sha256Hasher,
  bytes : Bytes,
) -> Result[Unit, NativeSignatureIssue] {
  if !sha256_update_ffi(self.library, self.state, bytes, bytes.length()) {
    return Err(Verification("SHA-256 update failed"))
  }
  Ok(())
}

///|
pub fn Sha256Hasher::finish_hex(
  self : Sha256Hasher,
) -> Result[String, NativeSignatureIssue] {
  let digest = sha256_finish_ffi(self.library, self.state)
  if digest.length() != 32 {
    return Err(Verification("SHA-256 finalization failed"))
  }
  let builder = StringBuilder(size_hint=64)
  for byte in digest {
    let part = byte.to_hex()
    if part.length() == 1 {
      builder.write_char('0')
    }
    builder.write_string(part)
  }
  Ok(builder.to_string())
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
