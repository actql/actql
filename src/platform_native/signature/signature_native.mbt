///|
type Library

///|
type Sha256Hasher

///|
#borrow(library)
extern "C" fn sha256_new_ffi(library : Library) -> Sha256Hasher = "actql_native_signature_sha256_new"

///|
#borrow(hash)
extern "C" fn sha256_ready_ffi(hash : Sha256Hasher) -> Bool = "actql_native_signature_sha256_ready"

///|
#borrow(hash, bytes)
extern "C" fn sha256_update_ffi(
  hash : Sha256Hasher,
  bytes : Bytes,
  length : Int,
) -> Bool = "actql_native_signature_sha256_update"

///|
#borrow(hash)
extern "C" fn sha256_finish_ffi(hash : Sha256Hasher) -> Bytes = "actql_native_signature_sha256_finish"

///|
#borrow(path)
extern "C" fn load_library_ffi(
  path : Bytes,
  length : Int,
  diagnostic_ceiling : Int,
) -> Library = "actql_native_signature_load_library"

///|
#borrow(library)
extern "C" fn library_ready_ffi(library : Library) -> Bool = "actql_native_signature_library_ready"

///|
/// Check this original Library's actual current lifetime without cryptographic
/// work. This observes its component/handle and closing state; it grants no
/// permission and acknowledges no cleanup or earlier operation.
pub fn Library::require_current(
  self : Library,
) -> Result[Unit, NativeSignatureIssue] {
  if library_ready_ffi(self) {
    Ok(())
  } else {
    Err(InvalidInput)
  }
}

///|
#borrow(library)
extern "C" fn library_close_ffi(library : Library) -> Int = "actql_native_signature_library_close"

///|
#borrow(hash)
extern "C" fn sha256_close_ffi(hash : Sha256Hasher) -> Bool = "actql_native_signature_sha256_close"

///|
/// Cleanup only on this original Library. A live SHA-256 context keeps its
/// original dynamic handle pending. Unconfirmed physical close stays sticky;
/// calling this again never loads a replacement or repeats that close.
/// This ACK does not retire caller aliases, Host loans or numerical funding.
pub fn Library::close_checked(
  self : Library,
) -> Result[Unit, NativeSignatureIssue] {
  match library_close_ffi(self) {
    0 => Ok(())
    1 => Err(CleanupPending)
    3 => Err(CloseUnconfirmed(library_message(self)))
    _ => Err(InvalidInput)
  }
}

///|
/// Retire this original EVP context, including after Library cleanup starts.
/// Finishing a digest also retires it. GC or a lost return is not this ACK.
pub fn Sha256Hasher::close_checked(
  self : Sha256Hasher,
) -> Result[Unit, NativeSignatureIssue] {
  if sha256_close_ffi(self) {
    Ok(())
  } else {
    Err(InvalidInput)
  }
}

///|
#borrow(library)
extern "C" fn library_diagnostic_ceiling_ffi(library : Library) -> Int = "actql_native_signature_library_diagnostic_ceiling"

///|
/// Read the positive ceiling installed on this original ready Library.
/// Legacy omission and unavailable handles return None. This immutable fact
/// neither reserves memory nor grants signing/read permission or cleanup ACK.
pub fn Library::diagnostic_ceiling(self : Library) -> Int? {
  let ceiling = library_diagnostic_ceiling_ffi(self)
  if ceiling > 0 {
    Some(ceiling)
  } else {
    None
  }
}

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
#borrow(library, private_key, message)
extern "C" fn sign_ed25519_ffi(
  library : Library,
  private_key : Bytes,
  private_key_length : Int,
  message : Bytes,
  message_length : Int,
) -> Bytes = "actql_native_signature_sign_ed25519"

///|
#borrow(library, public_key, output)
extern "C" fn ed25519_public_key_raw32_ffi(
  library : Library,
  public_key : Bytes,
  public_key_length : Int,
  output : Bytes,
  output_length : Int,
) -> Int = "actql_native_signature_ed25519_public_key_raw32"

///|
/// Comparison-only public key projection using the selected Library.
/// Requires an explicit diagnostic ceiling. It creates no CID or authority.
pub fn Library::ed25519_public_key_raw32(
  self : Library,
  public_key_pem : String,
) -> Result[Bytes, NativeSignatureIssue] {
  let public_key = @utf8.encode(public_key_pem)
  if public_key.length() == 0 || public_key.length() > 16384 {
    return Err(InvalidInput)
  }
  let output = Bytes::make(32, 0)
  match
    ed25519_public_key_raw32_ffi(
      self,
      public_key,
      public_key.length(),
      output,
      output.length(),
    ) {
    0 => Ok(output)
    2 => Err(InvalidInput)
    3 => Err(InvalidPublicKey(library_message(self)))
    4 => Err(UnsupportedKey(library_message(self)))
    _ => Err(Verification(library_message(self)))
  }
}

///|
/// Physical crypto only, over the exact bytes selected by the existing
/// Checkpoint/preimage Owner. This does not acquire a key, authorize signing,
/// issue a Resolution, or persist a credential use. Trusted assembly separately
/// supplies its purpose-specific original key custody and current authority.
/// The result uses the verification adapter's unpadded base64url transport.
pub fn Library::sign_ed25519(
  self : Library,
  private_key_pem : Bytes,
  message : Bytes,
) -> Result[String, NativeSignatureIssue] {
  if private_key_pem.length() == 0 ||
    private_key_pem.length() > 16384 ||
    message.length() > 1048576 {
    return Err(InvalidInput)
  }
  let result = sign_ed25519_ffi(
    self,
    private_key_pem,
    private_key_pem.length(),
    message,
    message.length(),
  )
  if result.length() == 0 {
    return Err(Signing("signature result unavailable"))
  }
  match result[0] {
    0 if result.length() == 65 =>
      Ok(
        @base64.encode(result[1:])
        .replace_all(old="+", new="-")
        .replace_all(old="/", new="_")
        .replace_all(old="=", new=""),
      )
    2 => Err(InvalidInput)
    3 => Err(InvalidPrivateKey("private key decode rejected"))
    4 => Err(UnsupportedKey("private key is not Ed25519"))
    _ => Err(Signing("Ed25519 signing failed"))
  }
}

