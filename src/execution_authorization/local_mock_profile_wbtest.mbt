///|
fn mock_profile_subjects() -> LocalMockAccountSubjects {
  {
    account_id: "mock-account",
    principal: "local-operator",
    control_connection: "local-host",
    sources: [("salesforce", "Account"), ("snowflake", "usage_30d")],
    model_tasks: ["sha256:" + "a".repeat(64)],
    request_target: Some(("local-host", "mock-realization")),
    update_target: Some(("salesforce", "Account")),
    signing_key_resource: Some("key:reviewer"),
  }
}

///|
test "Local Mock exact predecessor remains known without acquiring newer grants" {
  let original_body =
    #|{"control":{"operations":["read","resolve"],"resource":"run"},"effect":{"operations":["effect"],"outcome":"delegate"},"infer":{"connection":"mock","operations":["infer","model_raw_capture"]},"profile_id":"actql-local-mock","profile_version":"0.1","read":{"operations":["read"]},"request":{"operations":["write"],"resource":"original-host-mock-realization"},"scope":"selected-mock-project-installation","sign":{"operations":["sign"],"resource":"original-local-purpose-key"}}
  assert_eq(local_mock_profile_predecessor_body(), original_body)
  let previous = local_mock_profile_body_identity(original_body)
  assert_eq(
    previous.profile_cid,
    "sha256:fe8f88f3465a18456678bf9bf32943dcc4e4a8654b6d449f0c6af174fffd7e3a",
  )
  assert_true(is_known_local_mock_profile(previous))
  assert_true(is_known_local_mock_profile(local_mock_profile_identity()))
  assert_false(
    is_known_local_mock_profile({
      ..previous,
      profile_cid: "sha256:" + "f".repeat(64),
    }),
  )
  assert_false(
    is_known_local_mock_profile({ ..previous, profile_id: "foreign", }),
  )
  assert_false(
    is_known_local_mock_profile({ ..previous, profile_version: "0.2", }),
  )
  let saved_wire =
    #|{"account_id":"mock-account","bootstrap":{"profile_cid":"sha256:fe8f88f3465a18456678bf9bf32943dcc4e4a8654b6d449f0c6af174fffd7e3a","profile_id":"actql-local-mock","profile_version":"0.1"},"entries":[{"connection":{"any_of":["local-host"]},"entry_id":"local-request","exclusions":[],"operation":{"any_of":["write"]},"outcome":"allow","principal":{"any_of":["local-operator"]},"resource":{"any_of":["mock-realization"]}},{"connection":{"any_of":["local-host"]},"entry_id":"local-run","exclusions":[],"operation":{"any_of":["read","resolve"]},"outcome":"allow","principal":{"any_of":["local-operator"]},"resource":{"any_of":["run"]}},{"connection":{"any_of":["local-host"]},"entry_id":"local-sign","exclusions":[],"operation":{"any_of":["sign"]},"outcome":"allow","principal":{"any_of":["local-operator"]},"resource":{"any_of":["key:reviewer"]}},{"connection":{"any_of":["mock"]},"entry_id":"mock-infer-0","exclusions":[],"operation":{"any_of":["infer","model_raw_capture"]},"outcome":"allow","principal":{"any_of":["local-operator"]},"resource":{"any_of":["sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]}},{"connection":{"any_of":["salesforce"]},"entry_id":"mock-read-0","exclusions":[],"operation":{"any_of":["read"]},"outcome":"allow","principal":{"any_of":["local-operator"]},"resource":{"any_of":["Account"]}},{"connection":{"any_of":["snowflake"]},"entry_id":"mock-read-1","exclusions":[],"operation":{"any_of":["read"]},"outcome":"allow","principal":{"any_of":["local-operator"]},"resource":{"any_of":["usage_30d"]}},{"connection":{"any_of":["salesforce"]},"entry_id":"mock-update","exclusions":[],"operation":{"any_of":["effect"]},"outcome":"delegate","principal":{"any_of":["local-operator"]},"resource":{"any_of":["Account"]}}],"version":"actql-execution-account-config/0.1"}
  let saved = admit_account_configuration_json(saved_wire).unwrap()
  assert_eq(
    saved.configuration_cid(),
    "sha256:47fd6896d828109c3961e5183b1dfa1376aa1a1782fb454ca786601518d93f3a",
  )
  assert_eq(saved.bootstrap_profile(), Some(previous))
  assert_true(
    bind_bootstrap_adoption(saved, {
      record_id: "original-initialization",
      account_id: "mock-account",
      profile: previous,
    })
    is Ok(_),
  )
  for
    tuple in [
      mock_profile_at("local-host", "run", "submit"),
      mock_profile_at("local-host", "run", "publish"),
      mock_profile_at("local-host", "run", "cancel"),
      mock_profile_at("local-host", "result/answer", "read"),
    ] {
    assert_true(evaluate_account(saved, tuple) is Deny(NoMatch))
  }
  assert_true(
    evaluate_account(saved, mock_profile_at("local-host", "run", "read"))
    is Allow(_),
  )
  assert_eq(
    saved.configuration_cid(),
    "sha256:47fd6896d828109c3961e5183b1dfa1376aa1a1782fb454ca786601518d93f3a",
  )
}

