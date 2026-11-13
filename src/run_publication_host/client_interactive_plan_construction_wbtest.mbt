///|
fn interactive_geometry_actual(wire : String) -> (Int, Int, Int) raise {
  let value = parse_plan_identity_value(wire, 1000000, 100000, 100).unwrap()
  let (_, bytes, nodes, depth) = @canonical.stringify_value_with_usage(
    value, 1000000, 100000, 100,
  )
  (bytes, nodes, depth)
}

///|
test "static plan geometry matches complete original map and view including identity fields" {
  for
    prepared in [
      input_result_prepared(input_result_document),
      task_pipeline_geometry_original(),
    ] {
    let compilation = issue_prepared_client_task_compilation(
      prepared,
      run_materials_manifests(),
      prepared_client_values_sequence_limits(prepared),
      1000,
      1000,
      1000000,
      100000,
      100,
    ).unwrap()
    for inspect in [false, true] {
      let geometry = measure_client_static_plan_view(
        prepared, 1000000, 100000, 100, inspect,
      ).unwrap()
      let wire = client_task_static_plan_view(
        prepared,
        compilation,
        1000000,
        100000,
        100,
        inspect_installed=inspect,
      ).unwrap()
      assert_eq(geometry.view, interactive_geometry_actual(wire))
      let value = parse_plan_identity_value(wire, 1000000, 100000, 100).unwrap()
      let map = @canonical.object_field(value, "logical_map").unwrap()
      let map_wire = @canonical.stringify_value(map, 1000000, 100000, 100)
      assert_eq(geometry.map_sealed, interactive_geometry_actual(map_wire))
      assert_eq(geometry.map_sealed.1, geometry.map_body.1 + 1)
      assert_true(geometry.map_sealed.0 > geometry.map_body.0)
      guard @canonical.object_field(map, "steps")
        is Some(@canonical.Array(steps)) else {
        fail("steps")
      }
      assert_eq(geometry.step_count, @canonical.array_count(steps))
      let mut inputs = 0
      let mut outputs = 0
      let mut bytes = 0L
      let mut port_bytes = 0L
      for i in 0..<@canonical.array_count(steps) {
        let step = @canonical.array_at(steps, i).unwrap()
        let step_wire = @canonical.stringify_value(step, 1000000, 100000, 100)
        let actual = interactive_geometry_actual(step_wire)
        assert_true(
          actual.0 <= geometry.max_step.0 &&
          actual.1 <= geometry.max_step.1 &&
          actual.2 <= geometry.max_step.2,
        )
        bytes += actual.0.to_int64()
        guard @canonical.object_field(step, "ports")
          is Some(@canonical.Array(ports)) else {
          fail("ports")
        }
        for j in 0..<@canonical.array_count(ports) {
          let port = @canonical.array_at(ports, j).unwrap()
          let port_wire = @canonical.stringify_value(port, 1000000, 100000, 100)
          port_bytes += @utf8.encode(port_wire).length().to_int64()
          match @canonical.object_field(port, "role") {
            Some(@canonical.String("input")) => inputs += 1
            Some(@canonical.String("output")) => outputs += 1
            _ => fail("role")
          }
        }
      }
      assert_eq(geometry.steps_wire_bytes, bytes)
      assert_eq(geometry.ports_wire_bytes, port_bytes)
      assert_eq(geometry.input_port_count, inputs)
      assert_eq(geometry.output_port_count, outputs)
      for
        (b, n, d) in [
          (geometry.view.0 - 1, 100000, 100),
          (1000000, geometry.view.1 - 1, 100),
          (1000000, 100000, geometry.view.2 - 1),
        ] {
        assert_true(
          measure_client_static_plan_view(prepared, b, n, d, inspect) is Err(_),
        )
      }
    }
  }
}

