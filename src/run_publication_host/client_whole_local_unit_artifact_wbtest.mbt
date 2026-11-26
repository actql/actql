///|
test "ordinary Whole Local Unit issues its complete Manifest from the actual managed export" {
  let prepared = client_composed_whole_sibling_test_program()
  let occurrences = prepared_client_composed_infer_occurrences(prepared).unwrap()
  let plans = occurrences.map(occurrence => {
    issue_prepared_client_composed_infer_plan_graph(
      occurrence,
      client_infer_graph_test_execution(prepared, occurrence=Some(occurrence)),
      "sha256:" + "b".repeat(64),
      "sha256:" + "c".repeat(64),
      run_materials_limits().sequence,
      100000,
      10000,
      100,
      include_results=false,
    ).unwrap()
  })
  let compilation = issue_prepared_client_multi_infer_compilation(
    prepared,
    plans,
    run_materials_manifests(),
    run_materials_limits().sequence,
    1000,
    1000,
    1000000,
    100000,
    100,
  ).unwrap()
  let compiled = issue_client_task_compiled_run(
    prepared,
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = issue_client_compiled_run_definition(
    compiled, "fixture", "whole-ordinary-unit", "2026-11-12T00:00:00.000Z", "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let request = prepare_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "whole-unit",
    "sha256:" + "b".repeat(64),
  ).unwrap()
  let left = mixed_whole_infer_capture(prepared, 0, Ref(true))
  let right = mixed_whole_infer_capture(prepared, 1, Ref(true))
  let captures = [left.0, right.0]
  let sources = admit_client_infer_composed_whole_sources(
    occurrences[0],
    captures,
    [left.1, right.1],
    [left.2, right.2],
    [left.3, right.3],
    [left.4, right.4],
    client_request_authority_scope_cid(request),
    "2026-11-12T00:00:00.000Z",
    "2026-11-12T00:00:02.000Z",
  ).unwrap()
  let ledger = @resources.create_ledger({
    planning_work: 1000000,
    attempts: 32,
    holdings: 32,
    transfer_bytes: 2000000L,
    retained_bytes: 200000000L,
    execution_bytes: 268435456L,
  }).unwrap()
  let bootstrap = @resources.reserve_capacity(ledger, 1000000L, 1000000L).unwrap()
  let scope = begin_client_model_read_scope(
    compiled,
    definition,
    plans[0],
    ledger,
    bootstrap,
    32,
    32,
    8,
  ).unwrap()
  let graph = @strategy.prepare_source_inputs_dag(prepared.graph, [
    left.2,
    right.2,
  ]).unwrap()
  let run = @strategy.open_source_inputs_dag(graph, captures, ledger).unwrap()
  let fragment = Some(product_test_fragment_wire())
  let ordered = Some(compiler_registered_ordered_wire())
  assert_true(client_infer_composed_whole_sources_match_run(sources, run))
  assert_false(
    client_infer_composed_whole_sources_match_run(
      sources,
      run,
      after_completion=true,
    ),
  )
  let contracts = @local_query_time.prepare_installed_sequence_contracts(
    compiler_registered_body_wire(),
    compiler_registered_values_wire(),
    fragment,
    ordered,
  ).unwrap()
  let sequences = @local_query_time.prepare_client_local_sequences(
    prepared,
    contracts,
    compiler_registered_values_wire(),
    fragment,
    ordered,
  ).unwrap()
  assert_eq(sequences.length(), @strategy.graph_task_count(graph))
  let registry = @connector.prepare_capability_registry(
    [{ name: "local", acquisition: false, fixed_compute: true, effect: false, }],
    1,
    100,
  ).unwrap()
  let registration = @connector.capability_registration_at(registry, 0).unwrap()
  let execution = string_try_number_execution_limits()
  let wire : @execution.RowWireLimits = {
    max_columns: 10,
    max_order_work: 10000,
    max_bytes: 20000,
    max_nodes: 10000,
    max_depth: 20,
  }
  let row : @execution.RetainedRowDecodeLimits = {
    max_bytes: 1024,
    max_nodes: 32,
    max_depth: 6,
    max_text_bytes: 1024,
  }
  let installed = @local_driver.configure_local_compute(
    @host_driver.open_dispatch_driver(run),
    registry,
    registration,
    {
      sequences,
      managed_providers: [],
      managed_capacity: {
        contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
        max_rows: 100,
        max_value_bytes: 10000,
        common_fragment: None,
      },
      execution,
      measurement: {
        max_work: 10000,
        max_bytes: 20000,
        max_nodes: 10000,
        max_depth: 20,
      },
      max_work: 100000,
    },
  ).unwrap()
  @local_driver.configure_local_retained_inputs(
    installed,
    {
      max_rows: 100,
      values: execution.rows.input_values,
      wire,
      row,
      max_batch_bytes: 256,
    },
    None,
  ).unwrap()
  let owner = @strategy.graph_task_owner(graph, 0).unwrap()
  let dispatch = @local_driver.prepare_local_managed_dispatch_with_outputs(
      installed,
      [
        @local_driver.local_managed_supplied_relation_input(),
        @local_driver.local_managed_supplied_relation_input(),
      ],
      @execution.process_managed_obligations(owner),
      0L,
    )
    .unwrap()
    .unwrap()
  @strategy.select_captured_managed_registration(run, 0, registration).unwrap()
  let operations = @local_driver.start_local_managed_dispatch_node(dispatch).unwrap()
  (operations.execute)().unwrap()
  let producer_available = Ref(true)
  (operations.prepare_finalization)(0, operations.storage_bytes, () => {
    producer_available.val
  }).unwrap()
  for _ in 0..<100 {
    if (operations.advance_finalization)(64).unwrap().complete {
      break
    }
  }
  (operations.settle)().unwrap()
  let completed = (operations.complete)(0, operations.storage_bytes, () => {
    producer_available.val
  }).unwrap()
  assert_eq((operations.output_rows)(), 1)
  let results = @strategy.pin_captured_completed_unit_results(run, 0, 1, 2).unwrap()
  assert_true(
    client_model_read_scope_live(scope, compiled, definition, plans[0]),
  )
  assert_false(client_infer_composed_whole_sources_match_run(sources, run))
  assert_true(
    client_infer_composed_whole_sources_match_run(
      sources,
      run,
      after_completion=true,
    ),
  )
  assert_true(
    client_whole_local_unit_owners_match(
      scope, definition, run, 0, results, sources,
    ),
  )
  let invocation = match
    prepare_client_whole_local_unit_invocation(
      scope,
      definition,
      request,
      run,
      results,
      sources,
      0,
      65536,
      8192,
      64,
      count => count == 2,
      (label, geometry) => label == "local_computation" && geometry.bytes > 0,
    ) {
    Ok(value) => value
    Err(issue) => fail("Whole producer Invocation: " + @debug.to_string(issue))
  }
  assert_true(
    client_whole_local_unit_invocation_matches(
      invocation, compiled, definition, request, run,
    ),
  )
  let retention = @publication.seal_publication_contract(
    "result_retention_policy",
    "{\"version\":\"actql-result-retention-policy/0.1\",\"retention_contract_cid\":\"sha256:" +
    "8".repeat(64) +
    "\",\"effective_data_policy_cid\":\"sha256:" +
    "7".repeat(64) +
    "\",\"available_until\":\"2099-01-01T00:00:00.000Z\",\"delete_by\":\"2099-01-02T00:00:00.000Z\",\"extension_ceiling_at\":\"2099-01-03T00:00:00.000Z\",\"metadata_retention_policy_cid\":\"sha256:" +
    "9".repeat(64) +
    "\",\"metadata_delete_by\":\"2099-01-04T00:00:00.000Z\",\"clock_contract_cid\":\"sha256:" +
    "a".repeat(64) +
    "\"}",
    65536,
    8192,
    64,
  ).unwrap()
  let unit = match
    prepare_client_whole_local_unit_publication(
      invocation,
      retention,
      65536,
      8192,
      64,
      count => count == 2,
      (_, geometry) => geometry.bytes > 0,
    ) {
    Ok(value) => value
    Err(issue) =>
      fail("Whole producer Source metadata: " + @debug.to_string(issue))
  }
  let borrow = @strategy.captured_completed_unit_result_at(results, 0).unwrap()
  let bridge = @execution.prepare_managed_publication_bridge(
    completed,
    (operations.material)().unwrap(),
    10,
    execution.rows.input_values,
    100,
    10000,
  ).unwrap()
  let original_row = (operations.output_row)(0).unwrap()
  @execution.append_managed_publication_bridge_wire(bridge, original_row, row).unwrap()
  let output = @execution.finish_managed_publication_bridge(bridge).unwrap()
  let preparation = @execution.start_completed_result_relation_export(
    output,
    @strategy.captured_any_result_borrow_occurrence(borrow),
    {
      max_fields: 10,
      max_mapping_work: 100,
      max_order_work: 100,
      max_workspace_entries: 100,
    },
    10,
    execution.rows.input_values,
    wire,
    wire,
    { max_fields: 10, max_bytes: 10000, max_nodes: 1000, max_depth: 20, },
    256,
  ).unwrap()
  for _ in 0..<100 {
    if @execution.advance_completed_result_relation_export(preparation, 64).unwrap().0 {
      break
    }
  }
  let stream = @execution.finish_completed_result_relation_export_preparation(
    preparation,
  ).unwrap()
  assert_eq(
    @execution.next_completed_output_export(stream).unwrap(),
    Some("[{\"amount\":7,\"id\":1}"),
  )
  assert_true(@execution.next_completed_output_export(stream).unwrap() is None)
  let (receipt, tail) = @execution.finish_completed_relation_export(stream).unwrap()
  assert_eq(tail, "]")
  let handoff = @strategy.prepare_captured_completed_unit_result_handoff(
    results, 0, completed, bridge, preparation, receipt,
  ).unwrap()
  let unexpected_funding = Ref(0)
  assert_true(
    issue_client_whole_local_result_artifact(
      unit,
      1,
      handoff,
      100000,
      65536,
      8192,
      64,
      () => {
        unexpected_funding.val += 1
        false
      },
      (_, _) => false,
    )
    is Err(ForeignExport),
  )
  let artifact = issue_client_whole_local_result_artifact(
    unit,
    0,
    handoff,
    100000,
    65536,
    8192,
    64,
    () => true,
    (_, geometry) => geometry.bytes > 0,
  ).unwrap()
  assert_true(physical_equal(artifact.export_receipt, receipt))
  let (checked_port, _) = @strategy.captured_completed_unit_result_export_original(
    handoff, results, 0,
  ).unwrap()
  let producer_policy = @checked.prepare_local_result_source_policy(
    @strategy.graph_program(prepared.graph),
    0,
    checked_port,
    100000,
    65536,
    8192,
    64,
  ).unwrap()
  assert_true(
    @publication.publication_contract_json(artifact.artifact).contains(
      "\"effective_data_policy_cid\":\"" + producer_policy.cid + "\"",
    ),
  )
  assert_true(
    prepared_client_publication_data_policy_cid(prepared) !=
    Some(producer_policy.cid),
  )
  assert_true(
    @publication.result_retention_bounds_equal(artifact.retention, retention),
  )
  assert_true(
    @publication.publication_contract_identity(artifact.retention) !=
    @publication.publication_contract_identity(retention),
  )
  assert_true(
    issue_client_whole_local_result_manifest(
      unit,
      [],
      65536,
      8192,
      64,
      _ => {
        unexpected_funding.val += 1
        false
      },
      _ => false,
    )
    is Err(IncompleteResults),
  )
  assert_eq(unexpected_funding.val, 0)
  let manifest = issue_client_whole_local_result_manifest(
    unit,
    [artifact],
    65536,
    8192,
    64,
    count => count == 1,
    geometry => geometry.bytes > 0,
  ).unwrap()
  assert_true(client_whole_local_result_manifest_matches(manifest, artifact))
  assert_true(
    client_whole_local_result_manifest_json(manifest).contains(
      "\"rows\":\"" + client_whole_local_result_artifact_cid(artifact) + "\"",
    ),
  )
  let manifest_preimage = "{\"local_invocation_cid\":\"" +
    invocation.cid +
    "\",\"results\":{\"rows\":\"" +
    client_whole_local_result_artifact_cid(artifact) +
    "\"},\"unit_definition_cid\":\"" +
    invocation.unit_definition_cid +
    "\",\"version\":\"actql-local-result-manifest/0.1\"}"
  assert_eq(
    client_whole_local_result_manifest_cid(manifest),
    "sha256:" + @sha.text_hex(manifest_preimage).unwrap(),
  )
  let (original_port, _) = @strategy.captured_completed_unit_result_export_original(
    handoff, results, 0,
  ).unwrap()
  let first_edge = client_infer_whole_result_input_edge(
    occurrences[0],
    0,
    run,
    original_port,
  ).unwrap()
  let second_edge = client_infer_whole_result_input_edge(
    occurrences[1],
    0,
    run,
    original_port,
  ).unwrap()
  assert_true(first_edge != second_edge)
  let run_graph = @strategy.captured_dag_graph(run)
  for index, edge in [first_edge, second_edge] {
    assert_eq(
      @strategy.data_edge_consumer(
        @strategy.graph_data_at(run_graph, edge).unwrap(),
      ),
      occurrences[index].task,
    )
    assert_true(
      client_infer_whole_result_input_edge(
        occurrences[index],
        1,
        run,
        original_port,
      )
      is None,
    )
  }
  let unrelated = @strategy.graph_result_occurrence(prepared.graph, 0).unwrap()
  let wrong_port = @execution.managed_result_occurrence_port(unrelated)
  assert_true(
    client_infer_whole_result_input_edge(occurrences[0], 0, run, wrong_port)
    is None,
  )
  let selected_source = @strategy.captured_completed_unit_result_input_original(
    handoff,
  ).unwrap()
  let different_borrow = @execution.restrict_completed_output(selected_source, () => {
    true
  })
  let mut previous_artifact = None
  for index, occurrence in occurrences {
    let selected_sources = if index == 0 {
      sources
    } else {
      bind_client_infer_composed_whole_sibling(sources, occurrence).unwrap()
    }
    let prefix = @local_query_time.prepare_client_composed_infer_prefix(
      prepared,
      occurrence,
      contracts,
      compiler_registered_values_wire(),
      fragment_body=fragment,
      ordered_body=ordered,
    ).unwrap()
    for exact in [true, false] {
      let bound = @execution.bind_completed_input(
        occurrence.preparation,
        0,
        owner,
        if exact {
          selected_source
        } else {
          different_borrow
        },
      ).unwrap()
      let read = @execution.prepare_producer_read(
        occurrence.preparation,
        bound,
        10000,
        20000,
      ).unwrap()
      let child = @local_query_time.start_client_composed_infer_input(
        occurrence,
        prefix,
        [@local.managed_provider_relation_input(read)],
        execution,
        { max_work: 100000, max_bytes: 20000, max_nodes: 10000, max_depth: 20, },
        {
          max_items: 100,
          max_work: 100000,
          max_frames: 100,
          max_workspace_slots: 10000,
          values: { max_nodes: 10000, max_depth: 64, max_text_bytes: 20000, },
          logical: {
            max_input_rows: 100L,
            max_value_bytes: 20000L,
            max_live_value_bytes: 100000L,
            max_work: 100000L,
          },
        },
      ).unwrap()
      for _ in 0..<1000 {
        match @local_query_time.advance_client_infer_input(child, 32).unwrap() {
          @local_query_time.Complete(_, ..) => break
          @local_query_time.Continue(..) => ()
          _ => fail("original Whole Model prefix")
        }
      }
      let input = @local_query_time.client_infer_completed_input(child).unwrap()
      let selected = @local_query_time.client_infer_completed_whole_result_artifact_input(
        child,
        occurrence,
        plans[index],
        0,
        artifact,
        manifest,
      )
      if exact {
        let original = selected.unwrap()
        assert_eq(
          client_infer_result_artifact_input_binding(
            original, occurrence, input,
          ).unwrap(),
          ("rows", client_whole_local_result_artifact_cid(artifact)),
        )
        assert_true(
          client_infer_result_artifact_input_binding(
            original,
            occurrences[1 - index],
            input,
          )
          is Err(ForeignInput),
        )
        let scan = @execution.start_completed_relation_identity_scan(
          input,
          10,
          execution.rows.input_values,
          wire,
          wire,
          { max_fields: 10, max_bytes: 10000, max_nodes: 1000, max_depth: 20, },
          1000000,
          100000,
          incremental_metadata=true,
        ).unwrap()
        for _ in 0..<1000 {
          if @execution.advance_completed_relation_identity_scan(scan, 32).unwrap().0 {
            break
          }
        }
        let model_receipt = @execution.finish_completed_relation_identity_scan(
          scan,
        ).unwrap()
        assert_true(
          issue_client_infer_occurrence_call_scope(
            occurrence,
            plans[index],
            input,
            model_receipt,
            100000,
            10000,
            100,
            result_inputs=[original],
          )
          is Err(ForeignInput),
        )
        let call_scope = issue_client_infer_occurrence_call_scope(
          occurrence,
          plans[index],
          input,
          model_receipt,
          100000,
          10000,
          100,
          sources=Some(selected_sources),
          result_inputs=[original],
        ).unwrap()
        assert_eq(call_scope.sources.length(), 2)
        for source_index in 0..<2 {
          assert_true(
            physical_equal(
              call_scope.sources[source_index],
              sources.inputs[source_index].observation,
            ),
          )
        }
        let snapshot = client_infer_call_scope_snapshot(call_scope).unwrap()
        let saved = read_client_infer_saved_call_scope(
          compiled,
          definition,
          occurrence,
          plans[index],
          snapshot,
          client_request_authority_scope_cid(request),
          () => true,
        ).unwrap()
        assert_eq(saved.result_inputs, [
          (
            "rows",
            client_whole_local_result_artifact_cid(artifact),
            manifest.cid,
          ),
        ])
        let snapshot_value = parse_plan_identity_value(
          snapshot, 1000000, 100000, 100,
        ).unwrap()
        let empty_sources = parse_plan_identity_value("[]", 10, 10, 10).unwrap()
        let without_sources = @canonical.object_with_replaced_fields(
          snapshot_value,
          [("sources", empty_sources)],
        ).unwrap()
        assert_true(
          read_client_infer_saved_call_scope(
            compiled,
            definition,
            occurrence,
            plans[index],
            @canonical.stringify_value(without_sources, 1000000, 100000, 100),
            client_request_authority_scope_cid(request),
            () => true,
          )
          is Err(ForeignInput),
        )
        let call_artifact = @publication.run_evidence_value_identity(
          call_scope.artifact,
        )
        if previous_artifact is Some(previous) {
          assert_true(call_artifact != previous)
        }
        previous_artifact = Some(call_artifact)
        @execution.cancel_completed_relation_export_receipt(model_receipt)
      } else {
        assert_true(selected is Err(ForeignInput))
      }
      assert_true(@local_query_time.cleanup_client_infer_input(child).unwrap())
    }
  }
  @execution.cancel_completed_relation_export_receipt(receipt)
  assert_false(client_whole_local_result_manifest_matches(manifest, artifact))
  assert_true(@strategy.release_captured_completed_unit_results(results))
  @execution.close_managed_publication_bridge(bridge)
  producer_available.val = false
  (operations.close)()
  @strategy.stop_captured_dag(run)
  @strategy.close_captured_task_output(run, 0)
  @strategy.refresh_captured_retention(run)
  assert_true((operations.execution_stopped)())
  assert_true((operations.cleanup_refresh)())
  assert_true(
    finish_client_model_read_scope(scope, compiled, definition, plans[0], true).unwrap(),
  )
  let settled_usage = @resources.ledger_usage(ledger)
  assert_eq(settled_usage.held_bytes, 0L)
  assert_eq(settled_usage.reserved_execution_bytes, 0L)
  assert_eq(settled_usage.reserved_retention_bytes, 0L)
}
