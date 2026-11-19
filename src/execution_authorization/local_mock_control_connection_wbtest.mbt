///|
test "Mock control selection preserves Sources and separates arbitrary original Result names" {
  let sources = [
    ("local-mock", "Account"),
    ("actql-local-control-0", "Other"),
    ("actql-local-control-1", "Target"),
  ]
  let chosen = local_mock_control_connection_prepared(
      "local-mock",
      None,
      None,
      sources,
      [("actql-local-control-1", "Target")],
      _ => true,
    )
    .unwrap()
    .unwrap()
  assert_eq(chosen, "actql-local-control-2")
  assert_eq(sources[0], ("local-mock", "Account"))
  let subjects = {
    ..mock_profile_subjects(),
    control_connection: chosen,
    sources,
    model_tasks: [],
    update_target: None,
    request_target: Some((chosen, "mock-realization")),
  }
  let account = admit_account_configuration_json(
    local_mock_account_configuration(subjects).unwrap(),
  ).unwrap()
  for name in ["file", "anything", "main", "answer", "updates", "補助"] {
    assert_true(
      evaluate_account(
        account,
        mock_profile_at(chosen, "result/" + name, "read"),
      )
      is Allow(_),
    )
    assert_true(
      evaluate_account(
        account,
        mock_profile_at(chosen, "result/" + name, "write"),
      )
      is Deny(NoMatch),
    )
    assert_true(
      evaluate_account(
        account,
        mock_profile_at("local-mock", "result/" + name, "read"),
      )
      is Deny(NoMatch),
    )
  }
  assert_true(
    evaluate_account(account, mock_profile_at("local-mock", "Account", "read"))
    is Allow(_),
  )
  assert_true(
    evaluate_account(account, mock_profile_at("local-mock", "Other", "read"))
    is Deny(NoMatch),
  )
  assert_true(
    evaluate_account(account, mock_profile_at("mock", "file", "read"))
    is Deny(NoMatch),
  )
  assert_true(
    evaluate_account(account, mock_profile_at(chosen, "Account", "infer"))
    is Deny(NoMatch),
  )
}

///|
test "Mock new policy refuses colliding control domains and retains exact operator restriction" {
  let original = mock_profile_subjects()
  for control in ["salesforce", "mock"] {
    assert_true(
      local_mock_account_configuration({
        ..original,
        control_connection: control,
      })
      is Err(InvalidSubjects),
    )
  }
  let selected = local_mock_control_connection_prepared(
      "mock",
      None,
      None,
      [],
      [],
      _ => true,
    )
    .unwrap()
    .unwrap()
  assert_eq(selected, "actql-local-control-0")
  let config = decode_account_configuration_json(
    local_mock_account_configuration(original).unwrap(),
  ).unwrap()
  let restricted = admit_account_configuration({
    ..config,
    entries: config.entries.map(entry => {
      if entry.entry_id == "local-result-read" || entry.entry_id == "local-run" {
        { ..entry, outcome: Deny, }
      } else {
        entry
      }
    }),
  }).unwrap()
  assert_true(
    evaluate_account(
      restricted,
      mock_profile_at("local-host", "result/file", "read"),
    )
    is Deny(Explicit(_)),
  )
  assert_true(
    evaluate_account(restricted, {
      ..mock_profile_at("local-host", "result/file", "read"),
      principal: "other",
    })
    is Deny(NoMatch),
  )
}

///|
test "Mock retained control interpretation belongs to the original Common profile" {
  let current = local_mock_profile_identity()
  assert_eq(
    local_mock_control_connection_prepared(
      "local-mock",
      Some(current),
      Some("local-mock"),
      [],
      [],
      _ => true,
    ),
    Some(Ok("local-mock")),
  )
  assert_true(
    local_mock_control_connection_prepared(
      "local-mock",
      Some(current),
      None,
      [],
      [],
      _ => true,
    ).unwrap()
    is Err(InvalidSubjects),
  )
  assert_true(
    local_mock_control_connection_prepared(
      "local-mock",
      Some(current),
      Some("local-mock"),
      [("local-mock", "new-source")],
      [],
      _ => true,
    ).unwrap()
    is Err(InvalidSubjects),
  )
  let previous = local_mock_profile_body_identity(
    local_mock_updates_profile_body(),
  )
  assert_eq(
    previous.profile_cid,
    "sha256:0423a05cccb8d7329cc130247130f2081bb8f54e42ae579e99166da30c21de52",
  )
  // A legal legacy shared Source/control domain keeps its finite saved rules.
  assert_eq(
    local_mock_control_connection_prepared(
      "local-mock",
      Some(previous),
      None,
      [("local-mock", "source")],
      [],
      _ => true,
    ),
    Some(Ok("local-mock")),
  )
  assert_true(
    local_mock_control_connection_prepared(
      "local-mock",
      Some(previous),
      Some("replacement"),
      [],
      [],
      _ => true,
    ).unwrap()
    is Err(InvalidSubjects),
  )
  assert_true(
    local_mock_control_connection_prepared(
      "local-mock",
      Some({ ..current, profile_cid: "sha256:" + "f".repeat(64), }),
      None,
      [],
      [],
      _ => true,
    ).unwrap()
    is Err(InvalidSubjects),
  )
}

///|
test "Mock control index and String construction are admitted before allocation with exact boundaries" {
  let sources = [("local-mock", "x"), ("actql-local-control-0", "y")]
  let geometry = local_mock_control_construction("local-mock", sources, []).unwrap()
  // Three growing borrowed-key entries: Map7H18R21W +3*(4H11R13W),
  // plus the explicit normalizer and bounded String/control workspace.
  let nfc = @canonical.nfc_lf_construction_extent(10).unwrap()
  assert_eq(geometry.retained, account_construction_units(3L, 2L, 2L, 30L))
  assert_eq(
    geometry.execution,
    account_construction_units(
      25L + nfc.record_headers,
      55L + nfc.reference_slots,
      64L + nfc.scalar_words,
      40L + nfc.owned_utf16_units,
    ),
  )
  let calls = Ref(0)
  assert_true(
    local_mock_control_connection_prepared(
      "local-mock",
      None,
      None,
      sources,
      [],
      request => {
        calls.val += 1
        request.retained == geometry.retained &&
        request.execution == geometry.execution
      },
    ).unwrap()
    is Ok("actql-local-control-1"),
  )
  assert_eq(calls.val, 1)
  for
    short in [
      account_construction_units(2L, 2L, 2L, 30L),
      account_construction_units(3L, 2L, 2L, 29L),
    ] {
    assert_true(
      local_mock_control_connection_prepared(
        "local-mock",
        None,
        None,
        sources,
        [],
        request => request.retained == short,
      )
      is None,
    )
  }
}
