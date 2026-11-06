///|
fn[T, E] request_lookup_ok(value : Result[T, E], phase : String) -> T raise {
  match value {
    Ok(value) => value
    Err(_) => fail("Native request lookup fixture: " + phase)
  }
}

///|
fn[T] request_lookup_some(value : T?, phase : String) -> T raise {
  match value {
    Some(value) => value
    None => fail("Native request lookup fixture: " + phase)
  }
}

///|
// Fresh physical Host/Account/SQLite; no old Run, fake Store or Provider.
fn request_lookup_fixture(
  name : String,
  read? : Bool = true,
  existing? : Bool = false,
  submit? : Bool = true,
  ttl_ms? : Double = 100.0,
) -> (
  @local_host.NativeLocalHostConnection,
  LocalHostSettings,
  @local_crypto.Library,
) raise {
  let base = request_lookup_some(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT"),
    "root",
  )
  let root = base + "/" + name
  if !existing {
    let parent = request_lookup_ok(
      @local_filesystem.open_private_root(base),
      "parent",
    )
    request_lookup_ok(parent.create_directory(name), "directory") |> ignore
    request_lookup_ok(parent.close(), "parent.close")
    let files = request_lookup_ok(
      @local_filesystem.open_private_root(root),
      "files",
    )
    let operations = if read {
      if submit {
        "[\"read\",\"submit\"]"
      } else {
        "[\"read\"]"
      }
    } else if submit {
      "[\"submit\"]"
    } else {
      "[]"
    }
    let body = @utf8.encode(
      "{\"version\":\"actql-execution-account-config/0.1\",\"account_id\":\"operator\",\"entries\":[{\"entry_id\":\"request-lookup\",\"outcome\":\"allow\",\"principal\":{\"any_of\":[\"operator\"]},\"connection\":{\"any_of\":[\"cli\"]},\"resource\":{\"any_of\":[\"run\"]},\"operation\":{\"any_of\":" +
      operations +
      "},\"exclusions\":[]}]}",
    )
    let writer = request_lookup_ok(
      files.create_writer("account.stage", 4096L),
      "writer",
    )
    request_lookup_ok(writer.append(body), "append")
    request_lookup_ok(writer.seal("account.json"), "seal") |> ignore
    request_lookup_ok(files.close(), "files.close")
  }
  let crypto_path = request_lookup_some(
    @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY"),
    "crypto-library",
  )
  let sqlite_path = request_lookup_some(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY"),
    "sqlite-library",
  )
  let crypto = request_lookup_ok(
    @local_crypto.load_library(crypto_path),
    "crypto",
  )
  let sqlite = request_lookup_ok(
    @local_sqlite.load_library(sqlite_path),
    "sqlite",
  )
  let session = request_lookup_ok(
    @local_host.begin_native_local_host_adoption(
      root,
      "host",
      root,
      "account.json",
      "operator",
      crypto,
      existing_only=existing,
    ),
    "adoption",
  )
  let host = request_lookup_ok(
    session.open_journal(sqlite, crypto, ttl_ms, 8, 8388608L),
    "journal.open",
  )
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
    ttl_ms,
    record_limit: 8,
    snapshot_bytes: 8388608L,
    installation_files: [],
    source_file: None,
    run_file: None,
    read_file: None,
    run_policy_profile_file: None,
    reviewer_file: None,
    initial_host_signing: None,
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
  let scope = request_lookup_ok(
    host.authority_scope_cid(settings.principal, settings.connection, crypto),
    "scope",
  )
  let allowed = local_submit_allowed(host, settings, crypto, scope)
  let authority = request_lookup_ok(host.epoch_authority(), "epoch")
  let epoch = request_lookup_ok(
    authority.issue_epoch(scope, allowed, 1000.0),
    "epoch.issue",
  )
  let reference = request_lookup_ok(
    @local_host.prepare_native_client_submission_reference(epoch, nonce),
    "reference",
  )
  let intent = request_lookup_ok(
    @run_host.prepare_client_submitted_intent(
      "{\"kind\":\"aql\",\"input\":{\"format\":\"sql\",\"text\":\"SELECT 1 AS n\"},\"parameters\":null}",
      65536, 8192, 64,
    ),
    "intent",
  )
  request_lookup_ok(
    request_lookup_ok(host.run_journal(), "journal").record_submitted_intent(
      authority, reference, intent, scope, allowed, 1001.0,
    ),
    "record",
  )
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
  let child = request_lookup_some(
      command().parse(argv=["lookup-request", "--request-id", request_id]).subcommand,
      "command",
    ).1
  let reply = local_request_lookup(host, settings, crypto, child)
  request_lookup_ok(host.close(), "host.close")
  assert_eq(
    @local_host.native_client_submission_reference_wire(
      request_lookup_some(
        request_lookup_ok(selected, "select"),
        "selected.reference",
      ),
    ),
    @local_host.native_client_submission_reference_wire(reference),
  )
  let root = request_lookup_ok(
    @decode.open_object(local_input_cursor(reply)),
    "reply.object",
  )
  assert_eq(
    @decode.text(
      request_lookup_some(@decode.lookup(root, "kind"), "reply.kind"),
    ),
    Ok("local_submission_lookup"),
  )
  assert_eq(
    @decode.text(
      request_lookup_some(@decode.lookup(root, "history"), "reply.history"),
    ),
    Ok("retained"),
  )
  assert_eq(
    @decode.text(
      request_lookup_some(@decode.lookup(root, "phase"), "reply.phase"),
    ),
    Ok("preparing"),
  )
  assert_eq(
    @decode.text(
      request_lookup_some(@decode.lookup(root, "requestId"), "reply.requestId"),
    ),
    Ok(request_id),
  )
  assert_eq(
    @decode.text(
      request_lookup_some(@decode.lookup(root, "intentCid"), "reply.intentCid"),
    ),
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
  let journal = request_lookup_ok(host.run_journal(), "journal")
  let before = request_lookup_ok(
    journal.lookup_submitted_intent(
      request_lookup_ok(host.epoch_authority(), "epoch"),
      reference,
      scope,
      true,
      1002.0,
    ),
    "before",
  )
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
  let after = request_lookup_ok(
    journal.lookup_submitted_intent(
      request_lookup_ok(host.epoch_authority(), "epoch"),
      reference,
      scope,
      true,
      1003.0,
    ),
    "after",
  )
  request_lookup_ok(host.close(), "host.close")
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
  request_lookup_ok(host.close(), "host.close")
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
  request_lookup_ok(host.close(), "host.close")
  let (reopened, _, _) = request_lookup_fixture(name, existing=true)
  let restored = reopened.lookup_submission_reference_by_request_id(
    crypto, "operator", "cli", request_id, 1101.0,
  )
  let fresh = request_lookup_ok(
    @local_host.prepare_native_client_submission_reference(
      token, "new-after-expiry",
    ),
    "expired.reference",
  )
  let refused = request_lookup_ok(reopened.run_journal(), "reopened.journal").record_submitted_intent(
    request_lookup_ok(reopened.epoch_authority(), "reopened.epoch"),
    fresh,
    intent,
    scope,
    true,
    1101.0,
  )
  request_lookup_ok(reopened.close(), "reopened.close")
  assert_eq(
    @local_host.native_client_submission_reference_wire(
      request_lookup_some(
        request_lookup_ok(at_expiry, "expiry"),
        "expiry.reference",
      ),
    ),
    wire,
  )
  assert_eq(
    @local_host.native_client_submission_reference_wire(
      request_lookup_some(
        request_lookup_ok(restored, "restore"),
        "restored.reference",
      ),
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
  let other_nonce = request_lookup_ok(
    @local_host.prepare_native_client_submission_reference(token, "other-nonce"),
    "other.nonce",
  )
  let epoch = request_lookup_ok(host.epoch_authority(), "epoch")
  let other_token = request_lookup_ok(
    epoch.issue_epoch(scope, true, 1002.0),
    "other.epoch",
  )
  let other_epoch = request_lookup_ok(
    @local_host.prepare_native_client_submission_reference(
      other_token, "same-nonce",
    ),
    "other.epoch.reference",
  )
  let journal = request_lookup_ok(host.run_journal(), "journal")
  for reference in [other_nonce, other_epoch] {
    request_lookup_ok(
      journal.record_submitted_intent(
        epoch, reference, intent, scope, true, 1003.0,
      ),
      "other.record",
    )
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
  request_lookup_ok(host.close(), "host.close")
  let originals = [first, other_nonce, other_epoch]
  for index in 0..<3 {
    assert_eq(
      @local_host.native_client_submission_reference_wire(
        request_lookup_some(
          request_lookup_ok(selected[index], "select.identity"),
          "identity.reference",
        ),
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
  request_lookup_ok(host.close(), "host.close")
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
) -> Unit raise {
  let library = request_lookup_ok(
    @local_sqlite.load_library(settings.sqlite_library),
    "fault.library",
  )
  let database = request_lookup_ok(
    library.open_database(
      settings.state_parent + "/host/client.sqlite3",
      8388608L,
    ),
    "fault.database",
  )
  let id = @local_host.native_client_submission_request_id(reference)
  request_lookup_ok(database.begin_immediate(), "fault.begin")
  let row = request_lookup_ok(
    database.read("client_submitted_intents", id),
    "fault.read",
  )
  request_lookup_ok(
    database.compare_exchange(
      "client_submitted_intents",
      id,
      row.revision,
      body,
    ),
    "fault.cas",
  )
  |> ignore
  request_lookup_ok(database.commit(), "fault.commit")
  request_lookup_ok(database.close_checked(), "fault.close")
}

///|
test "selected lookup preserves its original while explicit inspection rejects malformed nonselected custody" {
  let (host, settings, crypto) = request_lookup_fixture("request-full-custody")
  let (reference, token, intent, scope) = request_lookup_original(
    host, settings, crypto, "selected",
  )
  let other = request_lookup_ok(
    @local_host.prepare_native_client_submission_reference(token, "nonselected"),
    "nonselected.reference",
  )
  request_lookup_ok(
    request_lookup_ok(host.run_journal(), "journal").record_submitted_intent(
      request_lookup_ok(host.epoch_authority(), "epoch"),
      other,
      intent,
      scope,
      true,
      1002.0,
    ),
    "nonselected.record",
  )
  |> ignore
  request_lookup_corrupt_row(settings, other, b"{}")
  let selected = host.lookup_submission_reference_by_request_id(
    crypto,
    "operator",
    "cli",
    @local_host.native_client_submission_request_id(reference),
    1003.0,
  )
  request_lookup_ok(host.close(), "host.close")
  let same = request_lookup_some(
    request_lookup_ok(selected, "selected"),
    "selected.reference",
  )
  assert_eq(
    @local_host.native_client_submission_reference_wire(same),
    @local_host.native_client_submission_reference_wire(reference),
  )
  // Whole-Journal integrity is the existing explicit inspection boundary;
  // the ordinary selected entrance does not scan unrelated request history.
  let library = request_lookup_ok(
    @local_sqlite.load_library(settings.sqlite_library),
    "audit.library",
  )
  assert_true(
    @local_host.inspect_native_client_state(
      library,
      settings.state_parent + "/host/client.sqlite3",
      131072L,
      16777216L,
      8,
    )
    is Err(Custody(Submission(@local_host.CustodyLost))),
  )
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
    request_lookup_ok(host.close(), "host.close")
    fail("public token shape")
  }
  let different = (if tag[0] == '0' { "1" } else { "0" }) + tag[1:].to_owned()
  token["authenticator"] = Json::string(different)
  fields["epoch"] = Json::object(token)
  let forged = request_lookup_ok(
    @local_host.admit_native_client_submission_reference(
      encode_request_json(Json::object(fields), 4096),
    ),
    "forged.reference",
  )
  let body = request_lookup_ok(
    @run_host.client_submitted_intent_journal_row_body(
      @local_host.native_client_submission_reference_wire(forged),
      intent,
    ),
    "forged.row",
  )
  request_lookup_corrupt_row(settings, reference, body)
  let selected = host.lookup_submission_reference_by_request_id(
    crypto,
    "operator",
    "cli",
    @local_host.native_client_submission_request_id(reference),
    1003.0,
  )
  request_lookup_ok(host.close(), "host.close")
  assert_true(selected is Err(@local_host.Epoch(@local_host.Unverifiable)))
}
