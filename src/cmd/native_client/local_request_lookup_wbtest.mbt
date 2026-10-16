///|
// Fresh physical Host/Account/SQLite; no old Run, fake Store or Provider.
fn request_lookup_fixture(
  name : String,
  read? : Bool = true,
  existing? : Bool = false,
) -> (
  @local_host.NativeLocalHostConnection,
  LocalHostSettings,
  @local_crypto.Library,
) raise {
  let base = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let root = base + "/" + name
  if !existing {
    let parent = @local_filesystem.open_private_root(base).unwrap()
    parent.create_directory(name).unwrap() |> ignore
    parent.close().unwrap()
    let files = @local_filesystem.open_private_root(root).unwrap()
    let operations = if read { "[\"read\",\"submit\"]" } else { "[\"submit\"]" }
    let body = @utf8.encode(
      "{\"version\":\"actql-execution-account-config/0.1\",\"account_id\":\"operator\",\"entries\":[{\"entry_id\":\"request-lookup\",\"outcome\":\"allow\",\"principal\":{\"any_of\":[\"operator\"]},\"connection\":{\"any_of\":[\"cli\"]},\"resource\":{\"any_of\":[\"run\"]},\"operation\":{\"any_of\":" +
      operations +
      "},\"exclusions\":[]}]}",
    )
    let writer = files.create_writer("account.stage", 4096L).unwrap()
    writer.append(body).unwrap()
    writer.seal("account.json").unwrap() |> ignore
    files.close().unwrap()
  }
  let crypto_path = @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY").unwrap()
  let sqlite_path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap()
  let crypto = @local_crypto.load_library(crypto_path).unwrap()
  let sqlite = @local_sqlite.load_library(sqlite_path).unwrap()
  let host = @local_host.begin_native_local_host_adoption(
      root,
      "host",
      root,
      "account.json",
      "operator",
      crypto,
      existing_only=existing,
    )
    .unwrap()
    .open_journal(sqlite, crypto, 100.0, 8, 8388608L)
    .unwrap()
  let settings : LocalHostSettings = {
    account_file: "account.json",
    account_id: "operator",
    principal: "operator",
    connection: "cli",
    state_parent: root,
    state_name: "host",
    managed_root: root,
    sqlite_library: sqlite_path,
    signature_library: crypto_path,
    ttl_ms: 100.0,
    record_limit: 8,
    snapshot_bytes: 8388608L,
    installation_files: [],
    source_file: None,
    run_file: None,
    read_file: None,
    run_policy_profile_file: None,
    reviewer_file: None,
  }
  (host, settings, crypto)
}

///|
fn request_lookup_original(
  host : @local_host.NativeLocalHostConnection,
  settings : LocalHostSettings,
  crypto : @local_crypto.Library,
  nonce : String,
) -> (
  @local_host.NativeClientSubmissionReference,
  @local_host.NativeClientSubmissionEpoch,
  @run_host.ClientSubmittedIntent,
  String,
) raise {
  let scope = host
    .authority_scope_cid(settings.principal, settings.connection, crypto)
    .unwrap()
  let allowed = local_submit_allowed(host, settings, crypto, scope)
  let epoch = host
    .epoch_authority()
    .unwrap()
    .issue_epoch(scope, allowed, 1000.0)
    .unwrap()
  let reference = @local_host.prepare_native_client_submission_reference(
    epoch, nonce,
  ).unwrap()
  let intent = @run_host.prepare_client_submitted_intent(
    "{\"kind\":\"aql\",\"input\":{\"format\":\"sql\",\"text\":\"SELECT 1 AS n\"},\"parameters\":null}",
    65536, 8192, 64,
  ).unwrap()
  host
  .run_journal()
  .unwrap()
  .record_submitted_intent(
    host.epoch_authority().unwrap(),
    reference,
    intent,
    scope,
    allowed,
    1001.0,
  )
  .unwrap()
  |> ignore
  (reference, epoch, intent, scope)
}

///|
test "request ID lookup selects the retained preparing reference and CLI uses no reference file" {
  let (host, settings, crypto) = request_lookup_fixture("request-original")
  let (reference, _, intent, _) = request_lookup_original(
    host, settings, crypto, "original-nonce",
  )
  let request_id = @local_host.native_client_submission_request_id(reference)
  let selected = host.lookup_submission_reference_by_request_id(
    crypto, "operator", "cli", request_id, 1002.0,
  )
  let child = command().parse(argv=[
      "lookup-request", "--request-id", request_id,
    ]).subcommand.unwrap().1
  let reply = local_request_lookup(host, settings, crypto, child)
  host.close().unwrap()
  assert_eq(
    @local_host.native_client_submission_reference_wire(
      selected.unwrap().unwrap(),
    ),
    @local_host.native_client_submission_reference_wire(reference),
  )
  let root = @decode.open_object(local_input_cursor(reply)).unwrap()
  assert_eq(
    @decode.text(@decode.lookup(root, "kind").unwrap()),
    Ok("local_submission_lookup"),
  )
  assert_eq(
    @decode.text(@decode.lookup(root, "history").unwrap()),
    Ok("retained"),
  )
  assert_eq(
    @decode.text(@decode.lookup(root, "phase").unwrap()),
    Ok("preparing"),
  )
  assert_eq(
    @decode.text(@decode.lookup(root, "requestId").unwrap()),
    Ok(request_id),
  )
  assert_eq(
    @decode.text(@decode.lookup(root, "intentCid").unwrap()),
    Ok(@run_host.client_submitted_intent_cid(intent)),
  )
  assert_true(@decode.lookup(root, "ref") is None)
  assert_true(local_product_operation("lookup-request"))
}