///|
fn mock_profile_at(
  connection : String,
  resource : String,
  operation : String,
) -> AccessTuple {
  { principal: "local-operator", connection, resource, operation, }
}

///|
test "answer-only Mock originals remain known without acquiring main authority" {
  let previous = local_mock_profile_body_identity(
    local_mock_answer_profile_body(),
  )
  assert_eq(
    previous.profile_cid,
    "sha256:5d1edcd4312874f4621a96fa5d6a73b4015952cab8db0f6950a1622dcf0ab36f",
  )
  assert_true(is_known_local_mock_profile(previous))
  let fresh = decode_account_configuration_json(
    local_mock_account_configuration(mock_profile_subjects()).unwrap(),
  ).unwrap()
  let saved = admit_account_configuration({
    ..fresh,
    bootstrap: Some(previous),
    entries: fresh.entries.filter(entry => {
      entry.entry_id != "local-primary-result-read" &&
      entry.entry_id != "local-update-result-read"
    }),
  }).unwrap()
  // Independently retained full configuration identity, not a newer policy
  // body or a generated expected Account grant.
  assert_eq(
    saved.configuration_cid(),
    "sha256:31531ccc65ed73cdef89bc21ec83864d64f264de64894c11fad50c7170a94828",
  )
  assert_true(
    evaluate_account(
      saved,
      mock_profile_at("local-host", "result/answer", "read"),
    )
    is Allow(_),
  )
  assert_true(
    evaluate_account(
      saved,
      mock_profile_at("local-host", "result/main", "read"),
    )
    is Deny(NoMatch),
  )
}

///|
test "prior primary Mock original never acquires the UPDATE Result on recovery" {
  let previous = local_mock_profile_body_identity(
    local_mock_primary_profile_body(),
  )
  assert_eq(
    previous.profile_cid,
    "sha256:8d3a8a44d338852bdef34d4547dc8a9c22d91e9831dac20ee42f144de8793e01",
  )
  assert_true(is_known_local_mock_profile(previous))
  let fresh = decode_account_configuration_json(
    local_mock_account_configuration(mock_profile_subjects()).unwrap(),
  ).unwrap()
  let saved = admit_account_configuration({
    ..fresh,
    bootstrap: Some(previous),
    entries: fresh.entries.filter(entry => {
      entry.entry_id != "local-update-result-read"
    }),
  }).unwrap()
  assert_eq(
    saved.configuration_cid(),
    "sha256:82722eed1a6b4cfb1a33f06b3345246076cf6802483c97eab250f5febb8826e8",
  )
  assert_true(
    evaluate_account(
      saved,
      mock_profile_at("local-host", "result/main", "read"),
    )
    is Allow(_),
  )
  assert_true(
    evaluate_account(
      saved,
      mock_profile_at("local-host", "result/updates", "read"),
    )
    is Deny(NoMatch),
  )
}

