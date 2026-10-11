///|
test "native Ed25519 verification uses the configured crypto library" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY") is Some(path) else {
    return
  }
  let library = load_library(path).unwrap()
  let public_key = "-----BEGIN PUBLIC KEY-----\n" +
    "MCowBQYDK2VwAyEA11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo=\n" +
    "-----END PUBLIC KEY-----\n"
  let signature = "5VZDAMNgrHKQhuLMgG6CioSHfx645dl02HPgZSJJAVVfuIIVkKM7rMYeOXAc-" +
    "bRr0lv18FlbviRlUUFDjnoQCw"
  assert_eq(
    library.verify_ed25519(public_key, Bytes::new(0), signature),
    Ok(true),
  )
  let altered = "A" + signature[1:].to_owned()
  assert_eq(
    library.verify_ed25519(public_key, Bytes::new(0), altered),
    Ok(false),
  )
  assert_eq(
    library.verify_ed25519(public_key, Bytes::new(0), signature + "="),
    Err(InvalidInput),
  )
}

///|
test "native SHA-256 preserves the standard incremental digest" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY") is Some(path) else {
    return
  }
  let library = load_library(path).unwrap()
  let empty = library.sha256_hasher().unwrap()
  assert_eq(
    empty.finish_hex(),
    Ok("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
  )
  let split = library.sha256_hasher().unwrap()
  split.update(@utf8.encode("a")).unwrap()
  split.update(@utf8.encode("bc")).unwrap()
  assert_eq(
    split.finish_hex(),
    Ok("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
  )
  assert_true(split.update(@utf8.encode("x")) is Err(_))
  assert_true(split.finish_hex() is Err(_))
}

///|
test "native HMAC authenticates exact bytes with independent RFC 4231 vectors" {
  let library = load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY").unwrap(),
  ).unwrap()
  // RFC 4231 sections 4.2 and 4.3. Expected tags are not derived from this FFI.
  // https://datatracker.ietf.org/doc/html/rfc4231#section-4.2
  for
    (key, message, expected) in [
      (
        Bytes::make(20, 11),
        "Hi There",
        "sDRMYdjbOFNcqK/OrwvxK4gdwgDJgz2nJuk3bC4yz/c=",
      ),
      (
        @utf8.encode("Jefe"),
        "what do ya want for nothing?",
        "W9zBRr9gdU5qBCQmCJV1x1oAPwidJzmDnexYuWTsOEM=",
      ),
    ] {
    let tag = @base64.decode(expected)
    assert_eq(library.hmac_sha256(key, @utf8.encode(message)), Ok(tag))
    assert_eq(
      library.verify_hmac_sha256(key, @utf8.encode(message), tag),
      Ok(true),
    )
    assert_eq(
      library.verify_hmac_sha256(key, @utf8.encode(message + "!"), tag),
      Ok(false),
    )
    assert_eq(
      library.verify_hmac_sha256(
        @utf8.encode("another key"),
        @utf8.encode(message),
        tag,
      ),
      Ok(false),
    )
    let altered = Bytes::makei(32, i => {
      if i == 31 {
        tag[i] ^ 1
      } else {
        tag[i]
      }
    })
    assert_eq(
      library.verify_hmac_sha256(key, @utf8.encode(message), altered),
      Ok(false),
    )
  }
  let key = Bytes::make(32, 42)
  let decomposed = library
    .hmac_sha256(key, @utf8.encode("e\u0301\r\n"))
    .unwrap()
  assert_eq(
    library.verify_hmac_sha256(key, @utf8.encode("é\r\n"), decomposed),
    Ok(false),
  )
  assert_eq(
    library.verify_hmac_sha256(key, @utf8.encode("e\u0301\n"), decomposed),
    Ok(false),
  )
  assert_eq(library.hmac_sha256(Bytes::new(0), b"message"), Err(InvalidInput))
  assert_eq(
    library.hmac_sha256(Bytes::make(4097, 0), b"message"),
    Err(InvalidInput),
  )
  assert_eq(
    library.hmac_sha256(key, Bytes::make(1048577, 0)),
    Err(InvalidInput),
  )
  assert_eq(
    library.verify_hmac_sha256(key, b"message", Bytes::make(31, 0)),
    Err(InvalidInput),
  )
}

///|
test "native secure randomness respects explicit finite bounds" {
  let library = load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY").unwrap(),
  ).unwrap()
  assert_eq(library.random_bytes(0), Err(InvalidInput))
  assert_eq(library.random_bytes(4097), Err(InvalidInput))
  assert_eq(library.random_bytes(32).unwrap().length(), 32)
  assert_eq(library.random_bytes(4096).unwrap().length(), 4096)
}
