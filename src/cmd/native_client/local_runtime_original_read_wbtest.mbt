///|
// The independent fixture is also valid for the legacy reader. Missing supply
// must refuse rather than selecting that path or inferring it from metadata.
test "runtime original read does not replace missing carrier with a valid legacy package" {
  let path = runtime_namespace_fixture("unchanged")
  let hash = @env.get_env_var(
    "ACTQL_TEST_NATIVE_RUNTIME_NAMESPACE_MANIFEST_SHA256",
  ).unwrap()
  assert_true(
    @local_host.open_native_local_packaged_runtime_in_original_read(
      None,
      path,
      "a".repeat(40),
      "darwin-arm64",
      hash,
      128,
    )
    is Err(Refused(OriginalReadUnavailable)),
  )
}

///|
test "runtime original read missing supply refuses before a new Root or path repair" {
  for path in [runtime_namespace_fixture("never-acquired"), "relative"] {
    assert_true(
      @local_host.open_native_local_packaged_runtime_in_original_read(
        None,
        path,
        "a".repeat(40),
        "darwin-arm64",
        "b".repeat(64),
        128,
      )
      is Err(Refused(OriginalReadUnavailable)),
    )
  }
}
