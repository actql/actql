///|
fn explanation_envelope_value(
  original : ClientStructuralExplanationOriginal,
  compiled : ClientCompiledRun,
  prepared : PreparedClientProgram,
) -> @canonical.CanonicalValue {
  let facts = seal_client_structural_explanation_facts(
    original, compiled, prepared, 1000000, 100000, 100,
  ).unwrap()
  @publication.parse_interactive_run_control_shape(
    "explanation_facts",
    @publication.run_evidence_value_json(facts),
    1000000,
    100000,
    100,
  ).unwrap()
}

///|
test "explanation envelope copies SAME original map Step keys and port IDs for both compilation paths" {
  for tasks in [false, true] {
    let (prepared, compiled, _) = local_values_invocation_fixture(tasks)
    let original = capture_client_structural_explanation_original(
      compiled, prepared, 1000000, 100000, 100,
    ).unwrap()
    let facts = explanation_envelope_value(original, compiled, prepared)
    assert_true(
      @canonical.object_field(facts, "disclosure")
      is Some(@canonical.String("structural")),
    )
    for
      (fact_field, map_field) in [
        ("compiled_plan_cid", "compiled_plan_cid"),
        ("program_definition_cid", "program_definition_cid"),
        ("logical_map_cid", "self_cid"),
      ] {
      assert_eq(
        compiled_run_plan_field(facts, fact_field),
        compiled_run_plan_field(original.map, map_field),
      )
    }
    assert_eq(
      compiled_run_plan_field(facts, "parameter_values_cid"),
      prepared_client_identity(prepared).parameter_values_cid,
    )
    guard @canonical.object_field(facts, "steps")
      is Some(@canonical.Array(steps)) &&
      @canonical.object_field(original.map, "steps")
      is Some(@canonical.Array(map_steps)) else {
      fail("original steps")
    }
    assert_eq(@canonical.array_count(steps), @canonical.array_count(map_steps))
    for i in 0..<@canonical.array_count(steps) {
      let fact = @canonical.array_at(steps, i).unwrap()
      let step = @canonical.array_at(map_steps, i).unwrap()
      for field in ["step_id", "key", "operator"] {
        assert_eq(
          @canonical.stringify_value(
            @canonical.object_field(fact, field).unwrap(),
            65536,
            8192,
            64,
          ),
          @canonical.stringify_value(
            @canonical.object_field(step, field).unwrap(),
            65536,
            8192,
            64,
          ),
        )
      }
      guard @canonical.object_field(step, "ports")
        is Some(@canonical.Array(ports)) else {
        fail("original ports")
      }
      for
        (role, field) in [("input", "input_ports"), ("output", "output_ports")] {
        guard @canonical.object_field(fact, field)
          is Some(@canonical.Array(ids)) else {
          fail("projected ports")
        }
        let mut count = 0
        for j in 0..<@canonical.array_count(ports) {
          let port = @canonical.array_at(ports, j).unwrap()
          if compiled_run_plan_field(port, "role") == role {
            let expected = compiled_run_plan_field(port, "port_id")
            assert_true(
              @canonical.array_at(ids, count) is Some(@canonical.String(actual)) &&
              actual == expected,
            )
            count += 1
          }
        }
        assert_eq(count, @canonical.array_count(ids))
      }
    }
  }
}

