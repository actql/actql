///|
fn content_construction_geometry(wire : String) -> (Int, Int, Int) {
  let value = parse_plan_identity_value(wire, 1000000, 100000, 100).unwrap()
  let writer = @encode.measuring_writer(1000000, 100000, 100) catch {
    _ => abort("fixture writer")
  }
  @canonical.emit_value(value, writer) catch {
    _ => abort("fixture measurement")
  }
  @encode.finish_measurement_usage(writer) catch {
    _ => abort("fixture measurement")
  }
}

///|
test "Content input constructor sizing follows same earlier input sort and empty originals" {
  for
    (detour, ordered, empty) in [
      (false, false, false),
      (true, false, false),
      (false, true, false),
      (false, false, true),
    ] {
    let owner = serialization_preparation_test_program(
      detour~,
      ordered~,
      empty~,
    )
    let step = if detour { 2 } else { 1 }
    let sequence = run_materials_limits().sequence
    let retained = owner.task_pipeline_inputs.length()
    let measured = measure_prepared_client_serialization_prefix_construction(
      owner, 0, step, 10000, sequence, 1000000, 100000, 100,
    ).unwrap()
    let original = issue_prepared_client_serialization_prefix_fragment(
      owner, 0, step, 10000, sequence, 1000000, 100000, 100,
    ).unwrap()
    let actual = content_construction_geometry(original.wire)
    assert_true(actual.0 <= measured.fragment.0)
    assert_eq(actual.1, measured.fragment.1)
    assert_eq(actual.2, measured.fragment.2)
    assert_eq(
      (original.node_id, original.output_port, original.output_carrier),
      (measured.node_id, measured.output_port, measured.output_carrier),
    )
    assert_eq(owner.task_pipeline_inputs.length(), retained)
  }
}

///|
test "Content graph sizing uses original emitters and complete possible Result inventory" {
  for
    (detour, ordered, projected, empty) in [
      (false, false, false, false),
      (true, false, true, false),
      (false, true, true, false),
      (false, false, true, true),
    ] {
    let owner = serialization_preparation_test_program(
      detour~,
      ordered~,
      projected~,
      empty~,
    )
    let step = if detour { 2 } else { 1 }
    let sequence = run_materials_limits().sequence
    let measured = measure_prepared_client_serialization_graph_construction(
      owner, 0, step, 100, 1000, 10000, sequence, 1000000, 100000, 100,
    ).unwrap()
    // Measuring creates no component/identity. Only this existing issuer
    // selects the real policy/producer/Result branch and constructs its wire.
    let original = issue_prepared_client_serialization_plan_graph(
      owner,
      0,
      step,
      serialization_plan_test_policy(),
      100,
      1000,
      10000,
      sequence,
      1000000,
      100000,
      100,
    ).unwrap()
    assert_eq(
      content_construction_geometry(original.output.wire),
      measured.node,
    )
    let actual = content_construction_geometry(original.graph.wire)
    assert_true(actual.0 <= measured.graph.0)
    assert_true(actual.1 <= measured.graph.1)
    assert_true(actual.2 <= measured.graph.2)
    assert_eq(
      measured.results.length(),
      @strategy.graph_result_count(owner.graph),
    )
    assert_eq(measured.projections.length(), measured.results.length())
    assert_true(measured.prefix is Some(_))
  }
}

///|
test "Content sizing keeps declared codec refusals and intermediate root ownership separate" {
  let owner = serialization_preparation_test_program()
  let limits = run_materials_limits().sequence
  for (b, n, d) in [(0, 100000, 100), (1000000, 0, 100), (1000000, 100000, 0)] {
    assert_true(
      measure_prepared_client_serialization_graph_construction(
        owner, 0, 1, 100, 1000, 10000, limits, b, n, d,
      )
      is Err(InvalidLimits),
    )
  }
  let intermediate = measure_prepared_client_serialization_graph_construction(
    owner,
    0,
    1,
    100,
    1000,
    10000,
    limits,
    1000000,
    100000,
    100,
    include_results=false,
  ).unwrap()
  assert_true(
    intermediate.results.is_empty() &&
    intermediate.projections.is_empty() &&
    intermediate.roots.is_empty(),
  )
  // A geometry does not validate a policy or mint an actual component.
  assert_true(
    issue_prepared_client_serialization_plan_graph(
      owner,
      0,
      1,
      serialization_plan_test_policy(),
      100,
      1000,
      0,
      limits,
      1000000,
      100000,
      100,
    )
    is Err(_),
  )
}
