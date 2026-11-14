///|
// Physical key/custody components only. The diagnostic sign proves the fresh
// private/public pair, not Host Account authority, a credential claim, actual
// attestation preimage, Checkpoint approval, CLI or normal installed funding.
test "fresh original initialization retains distinct real Reviewer and Host keys in one control" {
  let host = initial_signing_original_fixture("initial-host-distinct")
  let reviewer = host.restore_initial_signing_original().unwrap()
  let original = host.restore_initial_host_signing_original().unwrap()
  let raw = original.public_key().unwrap().raw32().unwrap()
  assert_true(raw != reviewer.public_key().unwrap().raw32().unwrap())
  assert_true(
    original.exported[26:42].to_owned() != reviewer.exported[26:42].to_owned(),
  )
  assert_eq(
    original.issuer_identity().unwrap(),
    reviewer.issuer_identity().unwrap(),
  )
  assert_eq(original.policy().unwrap().cid(), reviewer.policy().unwrap().cid())
  let control = host.database
    .read("client_local_installation_custody", "host")
    .unwrap()
  assert_true(control.body.length() <= 8192)
  assert_eq(
    local_initial_signing_control_header(control.body).unwrap().length(),
    3,
  )
  let payload = b"initial Host key correspondence only"
  let attempt = host.epoch.crypto
    .prepare_original_key_signing_attempt(original.projection, raw, payload)
    .unwrap()
  let signature = attempt.sign_once().unwrap()
  assert_true(
    host.epoch.crypto
    .verify_ed25519(original.public_key_pem, payload, signature)
    .unwrap(),
  )
  assert_false(
    host.epoch.crypto
    .verify_ed25519(reviewer.public_key_pem, payload, signature)
    .unwrap(),
  )
  assert_true(attempt.sign_once() is Err(@crypto.Signing(_)))
  attempt.close_checked().unwrap()
  assert_true(
    host.database.scan_after("client_local_grant_originals", "")
    is Err(@sqlite.NotFound),
  )
  assert_eq(host.installation_custody().unwrap(), (0, 0L))
  host.close().unwrap()
  assert_true(original.require_current() is Err(Closed))
}

///|
test "same-process Host key restore preserves exact control and refuses a replaced original generation" {
  let name = "initial-host-reopen"
  let host = initial_signing_original_fixture(name)
  let original = host.restore_initial_host_signing_original().unwrap()
  let cid = original.public_key().unwrap().cid()
  let control = host.database
    .read("client_local_installation_custody", "host")
    .unwrap().body
  let epoch = host.database
    .read("client_submission_epoch", "authority")
    .unwrap().body
  let generation = host.session.root
    .inspect_generation("local-host-attestation-key.pem")
    .unwrap()
    .unwrap()
  let path = host.session.state_path
  let parent = path[:path.length() - ("/" + name + ".host").length()].to_owned()
  let source = host.session.source_name
  let crypto = host.epoch.crypto
  host.close().unwrap()
  let session = begin_native_local_host_adoption(
    parent,
    name + ".host",
    parent,
    source,
    "operator",
    crypto,
    existing_only=true,
  ).unwrap()
  assert_true(session.create_initial_signing_material(crypto) is Err(_))
  let restored = session
    .open_journal(local_journal_test_library(), crypto, 100.0, 8, 8388608L)
    .unwrap()
  let actual = restored.restore_initial_host_signing_original().unwrap()
  assert_eq(actual.public_key().unwrap().cid(), cid)
  assert_eq(
    restored.database.read("client_local_installation_custody", "host").unwrap().body,
    control,
  )
  assert_eq(
    restored.database.read("client_submission_epoch", "authority").unwrap().body,
    epoch,
  )
  assert_eq(
    restored.session.root
    .inspect_generation("local-host-attestation-key.pem")
    .unwrap(),
    Some(generation),
  )
  let (body, _) = local_adoption_read(
    restored.session.root,
    "local-host-attestation-key.pem",
    119L,
  ).unwrap()
  restored.session.root
  .reclaim_generation("local-host-attestation-key.pem", generation)
  .unwrap()
  let writer = restored.session.root
    .create_writer("host-key-replacement.stage", 119L)
    .unwrap()
  writer.append(body).unwrap()
  writer.seal("local-host-attestation-key.pem").unwrap() |> ignore
  assert_true(actual.require_current() is Err(_))
  assert_true(restored.restore_initial_host_signing_original() is Err(_))
  restored.close().unwrap()
}