///|
test "explanation envelope retains typed parameter meaning and excludes literal rows bounds and values" {
  let prepared = structural_explanation_prepared(
    "{\"gt\":[{\"field\":\"id\"},{\"$param\":\"threshold\"}]}",
    parameter=true,
  )
  let compiled = issue_client_task_compiled_run(
    prepared,
    structural_explanation_compiled(prepared),
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let original = capture_client_structural_explanation_original(
    compiled, prepared, 1000000, 100000, 100,
  ).unwrap()
  let facts = seal_client_structural_explanation_facts(
    original, compiled, prepared, 1000000, 100000, 100,
  ).unwrap()
  let wire = @publication.run_evidence_value_json(facts)
  for
    forbidden in [
      "PRIVATE", "max_utf8_bytes", "row_count", "\"rows\"", "\"value\"", "\"default\"",
      "\"value_cid\"", "prompt", "source_body",
    ] {
    assert_false(wire.contains(forbidden))
  }
  assert_true(wire.contains("\"parameter\""))
  assert_true(wire.contains("\"threshold\""))
  assert_true(
    @publication.parse_interactive_run_control_shape(
      "explanation_facts", wire, 1000000, 100000, 100,
    )
    is Ok(_),
  )
}

///|
test "explanation envelope measurement includes final identity and refuses finite output limits" {
  let (prepared, compiled, _) = local_values_invocation_fixture(true)
  let original = capture_client_structural_explanation_original(
    compiled, prepared, 1000000, 100000, 100,
  ).unwrap()
  let geometry = measure_client_structural_explanation_facts(
    original, compiled, prepared, 1000000, 100000, 100,
  ).unwrap()
  let facts = seal_client_structural_explanation_facts(
    original,
    compiled,
    prepared,
    geometry.complete.0,
    geometry.complete.1,
    geometry.complete.2,
  ).unwrap()
  let wire = @publication.run_evidence_value_json(facts)
  assert_eq(geometry.complete, interactive_geometry_actual(wire))
  assert_eq(geometry.complete.1, geometry.body.1 + 1)
  assert_true(geometry.complete.0 > geometry.body.0)
  for
    (b, n, d) in [
      (geometry.complete.0 - 1, 100000, 100),
      (1000000, geometry.complete.1 - 1, 100),
      (1000000, 100000, geometry.complete.2 - 1),
    ] {
    assert_true(
      measure_client_structural_explanation_facts(
        original, compiled, prepared, b, n, d,
      )
      is Err(_),
    )
    assert_true(
      seal_client_structural_explanation_facts(
        original, compiled, prepared, b, n, d,
      )
      is Err(_),
    )
  }
  assert_true(
    measure_client_structural_explanation_facts(
      original, compiled, prepared, 0, 100000, 100,
    )
    is Err(InvalidReadLimits),
  )
}

///|
test "explanation envelope rejects equal foreign compiler originals without changing the existing Plan view" {
  let (prepared, compiled, _) = local_values_invocation_fixture(true)
  let (foreign_prepared, foreign_compiled, _) = local_values_invocation_fixture(
    true,
  )
  let before = client_compiled_run_static_plan_view(
    compiled, prepared, 1000000, 100000, 100,
  ).unwrap()
  let original = capture_client_structural_explanation_original(
    compiled, prepared, 1000000, 100000, 100,
  ).unwrap()
  assert_true(
    capture_client_structural_explanation_original(
      compiled, foreign_prepared, 1000000, 100000, 100,
    )
    is Err(OriginalPlan(ForeignCompilation)),
  )
  assert_true(
    measure_client_structural_explanation_facts(
      original, foreign_compiled, foreign_prepared, 1000000, 100000, 100,
    )
    is Err(ForeignOriginal),
  )
  assert_true(
    seal_client_structural_explanation_facts(
      original, compiled, foreign_prepared, 1000000, 100000, 100,
    )
    is Err(ForeignOriginal),
  )
  seal_client_structural_explanation_facts(
    original, compiled, prepared, 1000000, 100000, 100,
  ).unwrap()
  |> ignore
  assert_eq(
    client_compiled_run_static_plan_view(
      compiled, prepared, 1000000, 100000, 100,
    ).unwrap(),
    before,
  )
}

///|
test "explanation input-only occurrence preserves original null operator instead of synthesizing an operation" {
  let (prepared, compiled, _) = local_values_invocation_fixture(
    true,
    document=input_result_document,
  )
  let original = capture_client_structural_explanation_original(
    compiled, prepared, 1000000, 100000, 100,
  ).unwrap()
  let value = explanation_envelope_value(original, compiled, prepared)
  guard @canonical.object_field(value, "steps") is Some(@canonical.Array(steps)) else {
    fail("steps")
  }
  assert_eq(@canonical.array_count(steps), 2)
  let input = @canonical.array_at(steps, 1).unwrap()
  assert_true(
    @canonical.object_field(input, "operator") is Some(@canonical.Null),
  )
  let meaning = @canonical.object_field(input, "meaning").unwrap()
  assert_eq(compiled_run_plan_field(meaning, "kind"), "input_output")
}
