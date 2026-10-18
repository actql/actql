/* Physical key generation only. This does not adopt a Store/key, issue an
 * identity or grant, claim a credential use, or authorize a Resolution.
 * Synchronous, no callbacks/reentry: borrow the original Library and two
 * distinct output buffers (48 private DER bytes, 44 public DER bytes). Free
 * every temporary EVP key/context before returning; caller owns the output.
 * Optional symbols leave the existing verification/load contract unchanged.
 * https://docs.openssl.org/3.0/man3/EVP_PKEY_keygen/
 * https://www.rfc-editor.org/rfc/rfc8410#section-10.3 */
MOONBIT_FFI_EXPORT
int32_t actql_native_signature_generate_ed25519(
  actql_native_signature_library *library,
  moonbit_bytes_t private_der, int32_t private_length,
  moonbit_bytes_t public_der, int32_t public_length
) {
  ACTQL_SIGNATURE_SCOPE(library, 2);
  if (!actql_signature_library_available(library) ||
      library->diagnostic_ceiling <= 0 || private_der == NULL ||
      public_der == NULL || private_der == public_der ||
      private_length != 48 || public_length != 44) return 2;
  memset(private_der, 0, 48);
  memset(public_der, 0, 44);
  typedef EVP_PKEY_CTX *(*new_context_fn)(int, ENGINE *);
  typedef void (*free_context_fn)(EVP_PKEY_CTX *);
  typedef int (*initialize_fn)(EVP_PKEY_CTX *);
  typedef int (*generate_fn)(EVP_PKEY_CTX *, EVP_PKEY **);
  typedef int (*raw_key_fn)(const EVP_PKEY *, unsigned char *, size_t *);
  new_context_fn new_context = NULL;
  free_context_fn free_context = NULL;
  initialize_fn initialize = NULL;
  generate_fn generate = NULL;
  raw_key_fn private_key = NULL, public_key = NULL;
  if (!actql_load_symbol(library, (void **)&new_context, "EVP_PKEY_CTX_new_id") ||
      !actql_load_symbol(library, (void **)&free_context, "EVP_PKEY_CTX_free") ||
      !actql_load_symbol(library, (void **)&initialize, "EVP_PKEY_keygen_init") ||
      !actql_load_symbol(library, (void **)&generate, "EVP_PKEY_keygen") ||
      !actql_load_symbol(library, (void **)&private_key, "EVP_PKEY_get_raw_private_key") ||
      !actql_load_symbol(library, (void **)&public_key, "EVP_PKEY_get_raw_public_key")) return 5;
  EVP_PKEY_CTX *context = new_context(ACTQL_NID_ED25519, NULL);
  if (context == NULL) return 5;
  EVP_PKEY *key = NULL;
  int initialized = initialize(context);
  int generated = initialized == 1 ? generate(context, &key) : 0;
  free_context(context);
  int result = 5;
  if (generated == 1 && key != NULL &&
      library->evp_pkey_get_base_id(key) == ACTQL_NID_ED25519) {
    size_t private_size = 32, public_size = 32;
    if (private_key(key, private_der + 16, &private_size) == 1 &&
        private_size == 32 &&
        public_key(key, public_der + 12, &public_size) == 1 && public_size == 32) {
      /* RFC 8410 AlgorithmIdentifier has no parameters. PrivateKeyInfo wraps
       * one Ed25519 seed; SubjectPublicKeyInfo wraps the corresponding key. */
      static const unsigned char private_prefix[16] = {
        0x30,0x2e,0x02,0x01,0x00,0x30,0x05,0x06,
        0x03,0x2b,0x65,0x70,0x04,0x22,0x04,0x20
      };
      static const unsigned char public_prefix[12] = {
        0x30,0x2a,0x30,0x05,0x06,0x03,0x2b,0x65,0x70,0x03,0x21,0x00
      };
      memcpy(private_der, private_prefix, sizeof(private_prefix));
      memcpy(public_der, public_prefix, sizeof(public_prefix));
      result = 0;
    }
  }
  if (key != NULL) library->evp_pkey_free(key);
  if (result != 0) {
    memset(private_der, 0, 48);
    memset(public_der, 0, 44);
  }
  return result;
}

/* The wrapper retires its temporary DER immediately after PEM encoding.
 * Returned private PEM remains secret caller-owned material, not erased here. */
MOONBIT_FFI_EXPORT
void actql_native_signature_clear_key_der(moonbit_bytes_t bytes, int32_t length) {
  if (bytes == NULL || length != 48) return;
  volatile unsigned char *cursor = bytes;
  for (int32_t i = 0; i < length; i++) cursor[i] = 0;
}
