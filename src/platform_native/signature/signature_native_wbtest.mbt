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
