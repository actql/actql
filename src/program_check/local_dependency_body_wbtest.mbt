///|
test "checked dependency bodies retain exact preimages and owner" {
  let prepared : Array[CheckedProgram] = []
  for _ in 0..<2 {
    local_construction_fixture(
      { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
      second_stage=true,
      parameters=true,
      through_check=true,
      checked_results=prepared,
    )
    |> ignore
  }
  let program = prepared[0]
  for unit in 0..<2 {
    let closure = checked_local_dependency_bodies(
      program, unit, 4096, 1000000, 100000, 100,
    ).unwrap()
    assert_eq(closure[0].0, "local_dependencies")
    assert_eq(closure[5].0, "local_policy")
    assert_eq(
      closure.filter(item => item.0 == "result_import_interface").length(),
      if unit == 0 {
        0
      } else {
        2
      },
    )
    assert_true(
      checked_local_dependency_bodies(
        program,
        unit,
        closure.length() - 1,
        1000000,
        100000,
        100,
      )
      is Err(BudgetExceeded),
    )
    assert_true(
      checked_local_dependency_bodies(program, unit, 4096, 1, 100000, 100)
      is Err(_),
    )
    let kinds : Array[LocalDependencyBodyKind] = [
      UnitDefinition,
      LocalBody,
      ParameterDeclarations,
      UsedValues,
      LocalContracts,
      LocalPolicy,
    ]
    if unit == 1 {
      kinds.push(ResultInterface(0))
      kinds.push(ResultInterface(1))
      kinds.push(ResultType(0))
      kinds.push(ResultType(1))
    }
    for
      index in 0..<@environment.member_count(
        checked_environment(program),
        @environment.SchemaSnapshots,
      ) {
      kinds.push(SourceSchema(index))
      let expected = checked_local_dependency_body(
        program,
        unit,
        SourceSchema(index),
        1000000,
        100000,
        100,
      ).unwrap()
      let selected = checked_local_catalog_dependency_body(
        program,
        unit,
        "schema_evidence",
        expected.cid,
        1000000,
        100000,
        100,
      ).unwrap()
      assert_eq(selected.wire, expected.wire)
      assert_true(
        checked_local_dependency_body_matches(
          selected,
          program,
          unit,
          SourceSchema(index),
        ),
      )
      assert_true(
        checked_local_catalog_dependency_body(
          program,
          unit,
          "schema_evidence",
          expected.cid,
          1,
          100000,
          100,
        )
        is Err(Encoding),
      )
    }
    assert_true(
      checked_local_catalog_dependency_body(
        program, unit, "schema_evidence", "sha256:missing", 1000000, 100000, 100,
      )
      is Err(MissingDependency),
    )
    assert_true(
      checked_local_catalog_dependency_body(
        program, unit, "unknown-role", "unused", 1000000, 100000, 100,
      )
      is Err(MissingDependency),
    )
    for
      index in 0..<@environment.member_count(
        checked_environment(program),
        @environment.ConnectorCapabilities,
      ) {
      kinds.push(SourceCapability(index))
    }
    for
      index in 0..<@context.program_incoming_gates_count(program.gates, unit).unwrap() {
      kinds.push(IncomingGate(index))
    }
    for kind in kinds {
      let body = checked_local_dependency_body(
        program, unit, kind, 1000000, 100000, 100,
      ).unwrap()
      assert_true(
        checked_local_dependency_body_matches(body, program, unit, kind),
      )
      assert_false(
        checked_local_dependency_body_matches(body, prepared[1], unit, kind),
      )
      assert_false(
        checked_local_dependency_body_matches(body, program, 1 - unit, kind),
      )
      let wire = checked_local_dependency_body_json(body)
      let local_kind = match kind {
        UnitDefinition => Some("local_dependencies")
        ResultInterface(_) => Some("result_import_interface")
        IncomingGate(_) => Some("gate_requirement")
        _ => None
      }
      if local_kind is Some(local_kind) {
        let admitted = @run_publication.admit_local_effect_dependency_body(
          local_kind, wire, 1000000, 100000, 100,
        ).unwrap()
        assert_eq(
          @run_publication.captured_effect_dependency_body_json(admitted),
          wire,
        )
        assert_true(
          @run_publication.admit_local_effect_dependency_body(
            local_kind,
            wire + " ",
            1000000,
            100000,
            100,
          )
          is Err(_),
        )
      }
      let raw_kind = match kind {
        LocalBody => Some("local_body")
        ParameterDeclarations => Some("parameter_declarations")
        UsedValues => Some("used_values")
        LocalContracts => Some("local_contracts")
        LocalPolicy => Some("local_policy")
        ResultType(_) => Some("result_import_type")
        _ => None
      }
      if raw_kind is Some(raw_kind) {
        let admitted = @run_publication.admit_hashed_effect_dependency_body(
          raw_kind,
          body.cid,
          wire,
          1000000,
          100000,
          100,
        ).unwrap()
        assert_eq(
          @run_publication.captured_effect_dependency_body_json(admitted),
          wire,
        )
      }
      let restored = admit_checked_local_dependency_body(
        program, unit, kind, body, wire,
      ).unwrap()
      assert_true(physical_equal(restored, body))
      for altered in ["", " " + wire, wire + "\n", "{}"] {
        if altered != wire {
          assert_true(
            admit_checked_local_dependency_body(
              program, unit, kind, body, altered,
            )
            is Err(ForeignBody),
          )
        }
      }
      assert_true(
        admit_checked_local_dependency_body(prepared[1], unit, kind, body, wire)
        is Err(ForeignBody),
      )
      assert_true(
        admit_checked_local_dependency_body(program, 1 - unit, kind, body, wire)
        is Err(ForeignBody),
      )
      let node = @source.parse_json(wire, {
        max_input_bytes: 1000000,
        max_nodes: 100000,
        max_depth: 100,
      }).unwrap()
      let value = @json.from_source(node, 100000, 100, 1000000)
      let preimage = if @json.object_field(value, "self_cid") is Some(self_cid) {
        assert_true(self_cid is @json.String(cid) && cid == body.cid)
        @json.object_without_field(value, "self_cid").unwrap()
      } else {
        value
      }
      assert_eq(@json.cid_value(preimage, 1000000, 100000, 100), body.cid)
      assert_true(
        checked_local_dependency_body(program, unit, kind, 1, 100000, 100)
        is Err(Encoding),
      )
    }
  }
  for
    kind in [
      ResultInterface(2),
      ResultType(2),
      IncomingGate(999),
      SourceSchema(999),
      SourceCapability(999),
    ] {
    assert_true(
      checked_local_dependency_body(program, 1, kind, 1000000, 100000, 100)
      is Err(MissingDependency),
    )
  }
  assert_true(
    checked_local_dependency_body(
      program,
      2,
      UnitDefinition,
      1000000,
      100000,
      100,
    )
    is Err(MissingUnit),
  )
}
