///|
test "Effect observation retains the same compiler originals without an Effect-free compilation" {
  let (owner, allowed, definition) = original_effect_materials_fixture()
  let original = capture_client_effect_run_observation_originals(
    owner, allowed, definition,
  ).unwrap()
  assert_true(physical_equal(original.prepared(), allowed.prepared))
  assert_true(physical_equal(original.authorization(), allowed.authorization))
  let restored = restore_client_run_observation_originals_wire(
    definition,
    original.wire().unwrap(),
    131072,
    8192,
    64,
  ).unwrap()
  assert_eq(restored.wire().unwrap(), original.wire().unwrap())
}

///|
test "Effect observation refuses foreign owner Run and authorization originals" {
  let (owner, allowed, definition) = original_effect_materials_fixture()
  let (foreign_owner, foreign, foreign_definition) = original_effect_materials_fixture(
    alternate=true,
  )
  assert_true(
    capture_client_effect_run_observation_originals(
      foreign_owner, allowed, definition,
    )
    is Err(_),
  )
  assert_true(
    capture_client_effect_run_observation_originals(
      owner, allowed, foreign_definition,
    )
    is Err(_),
  )
  assert_true(
    capture_client_effect_run_observation_originals(
      owner,
      { ..allowed, authorization: foreign.authorization, },
      definition,
    )
    is Err(_),
  )
}

///|
test "saved observation envelope retains original evidence strings only" {
  let (_, compiled, definition) = local_values_invocation_fixture(false)
  let original = capture_client_run_observation_originals(compiled, definition).unwrap()
  let wire = original.wire().unwrap()
  assert_true(wire.has_prefix("{\"authorization\":"))
  let decoded = @json.parse(wire) catch {
    _ => abort("invalid observation fixture")
  }
  guard decoded is Object(fields) else {
    fail("expected original observation envelope")
    return
  }
  assert_eq(fields.length(), 2)
  assert_eq(
    fields.get("authorization"),
    Some(
      Json::string(
        @publication.run_evidence_value_json(original.authorization()),
      ),
    ),
  )
  assert_eq(
    fields.get("prepared"),
    Some(
      Json::string(@publication.run_evidence_value_json(original.prepared())),
    ),
  )
}

///|
test "saved observation envelope refuses changed or noncanonical metadata" {
  let (_, compiled, definition) = local_values_invocation_fixture(false)
  let original = capture_client_run_observation_originals(compiled, definition).unwrap()
  let wire = original.wire().unwrap()
  let restored = restore_client_run_observation_originals_wire(
    definition, wire, 131072, 8192, 64,
  ).unwrap()
  assert_eq(restored.wire().unwrap(), wire)
  for changed in [wire + " ", "{\"prepared\":null}", "{}"] {
    assert_true(
      restore_client_run_observation_originals_wire(
        definition, changed, 131072, 8192, 64,
      )
      is Err(_),
    )
  }
}

///|
test "Run observation originals retain exact compiler bytes for both effect-free families" {
  for tasks in [false, true] {
    let (_, compiled, definition) = local_values_invocation_fixture(tasks)
    let original = capture_client_run_observation_originals(
      compiled, definition,
    ).unwrap()
    assert_eq(
      @publication.run_evidence_value_json(original.prepared()),
      @publication.run_evidence_value_json(
        client_compiled_run_prepared(compiled),
      ),
    )
    assert_eq(
      @publication.run_evidence_value_json(original.authorization()),
      @publication.run_evidence_value_json(
        client_compiled_run_authorization(compiled),
      ),
    )
    let restored = restore_client_run_observation_originals(
      definition,
      @publication.run_evidence_value_json(original.prepared()),
      @publication.run_evidence_value_json(original.authorization()),
      65536,
      8192,
      64,
    ).unwrap()
    assert_eq(
      @publication.run_evidence_value_identity(restored.prepared()),
      @publication.run_evidence_value_identity(original.prepared()),
    )
    assert_eq(
      @publication.run_evidence_value_identity(restored.authorization()),
      @publication.run_evidence_value_identity(original.authorization()),
    )
  }
}

///|
test "Run observation originals refuse foreign authorization context before capture" {
  let (_, compiled, definition) = local_values_invocation_fixture(false)
  let original = capture_client_run_observation_originals(compiled, definition).unwrap()
  let foreign = match compiled.compilation {
    Values(value) =>
      issue_client_values_compiled_run(
        compiled.owner,
        value,
        "sha256:" + "c".repeat(64),
        "sha256:" + "b".repeat(64),
        "2099-01-01T00:00:00.000Z",
      ).unwrap()
    _ => abort("expected Values fixture")
  }
  assert_true(
    capture_client_run_observation_originals(foreign, definition) is Err(_),
  )
  assert_true(
    restore_client_run_observation_originals(
      definition,
      @publication.run_evidence_value_json(
        client_compiled_run_prepared(foreign),
      ),
      @publication.run_evidence_value_json(original.authorization()),
      65536,
      8192,
      64,
    )
    is Err(_),
  )
}

///|
test "Run observation originals refuse missing substituted and modified saved metadata" {
  let (_, compiled, definition) = local_values_invocation_fixture(false)
  let original = capture_client_run_observation_originals(compiled, definition).unwrap()
  let prepared = @publication.run_evidence_value_json(original.prepared())
  let authorization = @publication.run_evidence_value_json(
    original.authorization(),
  )
  for
    (left, right) in [
      ("", authorization),
      (prepared, ""),
      (authorization, prepared),
      (prepared + "x", authorization),
    ] {
    assert_true(
      restore_client_run_observation_originals(
        definition, left, right, 65536, 8192, 64,
      )
      is Err(_),
    )
  }
}

///|
test "Run observation originals preserve bounded restore refusal without recapture" {
  let (_, compiled, definition) = local_values_invocation_fixture(false)
  let original = capture_client_run_observation_originals(compiled, definition).unwrap()
  assert_true(
    restore_client_run_observation_originals(
      definition,
      @publication.run_evidence_value_json(original.prepared()),
      @publication.run_evidence_value_json(original.authorization()),
      16,
      8192,
      64,
    )
    is Err(_),
  )
}
