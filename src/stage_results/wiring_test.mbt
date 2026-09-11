///|
fn wiring_fixture() -> (
  @parameters.Source,
  Array[StagePorts],
  Array[AttachedImports],
) {
  let (source, producer, ports) = import_fixture()
  let owner = bind_ports(producer, ports).unwrap()
  let cap : ImportLimits = {
    max_work: 1000,
    max_imports: 100,
    max_text_bytes: 10000,
  }
  let initial = attach_imports(
    resolve_imports(source, 0, [], cap).unwrap(),
    producer,
    max_work=1000,
  ).unwrap()
  let resolved = resolve_imports(source, 1, [owner], cap).unwrap()
  let inputs = []
  for i in 0..<import_count(resolved) {
    let entry = import_at(resolved, i).unwrap()
    inputs.push(
      (input_name(entry), @pipeline.ProducedInput(input_producer(entry))),
    )
  }
  let body = @decode.open_object(
    @syntax.stage_body(@parameters.stage_at(source, 1).unwrap()),
  ).unwrap()
  let pipeline = @pipeline.check_with_evidence(
    @decode.required(body, "steps").unwrap(),
    inputs,
    Some(@parameters.declarations(source)),
    @decode.lookup(body, "from"),
    import_pipeline_limits(),
  ).unwrap()
  let stage = @parameters.collect(source, 1, pipeline, {
    max_work: 100000,
    max_slots: 100,
    max_references: 100,
    max_pointer_units: 10000,
    max_direct_text_bytes: 10000,
  }).unwrap()
  let attached = attach_imports(resolved, stage, max_work=1000).unwrap()
  let checked = @results.check(
    pipeline,
    @decode.required(body, "results").unwrap(),
    limits(),
  ).unwrap()
  let consumer = bind_ports(stage, import_ports(checked)).unwrap()
  (source, [owner, consumer], [initial, attached])
}

///|
fn wiring_limits() -> WiringLimits {
  {
    max_work: 1000000,
    max_text_bytes: 1000000,
    max_imports: 100,
    max_exports: 100,
  }
}

///|
test "whole Program Result wiring preserves root export ownership and cumulative budgets" {
  let (source, stages, attached) = wiring_fixture()
  let wired = wire_results(source, stages, attached, wiring_limits()).unwrap()
  assert_true(physical_equal(wiring_source(wired), source))
  for i in 0..<2 {
    assert_true(physical_equal(wiring_stage_at(wired, i).unwrap(), stages[i]))
    assert_true(
      physical_equal(wiring_imports_at(wired, i).unwrap(), attached[i]),
    )
  }
  assert_eq(export_count(wired), 1)
  let exported = export_at(wired, 0).unwrap()
  assert_eq(export_name(exported), "out")
  assert_true(physical_equal(export_stage(exported), stages[1]))
  assert_true(
    physical_equal(
      export_port(exported),
      @results.lookup_port(stage_port_publications(stages[1]), "r").unwrap(),
    ),
  )
  let (work, text) = wiring_usage(wired)
  let exact : WiringLimits = {
    max_work: work,
    max_text_bytes: text,
    max_imports: 2,
    max_exports: 1,
  }
  assert_true(wire_results(source, stages, attached, exact) is Ok(_))
  for
    cap in [
      { ..exact, max_work: work - 1, },
      { ..exact, max_text_bytes: text - 1, },
      { ..exact, max_imports: 1, },
      { ..exact, max_exports: 0, },
    ] {
    assert_true(
      wire_results(source, stages, attached, cap) is Err(BudgetExceeded),
    )
  }
  assert_true(
    wire_results(source, [stages[0]], attached, exact)
    is Err(StageCountMismatch),
  )
  assert_true(
    wire_results(source, [stages[1], stages[0]], attached, wiring_limits())
    is Err(ForeignStage(0)),
  )
  let (_, other_stages, _) = wiring_fixture()
  assert_true(
    wire_results(source, other_stages, attached, wiring_limits())
    is Err(ForeignStage(0)),
  )
  // A new wrapper around the same checked owners is harmless; replacing the
  // actual publications that the consumer retained is not.
  let replacement = bind_ports(
    stage_port_source(stages[0]),
    stage_port_publications(stages[0]),
  ).unwrap()
  assert_true(
    wire_results(source, [replacement, stages[1]], attached, wiring_limits())
    is Ok(_),
  )
  let producer_stage = stage_port_source(stages[0])
  let producer_body = @decode.open_object(
    @syntax.stage_body(@parameters.stage_at(source, 0).unwrap()),
  ).unwrap()
  let rechecked = @results.check(
    @collection.pipeline(@parameters.collection(producer_stage)),
    @decode.required(producer_body, "results").unwrap(),
    limits(),
  ).unwrap()
  let substituted = bind_ports(producer_stage, import_ports(rechecked)).unwrap()
  assert_true(
    wire_results(source, [substituted, stages[1]], attached, wiring_limits())
    is Err(ForeignProducer(1, _)),
  )
  assert_true(
    wire_results(source, stages, attached, { ..exact, max_work: -1, })
    is Err(InvalidLimits),
  )
  stages.clear()
  attached.clear()
  assert_true(wiring_stage_at(wired, 1) is Some(_))
  assert_true(wiring_imports_at(wired, 1) is Some(_))
  assert_true(export_at(wired, -1) is None)
  assert_true(export_at(wired, 1) is None)
}
