///|
test "mixed installed Effect capacities retain both original requirements and resource contributions" {
  let environment = @environment.read(
    @utf8.encode(mixed_installed_environment),
    mixed_installed_environment_cid,
    { max_bytes: 100000, max_nodes: 10000, max_depth: 100, max_members: 1000, },
  ).unwrap()
  let (_, _, original) = local_effect_export_fixture(table=true)
  // This independently authored control has three Units and two Sources.
  // Its input parser limits do not change the product's installed limits.
  let limits = {
    ..original,
    program: {
      ..original.program,
      max_tasks: 8,
      checking: {
        ..original.program.checking,
        input: { ..original.program.checking.input, max_stages: 3, },
        compilation: {
          ..original.program.checking.compilation,
          structure: {
            ..original.program.checking.compilation.structure,
            stages: 3,
          },
        },
      },
    },
  }
  let prepared = @publication_host.prepare_client_effect_computation(
    mixed_installed_program,
    Json,
    @program_check.checking_environment(
      environment,
      { text_time: false, veca: false, },
      { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    ),
    None,
    [],
    limits,
  ).unwrap()
  let (registry, values, fragment, ordered) = acquired_serialization_contracts()
  let capacities = Array::makei(2, task => {
    let declaration = @row_host.restore_relation_row_declaration(
      if task == 0 {
        "left"
      } else {
        "right"
      },
      "fixture",
      "fixture/0.1",
      mixed_installed_declaration,
      None,
    ).unwrap()
    let requirement = @client_local_host.prepare_effect_local_query_requirement(
      prepared, task, 0, registry, values, fragment, ordered,
    ).unwrap()
    let acquisition = @row_host.prepare_row_acquisition(
      declaration, requirement, original_row_query_contract_fixture, original_row_evidence_contract_fixture,
    ).unwrap()
    @client_local_host.installed_row_capture_capacity(acquisition).unwrap()
  })
  let prepare = capacities => {
    @client_local_host.prepare_multi_captured_effect_installed_ledger(
      prepared,
      capacities,
      [4096L, 8192L],
      [1024L, 2048L],
      registry,
      values,
      fragment,
      ordered,
    )
  }
  let ledger = prepare(capacities).unwrap()
  let budget = @resources.ledger_admission_limits(ledger)
  let left = @client_local_host.installed_capture_capacity_values(capacities[0])
  let right = @client_local_host.installed_capture_capacity_values(
    capacities[1],
  )
  // Both still-owned Source captures are additional to the existing retained
  // Compute allowance; equal row schemas do not merge the original Sources.
  assert_true(budget.retained_bytes >= left[0] + right[0] + 200000000L)
  assert_true(budget.transfer_bytes >= 4096L + 8192L)
  assert_true(budget.execution_bytes >= left[1] + 1024L)
  assert_true(budget.execution_bytes >= right[1] + 2048L)
  assert_true(prepare([capacities[1], capacities[0]]) is None)
  assert_true(prepare([capacities[0], capacities[0]]) is None)
  assert_true(prepare([capacities[0]]) is None)
  assert_true(
    @client_local_host.prepare_multi_captured_effect_installed_ledger(
      prepared,
      capacities,
      [4096L, -1L],
      [1024L, 2048L],
      registry,
      values,
      fragment,
      ordered,
    )
    is None,
  )
  assert_true(
    @client_local_host.prepare_multi_captured_effect_installed_ledger(
      prepared,
      capacities,
      [4096L, 8192L],
      [1024L],
      registry,
      values,
      fragment,
      ordered,
    )
    is None,
  )
  let usage = @resources.ledger_usage(ledger)
  assert_eq(usage.attempts, 0)
  assert_eq(usage.held_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_transfer_bytes, 0L)
}
