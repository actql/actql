///|
test "ordinary Whole Local Unit issues its complete Manifest from the actual managed export" {
  let prepared = client_composed_whole_sibling_test_program(
    project_second_model=true,
  )
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
  let (_, current_read) = @strategy.retain_captured_completed_unit_result_input(
    handoff, first_edge, 10000, 20000,
  ).unwrap()
  let reader_original = prepare_client_infer_whole_result_reader(
    occurrences[0],
    0,
    artifact,
    manifest,
    current_read,
  ).unwrap()
  assert_true(client_infer_whole_result_reader_retained(reader_original))
  assert_true(
    client_infer_whole_result_reader_matches(
      occurrences[0],
      0,
      artifact,
      manifest,
      current_read,
    ),
  )
  assert_false(
    client_infer_whole_result_reader_matches(
      occurrences[1],
      0,
      artifact,
      manifest,
      current_read,
    ),
  )
  assert_false(
    client_infer_whole_result_reader_matches(
      occurrences[0],
      0,
      { ..artifact, },
      manifest,
      current_read,
    ),
  )
  let rebound = @execution.rebind_producer_representation(
    current_read, selected_source,
  ).unwrap()
  assert_true(@execution.producer_read_same_binding(current_read, rebound))
  assert_false(
    client_infer_whole_result_reader_matches(
      occurrences[0],
      0,
      artifact,
      manifest,
      rebound,
    ),
  )
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
    for (staged, exact) in [(true, true), (false, true), (false, false)] {
      if index != 0 && staged {
        continue
      }
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
      let read = if staged {
        current_read
      } else {
        @execution.prepare_producer_read(
          occurrence.preparation,
          bound,
          10000,
          20000,
        ).unwrap()
      }
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
      let mut prepared_rows = None
      for _ in 0..<1000 {
        match @local_query_time.advance_client_infer_input(child, 32).unwrap() {
          @local_query_time.Complete(rows, ..) => {
            prepared_rows = Some(rows)
            break
          }
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
        reader=if index == 0 { Some(reader_original) } else { None },
      )
      if index == 0 && exact && !staged {
        assert_true(selected is Err(ForeignInput))
        assert_true(
          @local_query_time.cleanup_client_infer_input(child).unwrap(),
        )
        continue
      }
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
        assert_eq(
          client_infer_call_scope_matches_whole_result_reader(
            call_scope, reader_original,
          ),
          staged,
        )
        if staged {
          call_scope.result_inputs[0] = { ..original, }
          assert_false(client_infer_result_input_inventory_current(call_scope))
          assert_false(
            client_infer_call_scope_matches_whole_result_reader(
              call_scope, reader_original,
            ),
          )
          call_scope.result_inputs[0] = original
        }
        let suffix = @local_query_time.prepare_client_composed_infer_suffix(
          prepared,
          occurrence,
          contracts,
          compiler_registered_values_wire(),
          fragment_body=fragment,
          ordered_body=ordered,
        )
        assert_eq(suffix is Some(_), index == 1)
        whole_model_recorded_outcome_control(
          compiled,
          definition,
          call_scope,
          prepared_rows.unwrap(),
          sequences[occurrence.task],
          input,
          suffix,
          model_receipt,
          execution,
          wire,
        )
        assert_eq(call_scope.sources.length(), 2)
        for source_index in 0..<2 {
          assert_true(
            physical_equal(
              call_scope.sources[source_index],
              sources.inputs[source_index].observation,
            ),
          )
        }
        let program = @strategy.graph_program(prepared.graph)
        let observes = issue_original_scope_result_import_observations(
          program,
          call_scope,
          WholeScope(run, request, definition),
          65536,
          8192,
          64,
          before_body=Some((label, geometry) => {
            label == "result_import_observation" && geometry.bytes > 0
          }),
        ).unwrap()
        assert_eq(observes.length(), 1)
        assert_true(physical_equal(observes[0].input, original))
        let derived = client_whole_model_import_relations(
          observes,
          65536,
          8192,
          64,
          (label, shape) => label == "acquisition_relation" && shape.bytes > 0,
        ).unwrap()
        assert_eq(derived.length(), 1)
        assert_true(physical_equal(derived[0].0, artifact.scope.unwrap()))
        let relation = @publication.publication_contract_json(derived[0].1)
        assert_true(relation.contains("\"kind\":\"derivation\""))
        assert_true(relation.contains("\"actual_row_count\":1"))
        assert_true(
          relation.contains(
            "\"effective_data_policy_cid\":\"" + producer_policy.cid + "\"",
          ),
        )
        assert_true(
          relation.contains(
            "\"effective_retention_policy_cid\":\"" +
            @publication.publication_contract_identity(artifact.retention) +
            "\"",
          ),
        )
        let copied = {
          ..original,
          original: Whole({ ..artifact, }, manifest, None),
        }
        assert_true(
          client_whole_model_import_relations(
            [{ ..observes[0], input: copied, }],
            65536,
            8192,
            64,
            (_, _) => false,
          )
          is Err(Invocation(ForeignResultImport)),
        )
        fn modeled_policy(unit : Int) raise {
          let declared = @checked.unit_publication_at(program, unit, 0).unwrap()
          let selected = @context.publication_row_limit_result(
            @checked.publication_selection(declared),
          )
          @checked.prepare_local_result_source_policy(
            program,
            unit,
            selected.port,
            100000,
            65536,
            8192,
            64,
          ).unwrap()
        }
        let policy = modeled_policy(occurrence.stage)
        assert_eq(
          client_whole_local_model_result_policy(
            call_scope, selected_sources, observes, policy, program,
          ).unwrap(),
          (policy.cid, true),
        )
        assert_true(
          client_whole_local_model_result_policy(
            call_scope,
            selected_sources,
            [],
            policy,
            program,
          )
          is Err(ForeignDefinition),
        )
        assert_true(
          client_whole_local_model_result_policy(
            call_scope,
            selected_sources,
            observes,
            modeled_policy(occurrences[1 - index].stage),
            program,
          )
          is Err(ForeignDefinition),
        )
        let preimage = "{\"consumer_unit_definition_cid\":\"" +
          call_scope.unit_definition_cid +
          "\",\"import_interface_cid\":\"" +
          original.interface.cid +
          "\",\"input_name\":\"rows\",\"producer_local_manifest_cid\":\"" +
          manifest.cid +
          "\",\"result_artifact_cid\":\"" +
          client_whole_local_result_artifact_cid(artifact) +
          "\",\"version\":\"actql-result-import-observation/0.1\"}"
        assert_eq(observes[0].cid, "sha256:" + @sha.text_hex(preimage).unwrap())
        assert_eq(
          observes[0].wire,
          preimage.replace(
            old=",\"version\":",
            new=",\"self_cid\":\"" + observes[0].cid + "\",\"version\":",
          ),
        )
        let funding = Ref(0)
        let equal_foreign = prepare_client_request_identity(
          prepared,
          "sha256:" + "a".repeat(64),
          "whole-unit",
          "sha256:" + "b".repeat(64),
        ).unwrap()
        assert_eq(equal_foreign, request)
        assert_true(
          issue_original_scope_result_import_observations(
            program,
            call_scope,
            WholeScope(run, equal_foreign, definition),
            65536,
            8192,
            64,
            before_body=Some((_, _) => {
              funding.val += 1
              true
            }),
          )
          is Err(ForeignResultImport),
        )
        assert_eq(funding.val, 0)
        assert_true(
          issue_original_scope_result_import_observations(
            program,
            call_scope,
            WholeScope(run, request, definition),
            65536,
            8192,
            64,
            before_body=Some((_, _) => {
              funding.val += 1
              call_scope.result_inputs.clear()
              true
            }),
          )
          is Err(ForeignResultImport),
        )
        assert_eq(funding.val, 1)
        call_scope.result_inputs.push(original)
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
  assert_false(client_infer_whole_result_reader_retained(reader_original))
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

///|
// The fixture uses real nominal typed completions at the checked Model port
// with explicitly admitted empty rows. It exercises the lower Read/Outcome
// handoff and receipt controls without invoking a provider.
fn whole_model_recorded_outcome_control(
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  scope : ClientInferCallScope,
  rows : @execution.PreparedInferRows,
  sequence : @execution.GeneratedSequence,
  input : @execution.CompletedOutput,
  suffix : @execution.GeneratedSequence?,
  input_receipt : @execution.CompletedRelationExportReceipt,
  execution : @execution.SequenceExecutionLimits,
  wire : @execution.RowWireLimits,
) -> Unit raise {
  let values = execution.rows.input_values
  let plan = scope.plan
  let occurrence = plan.occurrence
  let target = @pipeline.Step(occurrence.step)
  let step = @execution.select_generated_sequence_step(
    sequence,
    occurrence.step,
  ).unwrap()
  fn prepare_materialization() raise {
    let admitted = @execution.prepare_admitted_output(
      occurrence.preparation,
      target,
      10,
      values,
    ).unwrap()
    let materialization = @execution.start_admitted_output_preparation(
      admitted,
      0,
      10000,
      10000,
      (_, _) => None,
    ).unwrap()
    assert_true(
      @execution.advance_admitted_output_preparation(materialization, 1000).unwrap()
      is @execution.AdmittedOutputComplete(_, ..),
    )
    materialization
  }
  let materialization = prepare_materialization()
  let other_materialization = prepare_materialization()
  let live = Ref(true)
  let completion = @execution.generated_completion_preparation(step)
  let (independent, foreign_issuer) = @execution.prepare_infer_outcome_handoff(
    rows,
  )
  let foreign_port = @execution.prepare_bound_infer_outcome_port(
    foreign_issuer,
    completion,
    rows,
    other_materialization,
    () => live.val,
  ).unwrap()
  let foreign = @execution.complete_bound_infer_outcome_port(
    foreign_port, independent,
  ).unwrap()
  assert_true(scope.custody is PendingWholeOutcome)
  let terminal = claim_original_whole_model_terminal(scope).unwrap().unwrap()
  assert_eq(
    terminal.step,
    if suffix is Some(_) {
      occurrence.step + 1
    } else {
      occurrence.step
    },
  )
  assert_true(claim_original_whole_model_terminal(scope) is Err(ForeignInput))
  assert_false(
    record_original_whole_model_terminal(terminal, foreign, foreign, () => true),
  )
  assert_false(client_whole_model_outcome_matches(scope, input_receipt))
  let (read_scope, _, consumer) = client_resource_park_test_scope(
    compiled, definition, plan,
  )
  enter_client_model_read_consumer(consumer, compiled, definition, plan, 7L, 5L).unwrap()
  let (ledger, capacity, original) = handoff_original_provider_input_capacity(
    consumer, compiled, definition, plan, scope, rows, 7L, 5L,
  ).unwrap()
  let (owner, issuer) = original.unwrap()
  let usage = @resources.ledger_usage(ledger)
  assert_true(
    handoff_original_provider_input_capacity(
      consumer, compiled, definition, plan, scope, rows, 7L, 5L,
    )
    is Err(ForeignInput),
  )
  assert_eq(@resources.ledger_usage(ledger), usage)
  assert_true(scope.custody is ArmedWholeOutcome)
  assert_true(
    complete_original_whole_model_outcome(owner, foreign_port) is None,
  )
  assert_true(scope.custody is ArmedWholeOutcome)
  assert_eq(@resources.ledger_usage(ledger), usage)
  let selected : Ref[@execution.InferOutcomePort?] = Ref(None)
  let reentered : Ref[Bool?] = Ref(None)
  let port = @execution.prepare_bound_infer_outcome_port(
    issuer,
    completion,
    rows,
    materialization,
    () => {
      if reentered.val is None && selected.val is Some(port) {
        reentered.val = Some(false)
        reentered.val = Some(
          complete_original_whole_model_outcome(owner, port) is None,
        )
      }
      live.val
    },
  ).unwrap()
  assert_true(
    @execution.prepare_bound_infer_outcome_port(
      issuer,
      completion,
      rows,
      other_materialization,
      () => live.val,
    )
    is Err(@execution.ForeignOutput),
  )
  selected.val = Some(port)
  let output = complete_original_whole_model_outcome(owner, port).unwrap()
  assert_true(reentered.val == Some(true))
  selected.val = None
  assert_true(complete_original_whole_model_outcome(owner, port) is None)
  fn export_original(value) {
    let scan = @execution.start_completed_relation_identity_scan(
      value,
      10,
      values,
      wire,
      wire,
      { max_fields: 10, max_bytes: 10000, max_nodes: 1000, max_depth: 20, },
      1000000,
      100000,
      incremental_metadata=true,
    ).unwrap()
    while !@execution.advance_completed_relation_identity_scan(scan, 32).unwrap().0 {
      ()
    }
    @execution.finish_completed_relation_identity_scan(scan).unwrap()
  }
  let receipt = export_original(output)
  let different_receipt = export_original(foreign)
  assert_false(client_whole_model_terminal_matches(scope, receipt))
  assert_false(client_whole_model_terminal_output_matches(scope, output))
  let completed = match suffix {
    Some(sequence) => {
      let child = @local_query_time.start_client_infer_suffix(
        sequence,
        [output, input],
        execution,
        { max_work: 100000, max_bytes: 20000, max_nodes: 10000, max_depth: 20, },
      ).unwrap()
      Some((child, finish_whole_model_fixture_suffix(child)))
    }
    None => None
  }
  let terminal_output = completed.map(pair => pair.1).unwrap_or(output)
  let terminal_receipt = if completed is Some(_) {
    let exported = export_original(terminal_output)
    assert_not_eq(
      @execution.relation_schema_cid(
        @execution.completed_relation_export_schema_identity(receipt),
      ),
      @execution.relation_schema_cid(
        @execution.completed_relation_export_schema_identity(exported),
      ),
    )
    exported
  } else {
    receipt
  }
  // Equal rows and the same checked target cannot select the direct terminal.
  // In the suffix case, the Outcome itself cannot stand in for its result.
  let wrong_terminal = if completed is Some(_) { output } else { foreign }
  assert_false(
    record_original_whole_model_terminal(terminal, output, wrong_terminal, () => {
      true
    }),
  )
  assert_false(
    record_original_whole_model_terminal(terminal, foreign, terminal_output, () => {
      true
    }),
  )
  assert_false(
    record_original_whole_model_terminal(terminal, output, terminal_output, () => {
      false
    }),
  )
  let original_import = scope.result_inputs[0]
  assert_false(
    record_original_whole_model_terminal(terminal, output, terminal_output, () => {
      scope.result_inputs[0] = { ..original_import, }
      true
    }),
  )
  scope.result_inputs[0] = original_import
  let entered = Ref(false)
  assert_true(
    record_original_whole_model_terminal(terminal, output, terminal_output, () => {
      entered.val = true
      !record_original_whole_model_terminal(terminal, output, terminal_output, () => {
        true
      })
    }),
  )
  assert_true(entered.val)
  assert_true(client_whole_model_terminal_matches(scope, terminal_receipt))
  assert_true(
    client_whole_model_terminal_output_matches(scope, terminal_output),
  )
  assert_false(
    client_whole_model_terminal_output_matches(scope, wrong_terminal),
  )
  assert_eq(
    client_whole_model_terminal_matches(scope, receipt),
    completed is None,
  )
  assert_false(client_whole_model_terminal_matches(scope, different_receipt))
  assert_false(
    record_original_whole_model_terminal(terminal, output, terminal_output, () => {
      true
    }),
  )
  let result_port = @strategy.graph_result_occurrence(
    scope.owner.graph,
    if completed is Some(_) {
      1
    } else {
      0
    },
  ).unwrap()
  let view = @execution.prepare_completed_result_relation_export(
    terminal_output,
    result_port,
    {
      max_fields: 10,
      max_mapping_work: 100,
      max_order_work: 100,
      max_workspace_entries: 100,
    },
    10,
    values,
    wire,
    wire,
    { max_fields: 10, max_bytes: 10000, max_nodes: 1000, max_depth: 20, },
    256,
  ).unwrap()
  while @execution.next_completed_output_export(view).unwrap() is Some(_) {
    ()
  }
  let (result_receipt, _) = @execution.finish_completed_relation_export(view).unwrap()
  assert_true(
    @execution.completed_relation_export_matches_output(
      result_receipt, terminal_output,
    ),
  )
  assert_false(client_whole_model_outcome_matches(scope, result_receipt))
  let logical = @execution.logical_relation_cid(
    @execution.completed_relation_export_identity(receipt),
  )
  let schema = @execution.relation_schema_cid(
    @execution.completed_relation_export_schema_identity(receipt),
  )
  assert_eq(
    @execution.logical_relation_cid(
      @execution.completed_relation_export_identity(different_receipt),
    ),
    logical,
  )
  let (input_logical, input_schema) = @publication.model_input_artifact_relation_identities(
    scope.artifact,
  ).unwrap()
  fn observation(outcome_cid : String) {
    let preimage = "{\"input_logical_relation_cid\":\"" +
      input_logical +
      "\",\"input_relation_schema_cid\":\"" +
      input_schema +
      "\",\"outcome_logical_relation_cid\":\"" +
      outcome_cid +
      "\",\"outcome_relation_schema_cid\":\"" +
      schema +
      "\",\"source_ordinal\":" +
      scope.source_ordinal.to_string() +
      ",\"unit_definition_cid\":\"" +
      scope.unit_definition_cid +
      "\",\"version\":\"actql-local-model-observation/0.1\"}"
    let cid = "sha256:" + @sha.text_hex(preimage).unwrap()
    @publication.admit_local_effect_dependency_body(
      "local_model_observation",
      preimage.replace(
        old=",\"source_ordinal\":",
        new=",\"self_cid\":\"" + cid + "\",\"source_ordinal\":",
      ),
      10000,
      1000,
      20,
    ).unwrap()
  }
  let exact = observation(logical)
  let substituted = observation("sha256:" + "9".repeat(64))
  assert_true(client_whole_model_observation_matches(scope, exact, receipt))
  assert_false(
    client_whole_model_observation_matches(scope, exact, different_receipt),
  )
  assert_true(
    @publication.local_model_observation_matches_input(
      substituted,
      scope.unit_definition_cid,
      scope.source_ordinal,
      scope.artifact,
    ),
  )
  assert_false(
    client_whole_model_observation_matches(scope, substituted, receipt),
  )
  assert_true(client_whole_model_terminal_matches(scope, result_receipt))
  retire_original_whole_model_terminal(terminal)
  assert_false(client_whole_model_terminal_matches(scope, terminal_receipt))
  assert_false(
    record_original_whole_model_terminal(terminal, output, terminal_output, () => {
      true
    }),
  )
  @execution.cancel_completed_relation_export_receipt(different_receipt)
  @execution.cancel_completed_relation_export_receipt(result_receipt)
  if completed is Some((child, _)) {
    @execution.cancel_completed_relation_export_receipt(terminal_receipt)
    assert_true(@local.cleanup_managed_provider(child).unwrap())
  }
  @execution.cancel_completed_relation_export_receipt(receipt)
  live.val = false
  assert_false(@execution.completed_output_available(output))
  assert_false(client_whole_model_observation_matches(scope, exact, receipt))
  assert_true(complete_original_whole_model_outcome(owner, port) is None)
  assert_true(
    @execution.cleanup_admitted_output_preparation(materialization).unwrap(),
  )
  assert_true(
    @execution.cleanup_admitted_output_preparation(other_materialization).unwrap(),
  )
  settle_client_model_read_consumer(consumer, true).unwrap()
  @resources.settle_capacity(ledger, capacity).unwrap()
  assert_true(
    finish_client_model_read_scope(read_scope, compiled, definition, plan, true).unwrap(),
  )
}

///|
fn finish_whole_model_fixture_suffix(
  child : @local.ManagedProviderExecution,
) -> @execution.CompletedOutput raise {
  for _ in 0..<1000 {
    match @local.advance_managed_provider(child, 32).unwrap() {
      @local.Complete(value, ..) => return value
      @local.Continue(..) => ()
      _ => fail("original Whole Model Compute suffix failed")
    }
  }
  fail("original Whole Model Compute suffix did not finish")
}
