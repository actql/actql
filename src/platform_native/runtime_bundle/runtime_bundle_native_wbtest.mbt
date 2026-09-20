///|
test "native bundle admission binds authority target and canonical preimage" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY") is Some(path) else {
    return
  }
  let library = @signature.load_library(path).unwrap()
  let public_key = "-----BEGIN PUBLIC KEY-----\n" +
    "MCowBQYDK2VwAyEA11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo=\n" +
    "-----END PUBLIC KEY-----\n"
  let body = "{\"bundle_name\":\"native-runtime\",\"component_bytes\":\"12\"," +
    "\"component_cid\":\"sha256:" +
    "a".repeat(64) +
    "\",\"connector_registration\":\"local\"," +
    "\"connector_revision\":\"local/1\"," +
    "\"issuer_authority\":\"bundle-authority-a\"," +
    "\"revision\":\"native/1\"," +
    "\"strategy_revision\":\"strategy/1\"," +
    "\"target_triple\":\"aarch64-apple-darwin\"," +
    "\"version\":\"actql-remote-runtime-bundle/0.1\"}"
  let runtime_bundle_cid = "sha256:6e7d6989d49341ba9c47c937b72994b4a8b869adf54ea65946af76cce56010d7"
  let signature = "VHc5Y9n1leMbzwAxezD-BeWXqC4u1vUX29O-q9jz1Z0-wx0h31XnQzeGOu8JM5NN" +
    "1eqIJUFygwj8TB1m3Q7bAw"
  let authorities = [
    {
      issuer_authority: "bundle-authority-a",
      key_id: "key-a",
      public_key_pem: public_key,
    },
  ]
  let admitted = admit_signed_bundle(
    library, authorities, "actql-remote-runtime-bundle-signature/0.1", "key-a", runtime_bundle_cid,
    body, signature, "aarch64-apple-darwin",
  ).unwrap()
  assert_eq(@bundle.bundle_manifest_identity(admitted), runtime_bundle_cid)
  guard admit_signed_bundle(
      library,
      authorities,
      "actql-remote-runtime-bundle-signature/0.1",
      "key-a",
      runtime_bundle_cid,
      body,
      "A" + signature[1:].to_owned(),
      "aarch64-apple-darwin",
    )
    is Err(AuthorityRejected) else {
    fail("altered native bundle signature was accepted")
  }
  guard admit_signed_bundle(
      library, authorities, "actql-remote-runtime-bundle-signature/0.1", "key-a",
      runtime_bundle_cid, body, signature, "x86_64-unknown-linux-gnu",
    )
    is Err(TargetRejected) else {
    fail("foreign native bundle target was accepted")
  }
}