///|
test "unknown IDs and nonces cannot create or select a fresh Submission" {
  let (host, settings, crypto) = request_lookup_fixture("request-missing")
  let (reference, _, _, scope) = request_lookup_original(
    host, settings, crypto, "original-nonce",
  )
  let journal = host.run_journal().unwrap()
  let before = journal
    .lookup_submitted_intent(
      host.epoch_authority().unwrap(),
      reference,
      scope,
      true,
      1002.0,
    )
    .unwrap()
  let missing = host.lookup_submission_reference_by_request_id(
    crypto,
    "operator",
    "cli",
    "sha256:" + "0".repeat(64),
    1003.0,
  )
  let nonce = host.lookup_submission_reference_by_request_id(
    crypto, "operator", "cli", "original-nonce", 1003.0,
  )
  let after = journal
    .lookup_submitted_intent(
      host.epoch_authority().unwrap(),
      reference,
      scope,
      true,
      1003.0,
    )
    .unwrap()
  host.close().unwrap()
  assert_true(missing is Ok(None))
  assert_true(nonce is Err(@local_host.InvalidSubmission))
  guard before is Submitted(before) && after is Submitted(after) else {
    fail("original preparing intent lost")
  }
  assert_eq(
    @local_host.native_client_submitted_intent_revision(before),
    @local_host.native_client_submitted_intent_revision(after),
  )
  assert_eq(
    @run_host.client_submitted_intent_wire(
      @local_host.native_client_submitted_intent(before),
    ),
    @run_host.client_submitted_intent_wire(
      @local_host.native_client_submitted_intent(after),
    ),
  )
  assert_true(@local_host.native_client_submitted_run_admission(after) is None)
}

///|
test "current RunRead is independent of the original submit authorization" {
  let (host, settings, crypto) = request_lookup_fixture(
    "request-read-denied",
    read=false,
  )
  let (reference, _, _, scope) = request_lookup_original(
    host, settings, crypto, "submit-only",
  )
  let submit = local_submit_allowed(host, settings, crypto, scope)
  let selected = host.lookup_submission_reference_by_request_id(
    crypto,
    "operator",
    "cli",
    @local_host.native_client_submission_request_id(reference),
    1002.0,
  )
  host.close().unwrap()
  assert_true(submit)
  assert_true(selected is Err(@local_host.AuthorizationDenied))
}

///|
test "history lookup after expiry and reopen preserves the same token without new admission" {
  let name = "request-history"
  let (host, settings, crypto) = request_lookup_fixture(name)
  let (reference, token, intent, scope) = request_lookup_original(
    host, settings, crypto, "history",
  )
  let wire = @local_host.native_client_submission_reference_wire(reference)
  let request_id = @local_host.native_client_submission_request_id(reference)
  let at_expiry = host.lookup_submission_reference_by_request_id(
    crypto, "operator", "cli", request_id, 1100.0,
  )
  host.close().unwrap()
  let (reopened, _, _) = request_lookup_fixture(name, existing=true)
  let restored = reopened.lookup_submission_reference_by_request_id(
    crypto, "operator", "cli", request_id, 1101.0,
  )
  let fresh = @local_host.prepare_native_client_submission_reference(
    token, "new-after-expiry",
  ).unwrap()
  let refused = reopened
    .run_journal()
    .unwrap()
    .record_submitted_intent(
      reopened.epoch_authority().unwrap(),
      fresh,
      intent,
      scope,
      true,
      1101.0,
    )
  reopened.close().unwrap()
  assert_eq(
    @local_host.native_client_submission_reference_wire(
      at_expiry.unwrap().unwrap(),
    ),
    wire,
  )
  assert_eq(
    @local_host.native_client_submission_reference_wire(
      restored.unwrap().unwrap(),
    ),
    wire,
  )
  assert_true(
    refused is Err(@local_host.SubmissionEpochRejected(@request_scope.Expired)),
  )
}

