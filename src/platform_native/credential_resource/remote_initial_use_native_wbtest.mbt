///|
test "Remote initial claim refusal consumes no ordinal and creates no nominal use" {
  let (database, client, origin, secret) = remote_retention_physical_fixture(
    ".initial-refused",
  )
  let scope = credential_test_scope(origin)
  let grant = local_resource_test_remote_grant(scope)
  let mut claims = 0
  let mut retained = 0
  let mut send_authorizations = 0
  let service = install_native_credential_resource_service_with_clock(
    database,
    client,
    [{ resource_origin: origin, operation: scope.operation, path: "/credential",
      secret_path: secret, verb: @http.Get, max_request_bytes: 0, }],
    authorization => {
      if authorization.stage == "send" { send_authorizations += 1 }
      true
    },
    () => 1L,
    claim_initial_remote_use=Some((original_grant, original_id, original_scope) => {
      claims += 1
      if !physical_equal(original_grant, grant) { return Err(InvalidConfiguration) }
      if original_id != "original-use" || original_scope.dispatch_request_cid != scope.dispatch_request_cid {
        return Err(InvalidConfiguration)
      }
      Err(Journal(@sqlite.CapacityExceeded))
    }),
    retain_remote_use=Some(_ => { retained += 1; Ok(()) }),
  ).unwrap()
  assert_true(call_native_credential_resource(service, grant, "original-use", scope)
    is Err(Journal(@sqlite.CapacityExceeded)))
  assert_true(query_native_credential_use(service, grant, "original-use", scope)
    is Err(Journal(@sqlite.NotFound)))
  // Inspect the existing ordinal Owner after refusal, not only a callback count.
  assert_true(database.claim_ordinal_action(use_scope(@credential.credential_grant_cid(grant)), "original-use", 2L).unwrap() is @sqlite.Fresh(1L))
  assert_eq(claims, 1)
  assert_eq(retained, 0)
  assert_eq(send_authorizations, 0)
  assert_true(client.close())
  database.close()
}

///|
test "Remote original use replay skips initial claim and preserves unresolved custody" {
  let (database, client, origin, secret) = remote_retention_physical_fixture(
    ".initial-replay",
  )
  let scope = credential_test_scope(origin)
  let grant = local_resource_test_remote_grant(scope)
  let mut claims = 0
  let mut retained = 0
  let mut send_authorizations = 0
  let service = install_native_credential_resource_service_with_clock(
    database,
    client,
    [{ resource_origin: origin, operation: scope.operation, path: "/credential",
      secret_path: secret, verb: @http.Get, max_request_bytes: 0, }],
    authorization => {
      if authorization.stage == "send" { send_authorizations += 1 }
      true
    },
    () => 1L,
    claim_initial_remote_use=Some((_, _, _) => {
      claims += 1
      if claims != 1 { return Err(AccessDenied) }
      Ok(())
    }),
    retain_remote_use=Some(_ => {
      retained += 1
      Err(Journal(@sqlite.CapacityExceeded))
    }),
  ).unwrap()
  assert_true(call_native_credential_resource(service, grant, "original-use", scope)
    is Err(Journal(@sqlite.CapacityExceeded)))
  let original = query_native_credential_use(service, grant, "original-use", scope).unwrap()
  let original_record = database.read(use_scope(@credential.credential_grant_cid(grant)), "original-use").unwrap()
  assert_eq(original.outcome, "claimed")
  assert_true(call_native_credential_resource(service, grant, "original-use", scope)
    is Err(UseAlreadyClaimed))
  let replay = query_native_credential_use(service, grant, "original-use", scope).unwrap()
  assert_eq(replay.use_cid, original.use_cid)
  assert_eq(replay.outcome, original.outcome)
  assert_eq(replay.status, original.status)
  let after = database.read(use_scope(@credential.credential_grant_cid(grant)), "original-use").unwrap()
  assert_eq(after.revision, original_record.revision)
  assert_eq(after.body, original_record.body)
  assert_eq(claims, 1)
  assert_eq(retained, 1)
  assert_eq(send_authorizations, 0)
  assert_true(client.close())
  database.close()
}

///|
test "Remote initial claim cannot bypass current permission before use selection" {
  let (database, client, origin, secret) = remote_retention_physical_fixture(
    ".initial-current",
  )
  let scope = credential_test_scope(origin)
  let grant = local_resource_test_remote_grant(scope)
  let mut current = true
  let mut retained = 0
  let service = install_native_credential_resource_service_with_clock(
    database,
    client,
    [{ resource_origin: origin, operation: scope.operation, path: "/credential",
      secret_path: secret, verb: @http.Get, max_request_bytes: 0, }],
    _ => true,
    () => 1L,
    claim_initial_remote_use=Some((_, _, _) => { current = false; Ok(()) }),
    retain_remote_use=Some(_ => { retained += 1; Ok(()) }),
  ).unwrap()
  assert_true(call_native_credential_resource_guarded_request_at_path(
    service, grant, "original-use", scope, @http.Get, "/credential", b"", () => current,
  ) is Err(AccessDenied))
  assert_true(query_native_credential_use(service, grant, "original-use", scope)
    is Err(Journal(@sqlite.NotFound)))
  assert_true(database.claim_ordinal_action(use_scope(@credential.credential_grant_cid(grant)), "original-use", 2L).unwrap() is @sqlite.Fresh(1L))
  assert_eq(retained, 0)
  assert_true(client.close())
  database.close()
}