///|
test "Reviewer-only legacy and altered Host role cannot reconstruct an initial Host original" {
  let host = initial_signing_original_fixture("initial-host-legacy")
  let control = host.database
    .read("client_local_installation_custody", "host")
    .unwrap()
  let header = local_initial_signing_control_header(control.body).unwrap()
  let legacy = local_adoption_record([
    ("adoption_body", header[0]),
    ("initial_signing_original", header[1]),
  ]).unwrap()
  host.journal
  .transaction(() => {
    host.database
    .remove_exact(
      "client_local_installation_custody",
      "host",
      control.revision,
      control.body,
    )
    .map_err(issue => NativeClientRunJournalIssue::Physical(issue))
    .bind(_ => {
      host.database
      .insert("client_local_installation_custody", "host", legacy)
      .map(_ => ())
      .map_err(issue => NativeClientRunJournalIssue::Physical(issue))
    })
  })
  .unwrap()
  assert_true(
    host.session.root
    .inspect_generation("local-host-attestation-key.pem")
    .unwrap()
    is Some(_),
  )
  assert_true(host.restore_initial_signing_original() is Ok(_))
  assert_true(host.restore_initial_host_signing_original() is Err(CustodyLost))
  assert_eq(
    host.database.read("client_local_installation_custody", "host").unwrap().body,
    legacy,
  )
  let packet = @base64.decode(header[2])
  let payload = read_local_installation_authenticated_payload(host, packet).unwrap()
  let fields = @host.read_client_local_initial_signing_payload(payload).unwrap()
  for
    changed in [
      { ..fields, purpose: "reviewer_proof", },
      { ..fields, key_file: "local-signing-key.pem", },
      { ..fields, initialization_intent_cid: "sha256:" + "f".repeat(64), },
    ] {
    let wrong_payload = @host.client_local_initial_signing_payload_body(changed).unwrap()
    let signed = host.journal
      .transaction(() => {
        local_installation_packet(host, wrong_payload).map_err(_ => CustodyLost)
      })
      .unwrap()
    let wrong = local_adoption_record([
      ("adoption_body", header[0]),
      ("initial_signing_original", header[1]),
      ("initial_host_attestation_original", @base64.encode(signed)),
    ]).unwrap()
    assert_true(
      read_local_initial_signing_control(host, wrong) is Err(CustodyLost),
    )
  }
  host.close().unwrap()
}

///|
test "preexisting partial initial key blocks both role generations and cold repair" {
  let (path, account, session, crypto) = initial_signing_fixture(
    "initial-host-partial",
  )
  // Existing private phase helper creates real partial evidence, not a public
  // replacement-generation port. No adopted material or key authority escapes.
  let partial = session
    .create_initial_signing_file(crypto, "local-signing-key.pem")
    .unwrap()
  let failure = match session.create_initial_signing_material(crypto) {
    Err(value) => value
    Ok(_) => fail("partial initialization generated another role")
  }
  assert_true(failure.issue() is CustodyLost)
  failure.retry_cleanup().unwrap()
  assert_eq(
    session.root.inspect_generation("local-signing-key.pem").unwrap(),
    Some(partial.generation),
  )
  assert_eq(
    session.root.inspect_generation("local-host-attestation-key.pem").unwrap(),
    None,
  )
  assert_true(session.close())
  let restored = begin_native_local_host_adoption(
    path, "initial-host-partial.host", path, account, "operator", crypto,
  ).unwrap()
  assert_true(restored.create_initial_signing_material(crypto) is Err(_))
  assert_eq(
    restored.root.inspect_generation("local-signing-key.pem").unwrap(),
    Some(partial.generation),
  )
  assert_eq(
    restored.root.inspect_generation("local-host-attestation-key.pem").unwrap(),
    None,
  )
  assert_true(restored.close())
}

///|
test "same-call Host control admission reads each authenticated role packet once" {
  let host = initial_signing_original_fixture("initial-host-control-reads")
  let original = host.restore_initial_host_signing_original().unwrap()
  let control = host.database
    .read("client_local_installation_custody", "host")
    .unwrap().body
  assert_eq(local_initial_signing_control_header(control).unwrap().length(), 3)
  for _ in 0..<2 {
    let before = native_timing_counter_value(1)
    assert_true(before >= 0L)
    let fields = read_local_initial_host_signing_control(host, control).unwrap()
    // Each authenticated packet retains two epoch scans and its exact record
    // read. The original Database reuses the statement for record reads, so
    // only the two scans prepare SQL again. This does not count HMAC calls.
    assert_eq(native_timing_counter_value(1) - before, 4L)
    assert_eq(fields.public_key.cid(), original.public_key.cid())
    assert_eq(fields.exported, original.exported)
  }
  host.close().unwrap()
}

///|
test "same-call Host subject admission retains the third authenticated packet" {
  let subject = ("host-machine", "host-cli", "key/initial-host-attestation")
  let (host, _) = initial_reviewer_fixture(
    "initial-host-subject-control-reads",
    account=installed_host_subject_account,
    host_signing_subject=Some(subject),
  )
  let original = host.restore_initial_host_signing_original().unwrap()
  let control = host.database
    .read("client_local_installation_custody", "host")
    .unwrap().body
  assert_eq(local_initial_signing_control_header(control).unwrap().length(), 4)
  for _ in 0..<2 {
    let before = native_timing_counter_value(1)
    assert_true(before >= 0L)
    let (fields, actual_subject) = read_local_initial_host_signing_control_with_subject(
      host, control,
    ).unwrap()
    // Reviewer, Host and subject each prepare two epoch scans while their
    // exact record reads reuse the original Database statement.
    // Repeating this invocation proves that no result is cached across calls.
    assert_eq(native_timing_counter_value(1) - before, 6L)
    assert_eq(actual_subject, Some(subject))
    assert_eq(fields.public_key.cid(), original.public_key.cid())
    assert_eq(fields.exported, original.exported)
  }
  host.close().unwrap()
}
