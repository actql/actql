///|
fn prepared_identity_fixture(
  first_by_order? : Bool = false,
  unused_operation? : Bool = false,
  third_stage? : Bool = false,
  environment_profile? : String = capacity_profile(false),
) -> (ProgramSourceIdentity, @stage_results.ResultWiring, ReconciledContexts) {
  // No acquired rows or schema snapshots. The environment still undergoes
  // canonical integrity and selected-policy admission. Hashing here constructs
  // fixture input; independent expectations below do not use this helper.
  let body = "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[],\"contract_registry\":[],\"host_policy_profile\":" +
    environment_profile +
    ",\"mapping_contracts\":[],\"model_task_contracts\":[],\"schema_snapshots\":[],\"source_views\":[],\"version\":\"actql-check-environment/0.1\"}"
  let cid = "sha256:" + @sha.hex(@utf8.encode(body))
  let environment = @environment.read(
    @utf8.encode(
      body.replace(
        old="\"host_policy_profile\":",
        new="\"evidence_bundle_cid\":\"" + cid + "\",\"host_policy_profile\":",
      ),
    ),
    cid,
    { max_bytes: 10000, max_nodes: 1000, max_depth: 100, max_members: 10, },
  ).unwrap()
  let (stages, wiring, _, _, _, _) = prepared_local_context_fixture(
    first_by_order~,
    unused_operation~,
    third_stage~,
    environment=Some(environment),
  )
  let wired = attach_result_wiring(
    stages,
    wiring,
    max_work=10000000,
    max_text_bytes=10000000,
  ).unwrap()
  let reconciled = attach_prepared_local_inputs(
    wired,
    max_work=10000000,
    max_text_bytes=10000000,
    max_local_input_nodes=100000,
  ).unwrap()
  (
    prepared_reconciled_identity(
      reconciled,
      environment,
      max_stages=if third_stage { 3 } else { 2 },
    ),
    wiring,
    reconciled,
  )
}

///|
fn prepared_reconciled_identity(
  reconciled : ReconciledContexts,
  environment : @environment.WireEnvironment,
  max_stages? : Int = 2,
) -> ProgramSourceIdentity {
  let selected = bind_capacity_policy(
    reconciled,
    match
      @environment.read_capacity(environment, {
        max_bytes: 10000,
        max_nodes: 100,
        max_depth: 10,
      }) {
      Ok(value) => value
      Err(issue) => {
        @debug.debug(issue)
        abort("capacity fixture")
      }
    },
    max_work=10000000,
    max_text_bytes=10000000,
    max_policy_nodes=100,
  ).unwrap()
  let producer = preparation_sources_fixture(selected)
  let operations = prepare_program_checks(
    producer,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    preparation_limits(),
    max_policy_depth=validation_limits().max_policy_depth,
    max_requirements=validation_limits().max_requirements,
    max_regex_depth=pattern_limits().max_regex_depth,
  ).unwrap()
  let limits = source_preparation_limits()
  prepare_program_source_identity(operations, {
    ..limits,
    identity: { ..limits.identity, max_stages, },
  }).unwrap()
}

