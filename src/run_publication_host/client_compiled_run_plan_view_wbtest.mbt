///|
fn compiled_run_plan_field(
  value : @canonical.CanonicalValue,
  field : String,
) -> String raise {
  match @canonical.object_field(value, field) {
    Some(@canonical.String(text)) => text
    _ => fail("missing original " + field)
  }
}

///|
test "fresh static maps satisfy the unchanged external binding reader" {
  for tasks in [false, true] {
    let (prepared, compiled, _) = local_values_invocation_fixture(tasks)
    let wire = client_compiled_run_static_plan_view(
      compiled, prepared, 65536, 8192, 64,
    ).unwrap()
    let view = parse_plan_identity_value(wire, 65536, 8192, 64).unwrap()
    let map = @canonical.object_field(view, "logical_map").unwrap()
    let map_wire = @canonical.stringify_value(map, 65536, 8192, 64)
    let admitted = @publication.admit_run_evidence_value(
      "logical_map", map_wire, 65536, 8192, 64,
    ).unwrap()
    @publication.check_interactive_logical_map_binding(
      admitted,
      client_compiled_run_plan(compiled),
      65536,
      8192,
      64,
    ).unwrap()
  }
}

///|
test "compiled Run map uses the retained compiler occurrence owner without another compilation" {
  for tasks in [false, true] {
    let (prepared, compiled, _) = local_values_invocation_fixture(tasks)
    let wire = client_compiled_run_static_plan_view(
      compiled, prepared, 65536, 8192, 64,
    ).unwrap()
    let view = parse_plan_identity_value(wire, 65536, 8192, 64).unwrap()
    let map = @canonical.object_field(view, "logical_map").unwrap()
    let original_plan = @publication.publication_contract_identity(
      client_compiled_run_plan(compiled),
    )
    assert_eq(compiled_run_plan_field(view, "compiled_plan_cid"), original_plan)
    assert_eq(compiled_run_plan_field(map, "compiled_plan_cid"), original_plan)
    assert_eq(
      compiled_run_plan_field(map, "program_definition_cid"),
      prepared_client_identity(prepared).program_definition_cid,
    )
    assert_true(
      @canonical.object_field(view, "provider_io")
      is Some(@canonical.Number(0.0)),
    )
    let capabilities = @canonical.object_field(view, "capabilities").unwrap()
    for field in ["durable_control", "inspect", "cost_guard", "execution_batch"] {
      assert_true(
        @canonical.object_field(capabilities, field)
        is Some(@canonical.Bool(false)),
      )
    }
    assert_eq(
      client_compiled_run_static_plan_view(compiled, prepared, 65536, 8192, 64),
      Ok(wire),
    )
    let expected = match compiled.compilation {
      Values(original) =>
        client_values_static_plan_view(prepared, original, 65536, 8192, 64)
      Tasks(original) =>
        client_task_static_plan_view(prepared, original, 65536, 8192, 64)
      Effects(_) => fail("unexpected Effect fixture")
    }
    assert_eq(Ok(wire), expected)
  }
}

///|
test "compiled Run map refuses a newly prepared equal document and caller bounds" {
  for tasks in [false, true] {
    let (prepared, compiled, _) = local_values_invocation_fixture(tasks)
    let (foreign, _, _) = local_values_invocation_fixture(tasks)
    assert_eq(
      client_compiled_run_static_plan_view(compiled, foreign, 65536, 8192, 64),
      Err(ClientCompiledRunPlanIssue::ForeignCompilation),
    )
    assert_eq(
      client_compiled_run_static_plan_view(compiled, prepared, 0, 8192, 64),
      Err(Projection(InvalidReadLimits)),
    )
    assert_true(
      client_compiled_run_static_plan_view(compiled, prepared, 65536, 1, 64)
      is Err(_),
    )
    assert_true(
      client_compiled_run_static_plan_view(compiled, prepared, 65536, 8192, 1)
      is Err(_),
    )
  }
}

///|
test "installed Inspect hint does not replace the original compiled Run map identity" {
  let (prepared, compiled, _) = local_values_invocation_fixture(false)
  let original = parse_plan_identity_value(
    client_compiled_run_static_plan_view(compiled, prepared, 65536, 8192, 64).unwrap(),
    65536,
    8192,
    64,
  ).unwrap()
  let installed = parse_plan_identity_value(
    client_compiled_run_static_plan_view(
      compiled,
      prepared,
      65536,
      8192,
      64,
      inspect_installed=true,
    ).unwrap(),
    65536,
    8192,
    64,
  ).unwrap()
  assert_eq(
    @canonical.stringify_value(
      @canonical.object_field(original, "logical_map").unwrap(),
      65536,
      8192,
      64,
    ),
    @canonical.stringify_value(
      @canonical.object_field(installed, "logical_map").unwrap(),
      65536,
      8192,
      64,
    ),
  )
  assert_true(
    @canonical.object_field(
      @canonical.object_field(installed, "capabilities").unwrap(),
      "inspect",
    )
    is Some(@canonical.Bool(true)),
  )
}