///|
test "Mock UPDATE Result scope requires the selected UPDATE recipe" {
  let subjects = mock_profile_subjects()
  let read_only = admit_account_configuration_json(
    local_mock_account_configuration({ ..subjects, update_target: None, }).unwrap(),
  ).unwrap()
  assert_true(
    evaluate_account(
      read_only,
      mock_profile_at("local-host", "result/updates", "read"),
    )
    is Deny(NoMatch),
  )
  let update = admit_account_configuration_json(
    local_mock_account_configuration(subjects).unwrap(),
  ).unwrap()
  assert_true(
    evaluate_account(
      update,
      mock_profile_at("local-host", "result/updates", "read"),
    )
    is Allow(_),
  )
  for
    tuple in [
      mock_profile_at("local-host", "result/other", "read"),
      mock_profile_at("local-host", "result/updates", "write"),
      mock_profile_at("foreign", "result/updates", "read"),
    ] {
    assert_true(evaluate_account(update, tuple) is Deny(NoMatch))
  }
}

///|
test "Local Mock profile and concrete configuration match independent canonical preimages" {
  // Independently authored profile/configuration objects and canonical SHA256,
  // not expectations regenerated from this implementation's emitted bytes.
  let profile = local_mock_profile_identity()
  assert_eq(profile.profile_id, "actql-local-mock")
  assert_eq(profile.profile_version, "0.1")
  assert_eq(
    profile.profile_cid,
    "sha256:0423a05cccb8d7329cc130247130f2081bb8f54e42ae579e99166da30c21de52",
  )
  let wire = local_mock_account_configuration(mock_profile_subjects()).unwrap()
  let admitted = admit_account_configuration_json(wire).unwrap()
  assert_eq(
    admitted.configuration_cid(),
    "sha256:d516378d5284e53e3c9667e62a11ffd020b477111920fa0405d93f73695f2907",
  )
  assert_eq(admitted.bootstrap_profile(), Some(profile))
  assert_true(
    bind_bootstrap_adoption(admitted, {
      record_id: "original-initialization",
      account_id: "mock-account",
      profile,
    })
    is Ok(_),
  )
  assert_true(
    bind_bootstrap_adoption(admitted, {
      record_id: "original-initialization",
      account_id: "other-account",
      profile,
    })
    is Err(AccountMismatch),
  )
}