///|
test "prepared multi-stage Program reaches source identity without replacing imported producers" {
  let (identity, wiring, context) = prepared_identity_fixture()
  let sources = program_identity_sources(identity)
  let references = program_sources_references(sources)
  let stages = program_reference_stages(references)
  let operations = @stages.bound_operations(stage_operations(stages))
  assert_eq(program_identity_stage_count(identity), 2)
  // Independently computed SHA-256 of canonical UTF-8:
  // {"values":{"n":2},"version":"actql-parameter-values/0.1"}
  let expected_values = "sha256:1304688593f0f3e9917621856ffd73242e3c000fa8696f1a49e19db361d74436"
  assert_eq(program_identity_parameter_values_cid(identity), expected_values)
  for i in 0..<2 {
    assert_eq(
      stage_identity_parameter_values_cid(
        program_identity_stage_at(identity, i).unwrap(),
      ),
      expected_values,
    )
    assert_true(
      physical_equal(
        @stages.operations_stage_at(operations, i).unwrap(),
        @stage_results.stage_port_source(
          @stage_results.wiring_stage_at(wiring, i).unwrap(),
        ),
      ),
    )
  }
  let resolved = resolve_program_operations(identity, {
    max_work: 10000000,
    max_requirements: 100,
    max_resolutions: 100,
  }).unwrap()
  let requirements = operation_resolution_requirements(resolved)
  let expressions = operation_requirements_expressions(requirements)
  assert_eq(expression_closure_count(expressions), 0)
  assert_true(
    physical_equal(
      operation_requirements_expressions(requirements),
      expressions,
    ),
  )
  // Identity is stable across reconstruction, ownership is deliberately not.
  let (again, _, other_context) = prepared_identity_fixture()
  assert_eq(
    program_identity_definition_cid(identity),
    program_identity_definition_cid(again),
  )
  assert_false(
    physical_equal(
      program_identity_sources(identity),
      program_identity_sources(again),
    ),
  )
  let (work, bytes, nodes) = program_identity_usage(identity)
  let exact = {
    ..identity_limits(),
    max_work: work,
    max_hash_bytes: bytes,
    max_hash_nodes: nodes,
  }
  assert_true(identify_program_sources(sources, exact) is Ok(_))
  assert_true(
    identify_program_sources(sources, { ..exact, max_work: work - 1, })
    is Err(BudgetExceeded),
  )
  // No SourceViews is not no semantic dependencies: both stages and the
  // repeated Result imports remain owned, and require their separate laws.
  let caps : SourceContractLimits = {
    max_work: 10000000,
    max_inputs: 0,
    max_references: 0,
  }
  let contracts = collect_source_contracts(context, caps).unwrap()
  assert_eq(source_contract_stage_count(contracts), 2)
  assert_eq(source_contract_input_count(contracts, 0), Some(0))
  assert_eq(source_contract_input_count(contracts, 1), Some(0))
  let selected_contracts = bind_program_source_contracts(
    identity, contracts, 10000000,
  ).unwrap()
  assert_true(
    physical_equal(
      program_source_contract_identity(selected_contracts),
      identity,
    ),
  )
  assert_true(
    bind_program_source_contracts(
      identity,
      collect_source_contracts(other_context, caps).unwrap(),
      10000000,
    )
    is Err(ForeignContext),
  )
  // The same prepared Program now supplies both the operation coverage index
  // and incoming dependencies. No executed predecessor or receipt is invented.
  let profiles = operation_resolution_profiles(resolved)
  let incoming_limits : IncomingLimits = {
    max_work: 10000000,
    max_name_units: 10000,
    max_requirements: 3,
  }
  let incoming = collect_program_incoming(identity, incoming_limits).unwrap()
  assert_eq(program_incoming_count(incoming), 3)
  let first = program_identity_stage_at(identity, 0).unwrap()
  let second = program_identity_stage_at(identity, 1).unwrap()
  let mut success = 0
  let mut imports = 0
  for i in 0..<3 {
    let site = program_incoming_at(incoming, i).unwrap()
    assert_eq(site.stage, 1)
    assert_true(physical_equal(site.consumer, second))
    match site.requirement {
      Success(Completed, producer) => {
        success += 1
        assert_true(physical_equal(producer, first))
      }
      Result(name, producer, port) => {
        imports += 1
        assert_true(name == "rows" || name == "again")
        assert_true(physical_equal(producer, first))
        assert_true(
          physical_equal(
            @stage_results.input_stage(port),
            @stage_results.wiring_stage_at(wiring, 0).unwrap(),
          ),
        )
      }
      _ => fail("unexpected incoming dependency")
    }
  }
  assert_eq((success, imports), (1, 2))
  let linked = link_resolved_program_incoming(
    resolved, incoming, incoming_limits,
  ).unwrap()
  assert_true(physical_equal(incoming_links_resolutions(linked), resolved))
  let indexed = incoming_links_resolutions(linked)
  assert_true(
    physical_equal(operation_resolution_requirements(indexed), requirements),
  )
  assert_eq(operation_resolution_count(indexed), 0)
  assert_true(physical_equal(incoming_links_requirements(linked), incoming))
  let exact_incoming = {
    ..incoming_limits,
    max_work: incoming_links_work(linked),
  }
  assert_true(
    link_program_incoming(profiles, incoming, exact_incoming) is Ok(_),
  )
  assert_true(
    link_program_incoming(profiles, incoming, {
      ..exact_incoming,
      max_work: exact_incoming.max_work - 1,
    })
    is Err(BudgetExceeded),
  )
  assert_true(
    link_program_incoming(
      profiles,
      collect_program_incoming(again, incoming_limits).unwrap(),
      incoming_limits,
    )
    is Err(ForeignIdentity),
  )
}
