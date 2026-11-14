///|
test "retained initial packet DATA reauthenticates the current epoch key and preserves its primary fence" {
  let host = initial_signing_original_fixture("control-data-current-mac")
  let original = host.restore_initial_signing_original().unwrap()
  let header = local_initial_signing_control_header(original.control_body).unwrap()
  let packet = @base64.decode(header[1])
  let (payload, tag) = local_installation_packet_data(packet).unwrap()
  authenticate_local_installation_payload(host, payload, tag).unwrap()
  let changed = Bytes::makei(tag.length(), index => {
    if index == 0 {
      tag[index] ^ 1
    } else {
      tag[index]
    }
  })
  assert_true(
    authenticate_local_installation_payload(host, payload, changed)
    is Err(CustodyLost),
  )
  let (key, clock, revision) = read_epoch_custody(host.database).unwrap()
  let changed_key = Bytes::makei(key.length(), index => {
    if index == 0 {
      key[index] ^ 1
    } else {
      key[index]
    }
  })
  host.database.begin_immediate().unwrap()
  host.database
  .compare_exchange(
    "client_submission_epoch",
    "authority",
    revision,
    epoch_custody_body(changed_key, clock).unwrap(),
  )
  .unwrap()
  |> ignore
  host.database.commit().unwrap()
  assert_true(
    authenticate_local_installation_payload(host, payload, tag)
    is Err(CustodyLost),
  )
  host.close().unwrap()
  assert_true(
    authenticate_local_installation_payload(host, payload, tag)
    is Err(Epoch(Physical(@sqlite.DatabaseClosed))),
  )
  assert_true(
    read_local_installation_authenticated_payload(host, packet)
    is Err(Epoch(Physical(@sqlite.DatabaseClosed))),
  )
}

///|
test "retained control DATA keeps private public-key copies and full foreign and role admission" {
  let host = initial_signing_original_fixture("control-data-role-owner")
  let foreign = initial_signing_original_fixture("control-data-role-foreign")
  let original = host.restore_initial_signing_original().unwrap()
  let (reviewer, host_fields) = read_local_initial_signing_control_with_host_key(
      host,
      original.control_body,
    )
    .unwrap()
    .unwrap()
  let data = retain_initial_signing_control_data(
    host,
    original.control_body,
    reviewer,
    host_fields,
  ).unwrap()
  assert_true(physical_equal(data.body, original.control_body))
  let expected = data.reviewer.public_key.raw32().unwrap()
  let returned = original.public_key().unwrap().raw32().unwrap()
  let altered = Bytes::makei(returned.length(), index => {
    if index == 0 {
      returned[index] ^ 1
    } else {
      returned[index]
    }
  })
  assert_false(physical_equal(returned, expected))
  assert_false(data.reviewer.public_key.raw32().unwrap() == altered)
  assert_eq(data.reviewer.public_key.raw32().unwrap(), expected)
  let header = local_initial_signing_control_header(original.control_body).unwrap()
  let swapped = local_adoption_record([
    ("adoption_body", header[0]),
    ("initial_signing_original", header[2]),
    ("initial_host_attestation_original", header[1]),
  ]).unwrap()
  assert_true(
    read_local_initial_signing_control_with_host_key(host, swapped)
    is Err(CustodyLost),
  )
  assert_true(
    read_local_initial_signing_control_with_host_key(
      foreign,
      original.control_body,
    )
    is Err(CustodyLost),
  )
  assert_true(original.control_data is None)
  original.require_current().unwrap()
  foreign.close().unwrap()
  host.close().unwrap()
}

///|
test "initial signing public projection keeps exact role PEM and original public32 correspondence" {
  let host = initial_signing_original_fixture("signing-projection-original")
  let original = host.restore_initial_signing_original().unwrap()
  let independent = host.restore_initial_host_signing_original().unwrap()
  // Pure public DATA correspondence only. The entered-Read route has a
  // separate actual-pair consumer; this fixture invents no Read or Allow.
  assert_eq(
    original
    .decoded_initial_signing_public_key(
      "reviewer_proof",
      "local-signing-key.pem",
      original.public_key_pem,
      original.public_key,
    )
    .unwrap(),
    original.public_key.raw32().unwrap(),
  )
  assert_eq(
    original
    .decoded_initial_signing_public_key(
      "host_attestation",
      "local-host-attestation-key.pem",
      independent.public_key_pem,
      independent.public_key,
    )
    .unwrap(),
    independent.public_key.raw32().unwrap(),
  )
  assert_true(
    original.decoded_initial_signing_public_key(
      "host_attestation",
      "local-signing-key.pem",
      independent.public_key_pem,
      independent.public_key,
    )
    is Err(CustodyLost),
  )
  assert_true(
    original.decoded_initial_signing_public_key(
      "reviewer_proof",
      "local-signing-key.pem",
      original.public_key_pem,
      independent.public_key,
    )
    is Err(CustodyLost),
  )
  assert_true(
    original.decoded_initial_signing_public_key(
      "reviewer_proof",
      "local-signing-key.pem",
      original.public_key_pem + "\n",
      original.public_key,
    )
    is Err(CustodyLost),
  )
  host.close().unwrap()
}

