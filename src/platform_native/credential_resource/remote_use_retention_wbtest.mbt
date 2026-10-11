///|
fn remote_retention_test_use() -> NativeOwnedCredentialUse {
  let scope = credential_test_scope("https://resource.example")
  prepare_owned_credential_use(
    RemoteGrant(local_resource_test_remote_grant(scope)),
    "original-use",
    1L,
    0,
    false,
    RemoteScope(scope),
  ).unwrap()
}

///|
test "Remote pre-send retention hands off the same nominal use without reissuing it" {
  let original = remote_retention_test_use()
  let mut called = 0
  retain_remote_use_before_send(
    original,
    Some(original_use => {
      called += 1
      guard original is RemoteUse(expected) else {
        return Err(InvalidConfiguration)
      }
      if !physical_equal(original_use, expected) {
        return Err(InvalidConfiguration)
      }
      Ok(())
    }),
  ).unwrap()
  assert_eq(called, 1)
}

///|
test "Remote pre-send retention preserves an unconfirmed-custody issue" {
  let original = remote_retention_test_use()
  let mut called = 0
  assert_true(
    retain_remote_use_before_send(
      original,
      Some(_ => {
        called += 1
        Err(Journal(@sqlite.CapacityExceeded))
      }),
    )
    is Err(Journal(@sqlite.CapacityExceeded)),
  )
  assert_eq(called, 1)
}

///|
test "Remote use retention does not reinterpret Local or preparation custody" {
  let local_use = prepare_owned_credential_use(
    LocalGrant(local_resource_test_grant()),
    "original-local-use",
    1L,
    0,
    false,
    LocalScope(local_resource_test_scope()),
  ).unwrap()
  let scope = native_preparation_identity_scope()
  let preparation = prepare_owned_credential_use(
    PreparationGrant(
      @credential.prepare_local_preparation_credential_grant(
        "local-authority-a", scope, 2000000000000L, 2,
      ).unwrap(),
    ),
    "original-preparation-use",
    1L,
    0,
    false,
    PreparationScope(scope),
  ).unwrap()
  let mut called = 0
  let forbidden : (@credential.RemoteCredentialUse) -> Result[
    Unit,
    NativeCredentialResourceIssue,
  ] = _ => {
    called += 1
    Err(AccessDenied)
  }
  retain_remote_use_before_send(local_use, Some(forbidden)).unwrap()
  retain_remote_use_before_send(preparation, Some(forbidden)).unwrap()
  assert_eq(called, 0)
}
