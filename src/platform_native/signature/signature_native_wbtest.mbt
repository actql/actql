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