///|
test "Local Mock reads inference request and key scopes remain finite and UPDATE delegates" {
  let config = admit_account_configuration_json(
    local_mock_account_configuration(mock_profile_subjects()).unwrap(),
  ).unwrap()
  for
    tuple in [
      mock_profile_at("salesforce", "Account", "read"),
      mock_profile_at("snowflake", "usage_30d", "read"),
      mock_profile_at("mock", "sha256:" + "a".repeat(64), "infer"),
      mock_profile_at("mock", "sha256:" + "a".repeat(64), "model_raw_capture"),
      mock_profile_at("local-host", "mock-realization", "write"),
      mock_profile_at("local-host", "run", "read"),
      mock_profile_at("local-host", "run", "resolve"),
      mock_profile_at("local-host", "run", "submit"),
      mock_profile_at("local-host", "run", "publish"),
      mock_profile_at("local-host", "run", "cancel"),
      mock_profile_at("local-host", "result/answer", "read"),
      mock_profile_at("local-host", "result/main", "read"),
      mock_profile_at("local-host", "result/updates", "read"),
      mock_profile_at("local-host", "key:reviewer", "sign"),
    ] {
    assert_true(evaluate_account(config, tuple) is Allow(_))
  }
  let update = mock_profile_at("salesforce", "Account", "effect")
  let outcome = evaluate_account(config, update)
  assert_true(outcome is Delegate(_))
  assert_eq(runtime_action_for(outcome), None)
  assert_true(
    bind_dispatch_authorization(
      config,
      update,
      EffectCommit,
      "sha256:" + "b".repeat(64),
      "sha256:" + "c".repeat(64),
    )
    is Err(UnresolvedDelegation),
  )
  for
    tuple in [
      mock_profile_at("salesforce", "Account", "write"),
      mock_profile_at("salesforce", "Contact", "read"),
      mock_profile_at("snowflake", "other_table", "read"),
      mock_profile_at("live", "sha256:" + "a".repeat(64), "infer"),
      mock_profile_at("mock", "sha256:" + "b".repeat(64), "infer"),
      mock_profile_at("local-host", "live-realization", "write"),
      mock_profile_at("local-host", "other-key", "sign"),
      mock_profile_at("local-host", "result/other", "read"),
      mock_profile_at("local-host", "result/answer", "write"),
      mock_profile_at("local-host", "result/main", "write"),
      mock_profile_at("foreign-host", "run", "submit"),
      mock_profile_at("foreign-host", "result/answer", "read"),
      mock_profile_at("foreign-host", "result/main", "read"),
      mock_profile_at("local-host", "answer", "read"),
      mock_profile_at("credential", "issuer", "issue"),
      { ..update, principal: "other-operator", },
    ] {
    assert_true(evaluate_account(config, tuple) is Deny(NoMatch))
  }
}

///|
test "Local Mock control and default Result preserve current restriction and original Account binding" {
  let original = decode_account_configuration_json(
    local_mock_account_configuration(mock_profile_subjects()).unwrap(),
  ).unwrap()
  let before = admit_account_configuration(original).unwrap()
  let restricted = admit_account_configuration({
    ..original,
    entries: original.entries.map(entry => {
      if entry.entry_id == "local-run" ||
        entry.entry_id == "local-result-read" ||
        entry.entry_id == "local-primary-result-read" {
        { ..entry, outcome: Deny, }
      } else {
        entry
      }
    }),
  }).unwrap()
  for
    tuple in [
      mock_profile_at("local-host", "run", "submit"),
      mock_profile_at("local-host", "run", "publish"),
      mock_profile_at("local-host", "run", "cancel"),
      mock_profile_at("local-host", "result/answer", "read"),
      mock_profile_at("local-host", "result/main", "read"),
    ] {
    assert_true(evaluate_account(before, tuple) is Allow(_))
    assert_true(evaluate_account(restricted, tuple) is Deny(Explicit(_)))
    assert_true(
      evaluate_account_state(Missing, tuple) is Deny(ConfigurationMissing),
    )
    let admitted = bind_dispatch_authorization(
      before,
      tuple,
      Acquisition,
      "sha256:" + "b".repeat(64),
      "sha256:" + "c".repeat(64),
    ).unwrap()
    assert_false(
      dispatch_authorization_matches(
        admitted,
        restricted,
        tuple,
        Acquisition,
        "sha256:" + "b".repeat(64),
        "sha256:" + "c".repeat(64),
      ),
    )
    assert_false(
      dispatch_authorization_matches(
        admitted,
        before,
        tuple,
        Acquisition,
        "sha256:" + "d".repeat(64),
        "sha256:" + "c".repeat(64),
      ),
    )
    assert_true(
      evaluate_account(before, { ..tuple, principal: "other-operator", })
      is Deny(NoMatch),
    )
  }
}

///|
test "Local Mock missing signer does not grant signing or block permitted reads" {
  let subjects = { ..mock_profile_subjects(), signing_key_resource: None, }
  let config = admit_account_configuration_json(
    local_mock_account_configuration(subjects).unwrap(),
  ).unwrap()
  assert_true(
    evaluate_account(config, mock_profile_at("salesforce", "Account", "read"))
    is Allow(_),
  )
  assert_true(
    evaluate_account(
      config,
      mock_profile_at("local-host", "key:reviewer", "sign"),
    )
    is Deny(NoMatch),
  )
  assert_true(
    evaluate_account_state(
      Missing,
      mock_profile_at("salesforce", "Account", "read"),
    )
    is Deny(ConfigurationMissing),
  )
}