///|
test "compiled plan geometry preserves provenance and does not issue a projection" {
  for tasks in [false, true] {
    let (prepared, compiled, _) = local_values_invocation_fixture(tasks)
    let geometry = measure_client_compiled_run_static_plan_view(
      compiled, prepared, 1000000, 100000, 100,
    ).unwrap()
    let wire = client_compiled_run_static_plan_view(
      compiled, prepared, 1000000, 100000, 100,
    ).unwrap()
    assert_eq(geometry.view, interactive_geometry_actual(wire))
    let (foreign, _, _) = local_values_invocation_fixture(tasks)
    assert_eq(
      measure_client_compiled_run_static_plan_view(
        compiled, foreign, 1000000, 100000, 100,
      ),
      Err(ForeignCompilation),
    )
    assert_true(
      measure_client_compiled_run_static_plan_view(
        compiled, prepared, 0, 100000, 100,
      )
      is Err(_),
    )
  }
}

///|
test "static plan quoting measures UTF8 and escaped data through the original codec" {
  for text in ["日本語😀", "a\"\\\n\r\t\u0000z", "\u2028\u2029", "e\u0301"] {
    let writer = @encode.measuring_writer(10000, 1, 1)
    @encode.string_value(writer, text)
    let geometry = @encode.finish_measurement_usage(writer)
    let wire = interactive_quote(text, 10000)
    assert_eq(geometry.0, @utf8.encode(wire).length())
    assert_eq(geometry.1, 1)
    assert_eq(geometry.2, 0)
  }
}

///|
test "static plan geometry follows long checked chains past legacy 64KiB projection boundary" {
  let body : Array[String] = [
    (
      #|{"as":"p0","values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]}}
    ),
  ]
  for i in 1..<71 {
    body.push(
      "{\"from\":\"p" +
      (i - 1).to_string() +
      "\",\"select\":[\"id\"],\"as\":\"p" +
      i.to_string() +
      "\"}",
    )
  }
  let document = "{\"version\":\"actql/0.1\",\"id\":\"long-static-map\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[" +
    body.join(",") +
    "],\"results\":{\"rows\":{\"from\":\"p70\",\"fields\":[\"id\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}"
  let prepared = input_result_prepared(document)
  let compilation = issue_prepared_client_task_compilation(
    prepared,
    run_materials_manifests(),
    prepared_client_values_sequence_limits(prepared),
    1000,
    1000,
    1000000,
    100000,
    100,
  ).unwrap()
  let geometry = measure_client_static_plan_view(
    prepared, 1000000, 100000, 100, false,
  ).unwrap()
  let wire = client_task_static_plan_view(
    prepared, compilation, 1000000, 100000, 100,
  ).unwrap()
  assert_eq(geometry.view, interactive_geometry_actual(wire))
  assert_true(geometry.view.0 > 65536)
  assert_eq(geometry.step_count, 71)
  assert_eq(geometry.max_stage_producers, 71)
  assert_true(
    measure_client_static_plan_view(prepared, 65536, 100000, 100, false)
    is Err(_),
  )
}

///|
test "Carrier measurement reservation precedes each helper and refusal has no fallback" {
  for tasks in [false, true] {
    let (prepared, compiled, _) = local_values_invocation_fixture(tasks)
    let original = measure_client_compiled_run_static_plan_view(
      compiled, prepared, 1000000, 100000, 100,
    ).unwrap()
    let calls = Ref(0)
    let admitted = measure_client_compiled_run_static_plan_view(
      compiled,
      prepared,
      1000000,
      100000,
      100,
      before_carrier_measurement=Some(_ => {
        calls.val += 1
        true
      }),
    ).unwrap()
    assert_eq(admitted, original)
    assert_eq(calls.val, original.input_port_count + original.output_port_count)
    calls.val = 0
    assert_eq(
      measure_client_compiled_run_static_plan_view(
        compiled,
        prepared,
        1000000,
        100000,
        100,
        before_carrier_measurement=Some(_ => {
          calls.val += 1
          false
        }),
      ),
      Err(Projection(ConstructionRefused)),
    )
    assert_eq(calls.val, 1)
    let (foreign, _, _) = local_values_invocation_fixture(tasks)
    calls.val = 0
    assert_eq(
      measure_client_compiled_run_static_plan_view(
        compiled,
        foreign,
        1000000,
        100000,
        100,
        before_carrier_measurement=Some(_ => {
          calls.val += 1
          true
        }),
      ),
      Err(ForeignCompilation),
    )
    assert_eq(calls.val, 0)
  }
}
