///|
#borrow(library, private_der, public_der)
extern "C" fn generate_ed25519_ffi(
  library : Library,
  private_der : Bytes,
  private_length : Int,
  public_der : Bytes,
  public_length : Int,
) -> Int = "actql_native_signature_generate_ed25519"

///|
#borrow(bytes)
extern "C" fn clear_key_der_ffi(bytes : Bytes, length : Int) -> Unit = "actql_native_signature_clear_key_der"

///|
/// Fresh physical material from the same explicitly selected Library. The
/// first result is secret PKCS#8 PEM Bytes; the second is public SPKI PEM.
/// This does not select/install a signer, adopt a generation or issue a CID,
/// grant, claim, signature or permission. Trusted first installation must own
/// the exclusive Writer and retain partial-file/close responsibility. Never
/// use this to repair a missing saved key or to replace a claimed operation.
/// The explicit diagnostic ceiling is an intake bound, not numerical funding.
pub fn Library::generate_ed25519_key_pair(
  self : Library,
) -> Result[(Bytes, String), NativeSignatureIssue] {
  if self.diagnostic_ceiling() is None {
    return Err(InvalidInput)
  }
  let private_der = Bytes::make(48, 0)
  let public_der = Bytes::make(44, 0)
  defer clear_key_der_ffi(private_der, private_der.length())
  match
    generate_ed25519_ffi(
      self,
      private_der,
      private_der.length(),
      public_der,
      public_der.length(),
    ) {
    0 => {
      let private_pem = @utf8.encode(
        "-----BEGIN PRIVATE KEY-----\n" +
        @base64.encode(private_der) +
        "\n-----END PRIVATE KEY-----\n",
      )
      let public_pem = "-----BEGIN PUBLIC KEY-----\n" +
        @base64.encode(public_der) +
        "\n-----END PUBLIC KEY-----\n"
      Ok((private_pem, public_pem))
    }
    2 => Err(InvalidInput)
    _ => Err(Signing("Ed25519 key generation unavailable"))
  }
}