///|
test "Local Mock provenance does not override a current operator restriction" {
  let original = decode_account_configuration_json(
    local_mock_account_configuration(mock_profile_subjects()).unwrap(),
  ).unwrap()
  let before = admit_account_configuration(original).unwrap()
  let entries = original.entries.map(entry => {
    if entry.entry_id == "mock-read-0" {
      { ..entry, outcome: Deny, }
    } else {
      entry
    }
  })
  let current = admit_account_configuration({ ..original, entries, }).unwrap()
  let tuple = mock_profile_at("salesforce", "Account", "read")
  assert_true(evaluate_account(before, tuple) is Allow(_))
  assert_true(evaluate_account(current, tuple) is Deny(Explicit("mock-read-0")))
  assert_eq(current.bootstrap_profile(), before.bootstrap_profile())
  assert_true(current.configuration_cid() != before.configuration_cid())
  let admitted = bind_dispatch_authorization(
    before,
    tuple,
    Acquisition,
    "sha256:" + "b".repeat(64),
    "sha256:" + "c".repeat(64),
  ).unwrap()
  assert_false(
    dispatch_authorization_matches(
      admitted,
      current,
      tuple,
      Acquisition,
      "sha256:" + "b".repeat(64),
      "sha256:" + "c".repeat(64),
    ),
  )
}

///|
test "Local Mock profile refuses malformed repeated unselected and excessive subjects" {
  let original = mock_profile_subjects()
  for
    subjects in [
      { ..original, principal: "", },
      {
        ..original,
        sources: [("salesforce", "Account"), ("salesforce", "Account")],
      },
      {
        ..original,
        model_tasks: ["sha256:" + "a".repeat(64), "sha256:" + "a".repeat(64)],
      },
      { ..original, model_tasks: ["not-a-task-cid"], },
      { ..original, model_tasks: Array::make(65, "sha256:" + "a".repeat(64)), },
      { ..original, sources: Array::make(129, ("source", "resource")), },
      { ..original, update_target: Some(("salesforce", "Contact")), },
      { ..original, signing_key_resource: Some(""), },
      { ..original, request_target: Some(("salesforce", "Account")), },
    ] {
    assert_true(
      local_mock_account_configuration(subjects) is Err(InvalidSubjects),
    )
  }
}

///|
test "Mock Source Account uses its original connection and resource apart from Run control" {
  let account = admit_account_configuration_json(
    local_mock_account_configuration(mock_profile_subjects()).unwrap(),
  ).unwrap()
  assert_true(
    evaluate_account(account, mock_profile_at("local-host", "run", "submit"))
    is Allow(_),
  )
  assert_true(
    evaluate_account(account, mock_profile_at("salesforce", "Account", "read"))
    is Allow(_),
  )
  // A SourceRef identifies a compiler port, not the actual configured Account
  // resource. Neither the control connection nor an Effect delegate grants it.
  assert_true(
    evaluate_account(
      account,
      mock_profile_at(
        "local-host", "connector://salesforce/Account#records", "read",
      ),
    )
    is Deny(NoMatch),
  )
  assert_true(
    evaluate_account(
      account,
      mock_profile_at(
        "salesforce", "connector://salesforce/Account#records", "read",
      ),
    )
    is Deny(NoMatch),
  )
  assert_true(
    evaluate_account(account, mock_profile_at("local-host", "Account", "read"))
    is Deny(NoMatch),
  )
  assert_true(
    evaluate_account(
      account,
      mock_profile_at("salesforce", "Account", "effect"),
    )
    is Delegate(_),
  )
  assert_true(
    evaluate_account(account, mock_profile_at("salesforce", "Account", "write"))
    is Deny(NoMatch),
  )
}