///|
fn library_message(library : Library) -> String {
  let bytes = library_error_ffi(library)
  if bytes.is_empty() {
    "Crypto diagnostic detail omitted"
  } else {
    @utf8.decode_lossy(bytes)
  }
}

///|
#borrow(library)
extern "C" fn random_bytes_ffi(library : Library, length : Int) -> Bytes = "actql_native_signature_random_bytes"

///|
#borrow(library, key, message)
extern "C" fn hmac_sha256_ffi(
  library : Library,
  key : Bytes,
  key_length : Int,
  message : Bytes,
  message_length : Int,
) -> Bytes = "actql_native_signature_hmac_sha256"

///|
#borrow(library, expected, supplied)
extern "C" fn equal_tag_ffi(
  library : Library,
  expected : Bytes,
  supplied : Bytes,
) -> Int = "actql_native_signature_equal_tag"

///|
/// Physical randomness for retained Host keys and nonces. This does not create
/// an epoch, admission fact, credential or permission by itself.
pub fn Library::random_bytes(
  self : Library,
  length : Int,
) -> Result[Bytes, NativeSignatureIssue] {
  if length < 1 || length > 4096 {
    return Err(InvalidInput)
  }
  let result = random_bytes_ffi(self, length)
  if result.length() != length {
    return Err(Verification("secure random generation failed"))
  }
  Ok(result)
}

///|
/// Authenticate exact bytes using the explicitly selected crypto library.
/// The common Owner chooses the canonical body and its authority scope.
pub fn Library::hmac_sha256(
  self : Library,
  key : Bytes,
  message : Bytes,
) -> Result[Bytes, NativeSignatureIssue] {
  if key.length() < 1 || key.length() > 4096 || message.length() > 1048576 {
    return Err(InvalidInput)
  }
  let tag = hmac_sha256_ffi(self, key, key.length(), message, message.length())
  if tag.length() != 32 {
    return Err(Verification("HMAC-SHA-256 authentication failed"))
  }
  Ok(tag)
}

///|
pub fn Library::verify_hmac_sha256(
  self : Library,
  key : Bytes,
  message : Bytes,
  tag : Bytes,
) -> Result[Bool, NativeSignatureIssue] {
  if tag.length() != 32 {
    return Err(InvalidInput)
  }
  let expected = match self.hmac_sha256(key, message) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match equal_tag_ffi(self, expected, tag) {
    0 => Ok(true)
    1 => Ok(false)
    _ => Err(Verification("constant-time tag comparison unavailable"))
  }
}

///|
pub fn Library::sha256_hasher(
  self : Library,
) -> Result[Sha256Hasher, NativeSignatureIssue] {
  let hash = sha256_new_ffi(self)
  if !sha256_ready_ffi(hash) {
    return Err(Verification("SHA-256 initialization failed"))
  }
  Ok(hash)
}

///|
pub fn Sha256Hasher::update(
  self : Sha256Hasher,
  bytes : Bytes,
) -> Result[Unit, NativeSignatureIssue] {
  if !sha256_update_ffi(self, bytes, bytes.length()) {
    return Err(Verification("SHA-256 update failed"))
  }
  Ok(())
}

///|
pub fn Sha256Hasher::finish_hex(
  self : Sha256Hasher,
) -> Result[String, NativeSignatureIssue] {
  let digest = sha256_finish_ffi(self)
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
/// Select from trusted installer configuration bound to its source/ABI.
/// Omission preserves legacy behavior; this bound issues no funding/authority.
pub fn load_library(
  path : String,
  diagnostic_ceiling? : Int? = None,
) -> Result[Library, NativeSignatureIssue] {
  if diagnostic_ceiling is Some(value) && value <= 0 {
    return Err(InvalidInput)
  }
  if path.is_empty() || path.length() > 4096 {
    return Err(InvalidInput)
  }
  let encoded = @utf8.encode(path)
  let library = load_library_ffi(
    encoded,
    encoded.length(),
    diagnostic_ceiling.unwrap_or(0),
  )
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

///|
#borrow(library, key, aad, input)
extern "C" fn private_cipher_ffi(
  library : Library,
  key : Bytes,
  key_length : Int,
  aad : Bytes,
  aad_length : Int,
  input : Bytes,
  input_length : Int,
  encrypt : Int,
) -> Bytes = "actql_native_private_evidence_cipher"

///|
fn Library::private_cipher(
  self : Library,
  key : Bytes,
  aad : Bytes,
  input : Bytes,
  encrypt : Bool,
) -> Result[Bytes, NativePrivateEvidenceIssue] {
  let result = private_cipher_ffi(
    self,
    key,
    key.length(),
    aad,
    aad.length(),
    input,
    input.length(),
    if encrypt {
      1
    } else {
      0
    },
  )
  if result.length() < 2 || result[0] != 0 {
    return Err(CipherRejected)
  }
  Ok(result[1:].to_owned())
}
