///|
fn profile_inventory_task(index : Int) -> String {
  let suffix = index.to_string()
  "sha256:" + "0".repeat(64 - suffix.length()) + suffix
}

///|
fn profile_inventory_standard(
  sources : Int,
  tasks : Int,
) -> LocalStandardAccountSubjects {
  {
    account_id: "inventory-account",
    principal: "inventory-operator",
    control_connection: "local-host",
    configured_connections: Array::makei(sources, i => "source-" + i.to_string()),
    model_tasks: Array::makei(tasks, i => {
      ("provider", profile_inventory_task(i))
    }),
    request_target: None,
    signing_key_resource: None,
  }
}

///|
fn profile_inventory_mock(
  sources : Int,
  tasks : Int,
) -> LocalMockAccountSubjects {
  {
    account_id: "inventory-account",
    principal: "inventory-operator",
    control_connection: "local-host",
    sources: Array::makei(sources, i => ("source-" + i.to_string(), "records")),
    model_tasks: Array::makei(tasks, profile_inventory_task),
    request_target: None,
    update_target: None,
    signing_key_resource: None,
  }
}

///|
fn profile_inventory_access(
  connection : String,
  resource : String,
  operation : String,
) -> AccessTuple {
  { principal: "inventory-operator", connection, resource, operation, }
}

///|
test "standard profile uses the same Account inventory beyond old Source and Task counts" {
  let subjects = profile_inventory_standard(129, 65)
  let wire = local_standard_account_configuration(subjects).unwrap()
  let original = admit_account_configuration_json(wire).unwrap()
  assert_eq(original.entry_count(), 197)
  for connection in subjects.configured_connections {
    assert_true(
      evaluate_account(
        original,
        profile_inventory_access(connection, "records", "read"),
      )
      is Allow(_),
    )
  }
  for (_, cid) in subjects.model_tasks {
    assert_true(
      evaluate_account(
        original,
        profile_inventory_access("provider", cid, "infer"),
      )
      is Allow(_),
    )
  }
  assert_true(
    evaluate_account(
      original,
      profile_inventory_access("unregistered", "records", "read"),
    )
    is Deny(NoMatch),
  )
  assert_true(
    evaluate_account(
      original,
      profile_inventory_access("source-128", "records", "effect"),
    )
    is Delegate(_),
  )
  assert_eq(local_standard_account_configuration(subjects).unwrap(), wire)
}

///|
test "Mock profile retains exact finite subjects beyond old Source and Task counts" {
  let subjects = profile_inventory_mock(129, 65)
  let original = admit_account_configuration_json(
    local_mock_account_configuration(subjects).unwrap(),
  ).unwrap()
  assert_eq(original.entry_count(), 197)
  for (connection, resource) in subjects.sources {
    assert_true(
      evaluate_account(
        original,
        profile_inventory_access(connection, resource, "read"),
      )
      is Allow(_),
    )
    assert_true(
      evaluate_account(
        original,
        profile_inventory_access(connection, "other", "read"),
      )
      is Deny(NoMatch),
    )
  }
  for cid in subjects.model_tasks {
    assert_true(
      evaluate_account(original, profile_inventory_access("mock", cid, "infer"))
      is Allow(_),
    )
  }
  assert_true(
    evaluate_account(
      original,
      profile_inventory_access("mock", profile_inventory_task(65), "infer"),
    )
    is Deny(NoMatch),
  )
}

///|
test "standard profile counts every emitted entry against the existing Account owner" {
  let subjects = profile_inventory_standard(MAX_ENTRIES - 3 - 65, 65)
  let original = admit_account_configuration_json(
    local_standard_account_configuration(subjects).unwrap(),
  ).unwrap()
  assert_eq(original.entry_count(), MAX_ENTRIES)
  assert_eq(
    local_standard_account_configuration({
      ..subjects,
      request_target: Some(("local-host", "realization")),
    }),
    Err(Configuration(TooManyEntries(MAX_ENTRIES + 1))),
  )
}

///|
test "Mock profile counts request signer and both update entries before construction" {
  let subjects = {
    ..profile_inventory_mock(MAX_ENTRIES - 7 - 65, 65),
    request_target: Some(("local-host", "realization")),
    update_target: Some(("source-0", "records")),
    signing_key_resource: Some("reviewer-key"),
  }
  let original = admit_account_configuration_json(
    local_mock_account_configuration(subjects).unwrap(),
  ).unwrap()
  assert_eq(original.entry_count(), MAX_ENTRIES)
  assert_eq(
    local_mock_account_configuration({
      ..subjects,
      model_tasks: subjects.model_tasks + [profile_inventory_task(65)],
    }),
    Err(Configuration(TooManyEntries(MAX_ENTRIES + 1))),
  )
}
