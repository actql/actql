///|
fn key_generation_test_library() -> Library {
  load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY").unwrap(),
    diagnostic_ceiling=Some(256),
  ).unwrap()
}

///|
test "fresh Ed25519 material signs exact bytes and refuses another generated public key" {
  let library = key_generation_test_library()
  let (private_key, public_key) = library.generate_ed25519_key_pair().unwrap()
  let (other_private, other_public) = library
    .generate_ed25519_key_pair()
    .unwrap()
  let message = @utf8.encode("same original e\u0301\r\n")
  let signature = library.sign_ed25519(private_key, message).unwrap()
  assert_true(
    library.verify_ed25519(public_key, message, signature) == Ok(true),
  )
  assert_true(
    library.verify_ed25519(other_public, message, signature) == Ok(false),
  )
  assert_true(
    library.verify_ed25519(
      public_key,
      @utf8.encode("same original é\n"),
      signature,
    ) ==
    Ok(false),
  )
  let other_signature = library.sign_ed25519(other_private, message).unwrap()
  assert_true(
    library.verify_ed25519(other_public, message, other_signature) == Ok(true),
  )
}

///|
test "generated PEM has the exact Ed25519 RFC 8410 structures without logging secret values" {
  let library = key_generation_test_library()
  let (private_key, public_key) = library.generate_ed25519_key_pair().unwrap()
  // Boolean assertions deliberately keep generated secret bytes out of failure
  // output. The independent prefixes are RFC 8410, not product-derived values.
  assert_true(private_key.length() == 119)
  assert_true(public_key.length() == 113)
  let private_text = @utf8.decode(private_key).unwrap()
  let private_lines = private_text.split("\n").to_array()
  let public_lines = public_key.split("\n").to_array()
  assert_true(private_lines.length() == 4 && public_lines.length() == 4)
  assert_true(private_lines[0] == "-----BEGIN PRIVATE KEY-----")
  assert_true(private_lines[2] == "-----END PRIVATE KEY-----")
  assert_true(public_lines[0] == "-----BEGIN PUBLIC KEY-----")
  assert_true(public_lines[2] == "-----END PUBLIC KEY-----")
  let private_der = @base64.decode(private_lines[1])
  let public_der = @base64.decode(public_lines[1])
  assert_true(private_der.length() == 48 && public_der.length() == 44)
  assert_true(
    private_der[0:16].to_owned() ==
    b"\x30\x2e\x02\x01\x00\x30\x05\x06\x03\x2b\x65\x70\x04\x22\x04\x20",
  )
  assert_true(
    public_der[0:12].to_owned() ==
    b"\x30\x2a\x30\x05\x06\x03\x2b\x65\x70\x03\x21\x00",
  )
  assert_true(
    library.ed25519_public_key_raw32(public_key).unwrap() ==
    public_der[12:44].to_owned(),
  )
}

///|
test "generation refuses omitted diagnostic original and invalid FFI buffers before mutation" {
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY").unwrap()
  let legacy = load_library(path).unwrap()
  assert_true(legacy.generate_ed25519_key_pair() is Err(InvalidInput))
  let library = key_generation_test_library()
  for (private_length, public_length) in [(0, 44), (47, 44), (48, 43), (49, 44)] {
    let private_der = Bytes::make(48, 77)
    let public_der = Bytes::make(44, 88)
    assert_eq(
      generate_ed25519_ffi(
        library, private_der, private_length, public_der, public_length,
      ),
      2,
    )
    assert_true(private_der == Bytes::make(48, 77))
    assert_true(public_der == Bytes::make(44, 88))
  }
  let shared = Bytes::make(48, 99)
  assert_eq(generate_ed25519_ffi(library, shared, 48, shared, 44), 2)
  assert_true(shared == Bytes::make(48, 99))
}

///|
test "temporary key DER is explicitly retired while the returned PEM remains usable" {
  let library = key_generation_test_library()
  let private_der = Bytes::make(48, 0)
  let public_der = Bytes::make(44, 0)
  assert_eq(generate_ed25519_ffi(library, private_der, 48, public_der, 44), 0)
  clear_key_der_ffi(private_der, 48)
  assert_true(private_der == Bytes::make(48, 0))
  let (private_key, public_key) = library.generate_ed25519_key_pair().unwrap()
  let signature = library
    .sign_ed25519(private_key, b"after DER retirement")
    .unwrap()
  assert_true(
    library.verify_ed25519(public_key, b"after DER retirement", signature) ==
    Ok(true),
  )
}