///|
test "initial signing public projection refuses missing and foreign original Host key pairs" {
  let host = initial_signing_original_fixture("signing-projection-owner")
  let foreign = initial_signing_original_fixture("signing-projection-foreign")
  let original = host.restore_initial_signing_original().unwrap()
  let other = foreign.restore_initial_host_signing_original().unwrap()
  assert_true(
    original.decoded_initial_signing_public_key(
      "host_attestation",
      "local-host-attestation-key.pem",
      other.public_key_pem,
      other.public_key,
    )
    is Err(CustodyLost),
  )
  let absent = { ..original, host_public_key: None, }
  let actual = host.restore_initial_host_signing_original().unwrap()
  assert_true(
    absent.decoded_initial_signing_public_key(
      "host_attestation",
      "local-host-attestation-key.pem",
      actual.public_key_pem,
      actual.public_key,
    )
    is Err(CustodyLost),
  )
  foreign.close().unwrap()
  host.close().unwrap()
}

///|
test "initial signing cannot turn copied callback metadata into an original Read or cached Allow" {
  let (host, _) = initial_reviewer_fixture("signing-read-no-fabricated-scope")
  let original = host.restore_initial_signing_original().unwrap()
  let material = host.adopted_current_material().unwrap()
  let library = local_journal_test_library()
  let capture = prepare_native_local_journal_capture(
    host.session,
    library,
    host.epoch.crypto,
    100.0,
    8,
    8388608L,
  )
  // Negative-only copied metadata. This fixture has NO original Arena pair;
  // the positive actual Read/SQL case belongs to native_client's real owner.
  capture.opening = JournalAcquired(host)
  capture.read_callback_active = true
  capture.read_facts_valid = true
  capture.read_material = Some(material)
  let scoped = { ..original, original_read: Some((capture, material)), }
  let tuple : @authorization.AccessTuple = {
    principal: "machine-user",
    connection: "cli",
    resource: "run",
    operation: "resolve",
  }
  let actual_allow = host.authorize(tuple).unwrap()
  assert_true(actual_allow is @authorization.Allow(_))
  capture.read_decisions.push((tuple, actual_allow))
  assert_true(scoped.require_current() is Err(OriginalResourceScopePending))
  assert_true(scoped.authorize(tuple) is Err(OriginalResourceScopePending))
  assert_true(
    scoped.selected_configuration("host.json")
    is Err(OriginalResourceScopePending),
  )
  // Refusal of the invented route does not destroy the genuine legacy owner.
  original.require_current().unwrap()
  capture.read_callback_active = false
  capture.read_facts_valid = false
  capture.clear_read_operation_facts()
  host.close().unwrap()
  assert_true(library.close_checked() is Err(Physical(_)))
}

///|
test "initial signing retains the first invalidation and rejects a different equal material identity" {
  let (host, _) = initial_reviewer_fixture("signing-read-retired-material")
  let original = host.restore_initial_signing_original().unwrap()
  let first = host.adopted_current_material().unwrap()
  let second = host.adopted_current_material().unwrap()
  assert_false(physical_equal(first, second))
  let library = local_journal_test_library()
  let capture = prepare_native_local_journal_capture(
    host.session,
    library,
    host.epoch.crypto,
    100.0,
    8,
    8388608L,
  )
  capture.opening = JournalAcquired(host)
  capture.read_callback_active = true
  capture.read_facts_valid = true
  capture.read_material = Some(second)
  let scoped = { ..original, original_read: Some((capture, first)), }
  assert_true(scoped.require_current() is Err(OriginalResourceScopePending))
  capture.read_operation_issue = Some(SourceChanged)
  assert_true(scoped.require_current() is Err(SourceChanged))
  assert_true(scoped.selected_configuration("host.json") is Err(SourceChanged))
  assert_true(scoped.check_callback_current() is Err(SourceChanged))
  capture.read_callback_active = false
  capture.read_facts_valid = false
  capture.clear_read_operation_facts()
  // Cleanup remains with the actual original even after currentness failed.
  host.close().unwrap()
  assert_true(library.close_checked() is Err(Physical(_)))
}