///|
test "same epoch different nonce and different epoch same nonce keep distinct original IDs" {
  let (host, settings, crypto) = request_lookup_fixture("request-identities")
  let (first, token, intent, scope) = request_lookup_original(
    host, settings, crypto, "same-nonce",
  )
  let other_nonce = @local_host.prepare_native_client_submission_reference(
    token, "other-nonce",
  ).unwrap()
  let epoch = host.epoch_authority().unwrap()
  let other_token = epoch.issue_epoch(scope, true, 1002.0).unwrap()
  let other_epoch = @local_host.prepare_native_client_submission_reference(
    other_token, "same-nonce",
  ).unwrap()
  let journal = host.run_journal().unwrap()
  for reference in [other_nonce, other_epoch] {
    journal
    .record_submitted_intent(epoch, reference, intent, scope, true, 1003.0)
    .unwrap()
    |> ignore
  }
  let selected = [first, other_nonce, other_epoch].map(reference => {
    host.lookup_submission_reference_by_request_id(
      crypto,
      "operator",
      "cli",
      @local_host.native_client_submission_request_id(reference),
      1004.0,
    )
  })
  host.close().unwrap()
  let originals = [first, other_nonce, other_epoch]
  for index in 0..<3 {
    assert_eq(
      @local_host.native_client_submission_reference_wire(
        selected[index].unwrap().unwrap(),
      ),
      @local_host.native_client_submission_reference_wire(originals[index]),
    )
    for other in 0..<index {
      assert_true(
        @local_host.native_client_submission_request_id(originals[index]) !=
        @local_host.native_client_submission_request_id(originals[other]),
      )
    }
  }
}

///|
test "foreign principal and retired Host cannot turn an original ID into current read permission" {
  let (host, settings, crypto) = request_lookup_fixture("request-current")
  let (reference, _, _, _) = request_lookup_original(
    host, settings, crypto, "current",
  )
  let id = @local_host.native_client_submission_request_id(reference)
  let foreign = host.lookup_submission_reference_by_request_id(
    crypto, "foreign", "cli", id, 1002.0,
  )
  host.close().unwrap()
  let retired = host.lookup_submission_reference_by_request_id(
    crypto, "operator", "cli", id, 1003.0,
  )
  assert_true(foreign is Err(@local_host.AuthorizationDenied))
  assert_true(retired is Err(@local_host.AuthorizationDenied))
}

///|
// Deliberate corruption is confined to these new disposable physical fixtures.
fn request_lookup_corrupt_row(
  settings : LocalHostSettings,
  reference : @local_host.NativeClientSubmissionReference,
  body : Bytes,
) {
  let library = @local_sqlite.load_library(settings.sqlite_library).unwrap()
  let database = library
    .open_database(settings.state_parent + "/host/client.sqlite3", 8388608L)
    .unwrap()
  let id = @local_host.native_client_submission_request_id(reference)
  database.begin_immediate().unwrap()
  let row = database.read("client_submitted_intents", id).unwrap()
  database
  .compare_exchange("client_submitted_intents", id, row.revision, body)
  .unwrap()
  |> ignore
  database.commit().unwrap()
  database.close_checked().unwrap()
}

///|
test "malformed nonselected custody prevents returning an otherwise valid selected reference" {
  let (host, settings, crypto) = request_lookup_fixture("request-full-custody")
  let (reference, token, intent, scope) = request_lookup_original(
    host, settings, crypto, "selected",
  )
  let other = @local_host.prepare_native_client_submission_reference(
    token, "nonselected",
  ).unwrap()
  host
  .run_journal()
  .unwrap()
  .record_submitted_intent(
    host.epoch_authority().unwrap(),
    other,
    intent,
    scope,
    true,
    1002.0,
  )
  .unwrap()
  |> ignore
  request_lookup_corrupt_row(settings, other, b"{}")
  let selected = host.lookup_submission_reference_by_request_id(
    crypto,
    "operator",
    "cli",
    @local_host.native_client_submission_request_id(reference),
    1003.0,
  )
  host.close().unwrap()
  assert_true(selected is Err(@local_host.CustodyLost))
}

///|
test "selected reference identity without its original HMAC is not authentic custody" {
  let (host, settings, crypto) = request_lookup_fixture("request-authenticator")
  let (reference, _, intent, _) = request_lookup_original(
    host, settings, crypto, "authenticator",
  )
  let wire = @local_host.native_client_submission_reference_wire(reference)
  guard @json.parse(wire) is Object(fields) &&
    fields.get("epoch") is Some(Object(token)) &&
    token.get("authenticator") is Some(String(tag)) else {
    host.close().unwrap()
    fail("public token shape")
  }
  let different = (if tag[0] == '0' { "1" } else { "0" }) + tag[1:]
  token["authenticator"] = Json::string(different)
  fields["epoch"] = Json::object(token)
  let forged = @local_host.admit_native_client_submission_reference(
    encode_request_json(Json::object(fields), 4096),
  ).unwrap()
  let body = @run_host.client_submitted_intent_journal_row_body(
    @local_host.native_client_submission_reference_wire(forged),
    intent,
  ).unwrap()
  request_lookup_corrupt_row(settings, reference, body)
  let selected = host.lookup_submission_reference_by_request_id(
    crypto,
    "operator",
    "cli",
    @local_host.native_client_submission_request_id(reference),
    1003.0,
  )
  host.close().unwrap()
  assert_true(selected is Err(@local_host.Epoch(@local_host.Unverifiable)))
}
