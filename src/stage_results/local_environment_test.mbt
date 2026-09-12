///|
fn local_environment_fixture() -> @environment.WireEnvironment {
  // Fixed canonical preimage hashed independently with Node SHA-256.
  let cid = "sha256:0dce18eacaf2b67655f82d4755b37b393882d12116811c85ad2231f33f257947"
  let text =
    #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[],"contract_registry":[],"evidence_bundle_cid":"sha256:0dce18eacaf2b67655f82d4755b37b393882d12116811c85ad2231f33f257947","host_policy_profile":{},"mapping_contracts":[],"model_task_contracts":[],"schema_snapshots":[{"output_carrier":"relation","schema":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"},"source_ref":"source:local/first/rows","version":"actql-local-input-schema/0.1"}],"source_views":[],"version":"actql-check-environment/0.1"}
  @environment.read(@utf8.encode(text), cid, {
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 100,
    max_members: 10,
  }).unwrap()
}

///|
test "Local preparation uses snapshot schemas before constructing pipelines and imports" {
  for multiple in [false, true] {
    let source = local_program_source(multiple, untyped=true)
    let program = @parameters.program(source)
    let limits = local_program_limits()
    assert_true(
      prepare_local_source(program, None, max_parameters=0, limits)
      is Err(Program(Pipeline(0, _))),
    )
    let environment = local_environment_fixture()
    let prepared = prepare_local_source(
      program,
      None,
      max_parameters=0,
      limits,
      environment=Some(environment),
    ).unwrap()
    let wiring = local_source_wiring(prepared)
    let last = wiring_stage_at(wiring, @syntax.stage_count(program) - 1).unwrap()
    let output = @pipeline.output_schema(
      @collection.pipeline(@parameters.collection(stage_port_source(last))),
    ).unwrap()
    assert_true(
      @contract.type_equal(
        @schema.lookup(
          output,
          @schema.Unqualified(if multiple { "more" } else { "extra" }),
        ).unwrap(),
        @contract.primitive(NumberType, nullable=false),
        100,
      ),
    )
    let registrations = wiring_local_environment(wiring).unwrap()
    assert_true(
      physical_equal(@local.program_environment(registrations), environment),
    )
    assert_true(
      physical_equal(
        @local.environment_program(registrations),
        local_source_source(prepared),
      ),
    )
    for i in 0..<@syntax.stage_count(program) {
      let attached = wiring_reconciled_input_at(wiring, i).unwrap()
      assert_true(
        physical_equal(
          @local.reconciled_stage(attached),
          stage_port_source(wiring_stage_at(wiring, i).unwrap()),
        ),
      )
      assert_true(
        physical_equal(
          @local.reconciled_inputs(attached),
          @local.program_environment_stage(registrations, i).unwrap(),
        ),
      )
      assert_true(wiring_local_input_at(wiring, i) is None)
    }
    let used = local_source_usage(prepared)
    let exact = {
      ..limits,
      max_work: used.work,
      max_nodes: used.nodes,
      max_text_bytes: used.text_bytes,
    }
    assert_true(
      prepare_local_source(
        program,
        None,
        max_parameters=0,
        exact,
        environment=Some(environment),
      )
      is Ok(_),
    )
    for
      short in [
        { ..exact, max_work: used.work - 1, },
        { ..exact, max_nodes: used.nodes - 1, },
        { ..exact, max_text_bytes: used.text_bytes - 1, },
      ] {
      assert_true(
        prepare_local_source(
          program,
          None,
          max_parameters=0,
          short,
          environment=Some(environment),
        )
        is Err(_),
      )
    }
    assert_true(
      prepare_local_program(source, limits, environment=Some(registrations))
      is Err(ForeignEnvironmentSource),
    )
    assert_true(wiring_reconciled_input_at(wiring, -1) is None)
    assert_true(
      wiring_reconciled_input_at(wiring, @syntax.stage_count(program)) is None,
    )
  }
  let invalid = @parameters.program(
    local_program_source(true, untyped=true, bad_later=true),
  )
  assert_true(
    prepare_local_source(
      invalid,
      None,
      max_parameters=0,
      local_program_limits(),
      environment=Some(local_environment_fixture()),
    )
    is Err(Program(Pipeline(1, _))),
  )
}
