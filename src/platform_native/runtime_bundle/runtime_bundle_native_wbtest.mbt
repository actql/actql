///|
test "native bundle admission binds authority target and canonical preimage" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY") is Some(path) else {
    return
  }
  let library = @signature.load_library(path).unwrap()
  let public_key = "-----BEGIN PUBLIC KEY-----\n" +
    "MCowBQYDK2VwAyEA0EqyMnQrtKs6E2i9RhXk5tAiSrcaAWuvhSCjMsl3hzc=\n" +
    "-----END PUBLIC KEY-----\n"
  let body = "{\"bundle_name\":\"native-runtime\",\"components\":[{\"bytes\":\"12\"," +
    "\"cid\":\"sha256:" +
    "a".repeat(64) +
    "\",\"role\":\"runtime_executable\"}],\"connector_registration\":\"local\"," +
    "\"connector_revision\":\"local/1\"," +
    "\"issuer_authority\":\"bundle-authority-a\"," +
    "\"revision\":\"native/1\"," +
    "\"strategy_revision\":\"strategy/1\"," +
    "\"target_triple\":\"aarch64-apple-darwin\"," +
    "\"version\":\"actql-remote-runtime-bundle/0.1\"}"
  let runtime_bundle_cid = "sha256:0d2749ebe4893ee0b8611759d5e102c8f060e0a5e144c51855cabc8e72c95104"
  let signature = "mbxtoDzdPMPGrO2vJ-BqAHLgZ8mShCscH6TY2yGTWX5vQCUW2eFcxGC9kGVLAwrm" +
    "L8Dq1H-39S30NH9hokXaDg"
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
