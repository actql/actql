///|
test "checked Client Result transformation orders before identity and evidence" {
  let (_, environment, effect_limits) = local_effect_export_fixture()
  let document =
    #|{"version":"actql/0.1","id":"client-result-transform","stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":3},{"id":1},{"id":2}]},"as":"selected"}],"results":{"ordered":{"from":"selected","fields":["id"],"order_by":[{"id":"asc"}]},"unchanged":{"from":"selected","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"source","result":"ordered"}},"original":{"from":{"stage":"source","result":"unchanged"}}}}
  let prepare = fn() {
    @publication_host.prepare_effect_free_client_program(
      document,
      Json,
      environment,
      None,
      effect_limits.program,
    ).unwrap()
  }
  let prepared = prepare()
  let run = @publication_host.open_prepared_source_free_client_run(prepared, {
    planning_work: 100000,
    attempts: 10,
    holdings: 10,
    transfer_bytes: 500000L,
    retained_bytes: 200000000L,
    execution_bytes: 268435456L,
  }).unwrap()
  let ledger = @strategy.captured_dag_ledger(run)
  let registry = search_registry()
  let limits = dispatch_test_limits()
  let sequence_limits : @lower.SequenceLimits = {
    max_steps: 100,
    max_rows: 100,
    max_cells: 10000,
    max_bindings: 100,
    max_name_bytes: 10000,
    expressions: {
      max_nodes: 10000,
      max_work: 100000,
      max_depth: 100,
      max_literal_nodes: 10000,
      max_literal_text_bytes: 10000,
    },
  }
  assert_true(
    @publication_host.issue_prepared_client_direct_values_result_root(
      prepared, 0, sequence_limits, 100000, 10000, 100,
    )
    is Err(RequiresResultTransformation),
  )
  assert_true(
    @publication_host.issue_prepared_client_direct_values_result_root(
      prepared, 1, sequence_limits, 100000, 10000, 100,
    )
    is Ok(_),
  )
  let generated = @publication_host.prepare_client_task_sequence(
    prepared,
    0,
    registered_relation_contracts(),
    [],
    sequence_limits,
    100000,
    10000,
  ).unwrap()
  let modules = @builtin.configure_compute_modules(
    @host_driver.open_dispatch_driver(run),
    registry,
    1,
    _ => @strategy.RunIssue::ForeignCandidate,
    with_local=Some(
      (
        @connector.capability_registration_at(registry, 0).unwrap(),
        {
          sequences: [generated],
          managed_providers: [],
          managed_capacity: limits.capacity,
          execution: limits.local_execution,
          measurement: limits.guards,
          max_work: limits.candidate_work,
        },
        _ => @strategy.RunIssue::ForeignCandidate,
        _ => @strategy.RunIssue::ForeignCandidate,
      ),
    ),
  ).unwrap()
  let installed = @builtin.configured_local_module(modules).unwrap()
  @local_driver.configure_local_retained_inputs(
    installed,
    {
      max_rows: 100,
      values: limits.local_execution.rows.input_values,
      wire: retained_attempt_wire_limits(),
      row: { max_bytes: 100, max_nodes: 20, max_depth: 4, max_text_bytes: 100, },
      max_batch_bytes: 64,
    },
    None,
  ).unwrap()
  let available = Ref(true)
  let (operations, completed) = run_local_managed_test_task(
    installed,
    run,
    0,
    [],
    [],
    1,
    available,
  )
  assert_eq(local_managed_test_rows(operations), [
    "{\"id\":3}", "{\"id\":1}", "{\"id\":2}",
  ])
  assert_true(@strategy.captured_task_completed(run, 0))
  assert_eq(@strategy.next_captured_task(run), None)
  let values : @execution.ValueLimits = {
    max_nodes: 1000,
    max_text_bytes: 10000,
    max_depth: 20,
    max_work: 10000,
  }
  let bridge = @execution.prepare_managed_publication_bridge(
    completed,
    (operations.material)().unwrap(),
    100,
    values,
    100,
    10000,
  ).unwrap()
  for row in local_managed_test_rows(operations) {
    @execution.append_managed_publication_bridge_wire(bridge, row, {
      max_bytes: 100,
      max_nodes: 20,
      max_depth: 4,
      max_text_bytes: 100,
    }).unwrap()
  }
  let output = @execution.finish_managed_publication_bridge(bridge).unwrap()
  let wire = row_wire_limits()
  let export_limits : @publication_host.PublicationOutputExportLimits = {
    max_result_fields: 10,
    max_result_mapping_work: 100,
    max_result_order_work: 100,
    max_result_workspace_entries: 100,
    max_rows: 100,
    values,
    payload_wire: wire,
    logical_wire: wire,
    schema: {
      max_fields: 10,
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 20,
    },
    max_batch_bytes: 64,
  }
  let foreign = @publication_host.prepare_client_result_transformation(
    prepare(),
    0,
    100000,
    10000,
    100,
  ).unwrap()
  assert_true(
    @publication_host.start_client_result_transformation(
      foreign, output, export_limits,
    )
    is Err(Output(ResultView(ForeignOccurrence))),
  )
  assert_true(
    @publication_host.prepare_client_result_transformation(
      prepared, 2, 100000, 10000, 100,
    )
    is Err(MissingResult),
  )
  let logical_ids = []
  for
    (index, expected) in [
      (0, "[{\"id\":1},{\"id\":2},{\"id\":3}]"),
      (1, "[{\"id\":3},{\"id\":1},{\"id\":2}]"),
    ] {
    let selected = @publication_host.prepare_client_result_transformation(
      prepared, index, 100000, 10000, 100,
    ).unwrap()
    assert_true(
      @publication_host.client_result_transformation_matches(
        selected, prepared, index,
      ),
    )
    assert_false(
      @publication_host.client_result_transformation_matches(
        selected,
        prepared,
        1 - index,
      ),
    )
    let preparation = @publication_host.start_client_result_transformation(
      selected, output, export_limits,
    ).unwrap()
    assert_true(preparation.finish() is Err(Output(NotFinished)))
    while true {
      let (done, used) = preparation.advance(1).unwrap()
      assert_true(used <= 1)
      if done {
        break
      }
    }
    let result = preparation.finish().unwrap()
    assert_true(preparation.finish() is Err(Output(Closed)))
    assert_true(result.ordering() is Err(InvalidState))
    let text = StringBuilder()
    while result.next().unwrap() is Some(chunk) {
      text.write_string(chunk)
    }
    text.write_string(result.finish().unwrap())
    assert_eq(text.to_string(), expected)
    assert_eq(result.result_fields().unwrap(), ["id"])
    assert_eq(result.row_count().unwrap(), 3)
    logical_ids.push(result.logical_relation_cid().unwrap())
    // These are test authority contexts, not live authorization or a compiled
    // Executable Plan. The exporter must bind evidence to the transformed view.
    let context = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    result
    .issue_result_evidence(
      context,
      [],
      context,
      context,
      context,
      100000,
      10000,
      100,
    )
    .unwrap()
    assert_true(
      @publication.validate_result_occurrence_ordering_evidence(
        result.definition().unwrap(),
        result.derivation().unwrap(),
        result.ordering().unwrap(),
        result.logical_relation_cid().unwrap(),
        result.result_schema_cid().unwrap(),
        context,
      )
      is Ok(_),
    )
    if index == 1 {
      assert_true(
        @publication.validate_result_occurrence_ordering_evidence(
          result.definition().unwrap(),
          result.derivation().unwrap(),
          result.ordering().unwrap(),
          logical_ids[0],
          result.result_schema_cid().unwrap(),
          context,
        )
        is Err(LogicalValueMismatch),
      )
    }
    result.cancel()
  }
  assert_true(logical_ids[0] != logical_ids[1])
  let selected = @publication_host.prepare_client_result_transformation(
    prepared, 0, 100000, 10000, 100,
  ).unwrap()
  let limited = @publication_host.start_client_result_transformation(
    selected,
    output,
    { ..export_limits, max_result_order_work: 0, },
  ).unwrap()
  assert_true(limited.advance(1000) is Err(Output(ResultView(Limit))))
  limited.cancel() |> ignore
  let cancelled = @publication_host.start_client_result_transformation(
    selected, output, export_limits,
  ).unwrap()
  assert_true(cancelled.cancel())
  assert_false(cancelled.cancel())
  assert_true(cancelled.advance(1) is Err(Output(Closed)))
  // C's captured export boundary must retain a separate Result borrow while
  // B's bounded transform is in flight. Equal content is not another owner.
  assert_true(
    @publication_host.start_captured_managed_result_transformation(
      foreign, run, 0, completed, bridge, output, export_limits,
    )
    is Err(ForeignSelection),
  )
  assert_true(
    @publication_host.start_captured_managed_result_transformation(
      selected, run, 1, completed, bridge, output, export_limits,
    )
    is Err(ForeignSelection),
  )
  let unrelated_bridge = @execution.prepare_managed_publication_bridge(
    completed,
    (operations.material)().unwrap(),
    100,
    values,
    100,
    10000,
  ).unwrap()
  assert_true(
    @publication_host.start_captured_managed_result_transformation(
      selected, run, 0, completed, unrelated_bridge, output, export_limits,
    )
    is Err(ForeignSelection),
  )
  @execution.close_managed_publication_bridge(unrelated_bridge)
  let released_result = @publication_host.start_captured_managed_result_transformation(
    selected, run, 0, completed, bridge, output, export_limits,
  )
  let released = match released_result {
    Ok(value) => value
    Err(ForeignSelection) => abort("captured selection mismatch")
    Err(Retain(NotReady)) => abort("capture retain not ready")
    Err(Retain(ForeignCandidate)) => abort("capture retain foreign")
    Err(Retain(_)) => abort("capture retain failed")
    Err(Transform(_)) => abort("capture transform failed")
    Err(InvalidState) => abort("capture invalid state")
  }
  released.cancel()
  released.cancel()
  assert_true(released.advance(1) is Err(InvalidState))
  let held = @publication_host.start_captured_managed_result_transformation(
    selected, run, 0, completed, bridge, output, export_limits,
  ).unwrap()
  assert_true(held.finish() is Err(Transform(Output(NotFinished))))
  @strategy.close_captured_task_output(run, 0)
  while true {
    let (done, used) = held.advance(1).unwrap()
    assert_true(used <= 1)
    if done {
      break
    }
  }
  let exported = held.finish().unwrap()
  // Responsibility moved to the export; cancelling preparation must not
  // revoke it. Repeated finish cannot duplicate that responsibility.
  held.cancel()
  assert_true(held.finish() is Err(InvalidState))
  let transformed = StringBuilder()
  while exported.next().unwrap() is Some(chunk) {
    transformed.write_string(chunk)
  }
  transformed.write_string(exported.finish().unwrap())
  assert_eq(transformed.to_string(), "[{\"id\":1},{\"id\":2},{\"id\":3}]")
  exported.cancel()
  @execution.close_managed_publication_bridge(bridge)
  @strategy.close_captured_task_output(run, 0)
  let usage = @resources.ledger_usage(ledger)
  assert_eq(usage.reserved_execution_bytes, 0L)
}
