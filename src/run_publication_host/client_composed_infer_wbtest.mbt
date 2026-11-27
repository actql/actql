///|
fn client_composed_infer_test_program(
  authored? : String? = None,
) -> PreparedClientProgram raise {
  let fixture = client_infer_prefix_test_program()
  let environment = @checked.checking_environment(
    @checked.checked_environment(@strategy.graph_program(fixture.graph)),
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    model_tasks=@checked.checked_model_tasks(
      @strategy.graph_program(fixture.graph),
    ),
  )
  let document =
    #|{"version":"actql/0.1","id":"composed-infer","stages":[{"id":"left","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"text":{"type":"string","nullable":true}},"rows":[{"id":"a","text":"hello"}]},"as":"rows"}],"results":{"rows":{"from":"rows","fields":["id","text"]}}},{"id":"right","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"tag":{"type":"string","nullable":false}},"rows":[{"id":"a","tag":"match"}]},"as":"rows"}],"results":{"rows":{"from":"rows","fields":["id","tag"]}}},{"id":"classify","inputs":{"left_rows":{"result":{"stage":"left","result":"rows"}},"right_rows":{"result":{"stage":"right","result":"rows"}}},"steps":[{"from":"left_rows","join":{"with":"right_rows","kind":"inner","on":[{"left":"id","right":"id"}],"max_output_rows":2,"select":{"id":"left.id","text":"left.text"}}},{"assert_rows":{"unique_by":["id"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"text"}}},"as":"captured"}],"results":{"rows":{"from":"captured","fields":["id","outcome","value"]}}}],"results":{"answer":{"from":{"stage":"classify","result":"rows"}}}}
  let prepared = prepare_effect_free_client_program(
    authored.unwrap_or(document),
    Json,
    environment,
    None,
    client_standard_program_preparation_limits(),
  )
  match prepared {
    Ok(value) => value
    Err(Syntax(_)) => abort("composition fixture syntax")
    Err(Check(issue)) => raise @checked.diagnostic_cause(issue)
    Err(Graph(_)) => abort("composition fixture graph")
    Err(_) => abort("composition fixture preparation")
  }
}

///|
fn original_infer_graph_parts_fixture() -> (
  PreparedClientProgram,
  ClientInferPlanGraph,
) {
  let prepared = client_infer_prefix_test_program()
  let occurrence = prepared_client_composed_infer_occurrence(prepared).unwrap()
  let bounds = run_materials_limits()
  let graph = issue_installed_client_composed_infer_plan_graph(
    occurrence,
    client_infer_graph_test_execution(prepared, occurrence=Some(occurrence)),
    bounds.sequence,
    bounds.max_evidence_bytes,
    bounds.max_evidence_nodes,
    bounds.max_evidence_depth,
  ).unwrap()
  (prepared, graph)
}

///|
test "Model component graph retains its original arrays and completed writer geometry for the actual task compiler" {
  let (prepared, component) = original_infer_graph_parts_fixture()
  let bounds = run_materials_limits()
  let parsed = @source.parse_json_bytes_measured(
    @utf8.encode(component.graph.wire),
    {
      max_input_bytes: bounds.max_evidence_bytes,
      max_nodes: bounds.max_evidence_nodes,
      max_depth: bounds.max_evidence_depth,
    },
  ).unwrap()
  assert_eq(component.graph_wire_bytes, parsed.usage.input_bytes)
  assert_eq(component.graph_wire_nodes, parsed.usage.nodes)
  assert_eq(component.graph_wire_depth, parsed.usage.depth)
  let (nodes, edges, roots) = client_infer_graph_original_parts(
    component,
    prepared,
    parsed.usage.input_bytes,
    parsed.usage.nodes,
    parsed.usage.depth,
  ).unwrap()
  assert_true(physical_equal(nodes, component.graph_nodes))
  assert_true(physical_equal(edges, component.graph_edges))
  assert_true(physical_equal(roots, component.graph_roots))
  assert_eq(nodes.length(), 2)
  assert_eq(edges.length(), 1)
  assert_true(roots.is_empty())
  assert_true(
    @canonical.object_field(nodes[1], "node_id") is Some(@canonical.String(id)) &&
    id == "task_0_infer_2",
  )
  let compiled = issue_prepared_client_multi_infer_compilation(
    prepared,
    [component],
    run_materials_manifests(),
    bounds.sequence,
    bounds.max_sequence_steps,
    bounds.max_sequence_work,
    bounds.max_evidence_bytes,
    bounds.max_evidence_nodes,
    bounds.max_evidence_depth,
  ).unwrap()
  assert_eq(compiled.infers.length(), 1)
  assert_true(physical_equal(compiled.infers[0], component))
  assert_eq(client_task_compilation_result_names(compiled), ["answer"])
}

///|
test "Model original graph parts keep tighter codec bounds and refuse foreign or changed wire" {
  let (prepared, component) = original_infer_graph_parts_fixture()
  let b = component.graph_wire_bytes
  let n = component.graph_wire_nodes
  let d = component.graph_wire_depth
  for
    (bytes, nodes, depth) in [
      (b - 1, n, d),
      (b, n - 1, d),
      (b, n, d - 1),
      (0, n, d),
    ] {
    assert_true(
      client_infer_graph_original_parts(
        component, prepared, bytes, nodes, depth,
      )
      is None,
    )
  }
  assert_true(
    client_infer_graph_original_parts(
      component,
      client_infer_prefix_test_program(),
      b,
      n,
      d,
    )
    is None,
  )
  let changed = { ..component, graph: { ..component.graph, wire: "{}", }, }
  assert_true(
    client_infer_graph_original_parts(changed, prepared, b, n, d) is None,
  )
  let equal_copy = {
    ..component,
    graph: { ..component.graph, wire: component.graph.wire, },
  }
  assert_true(!physical_equal(equal_copy.graph, component.graph))
  assert_true(
    client_infer_graph_original_parts(equal_copy, prepared, b, n, d) is None,
  )
  assert_true(
    issue_prepared_client_multi_infer_task_plan_graph(
      prepared,
      [changed],
      run_materials_limits().sequence,
      b,
      n,
      d,
    )
    is Err(UnsupportedGraph),
  )
}

///|
test "composed INFER selects its checked JOIN task rather than task zero" {
  let prepared = client_composed_infer_test_program()
  // The existing one-task component selection remains scoped to its input.
  assert_eq(prepared_client_infer_step(prepared), None)
  let occurrence = prepared_client_composed_infer_occurrence(prepared).unwrap()
  assert_eq(client_infer_occurrence_coordinates(occurrence), (2, 2, 2))
  assert_true(client_infer_occurrence_matches(occurrence, prepared))
  assert_true(
    !client_infer_occurrence_matches(
      occurrence,
      client_composed_infer_test_program(),
    ),
  )
  assert_true(
    physical_equal(
      occurrence.preparation,
      @strategy.graph_task_owner(prepared.graph, 2).unwrap(),
    ),
  )
}

///|
test "composition selection preserves the existing source-free occurrence" {
  let prepared = client_infer_prefix_test_program()
  let occurrence = prepared_client_composed_infer_occurrence(prepared).unwrap()
  assert_eq(client_infer_occurrence_coordinates(occurrence), (0, 0, 2))
  assert_eq(prepared_client_infer_step(prepared), Some(2))
  assert_eq(
    client_infer_occurrence_model_task_cid(occurrence),
    prepared_client_infer_model_task_cid(prepared, 2),
  )
}

///|
fn client_two_independent_infer_test_program() -> PreparedClientProgram raise {
  let document =
    #|{"version":"actql/0.1","id":"two-independent-infer","stages":[{"id":"input","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"text":{"type":"string","nullable":true}},"rows":[{"id":"a","text":"é\r"},{"id":"b","text":"é\n"}]},"as":"items"}],"results":{"rows":{"from":"items","fields":["id","text"]}}},{"id":"first","inputs":{"rows":{"result":{"stage":"input","result":"rows"}}},"steps":[{"assert_rows":{"unique_by":["id"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"text"}}},"as":"first_assessment"}],"results":{"rows":{"from":"first_assessment","fields":["id","outcome","value"]}}},{"id":"second","inputs":{"rows":{"result":{"stage":"input","result":"rows"}}},"steps":[{"assert_rows":{"unique_by":["id"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"text"}}},"as":"second_assessment"}],"results":{"rows":{"from":"second_assessment","fields":["id","outcome","value"]}}},{"id":"combine","inputs":{"first":{"result":{"stage":"first","result":"rows"}},"second":{"result":{"stage":"second","result":"rows"}}},"steps":[{"from":"first","join":{"with":"second","kind":"inner","cardinality":"one_to_one","max_output_rows":2,"on":[{"left":"id","right":"id"}],"select":{"id":"left.id","first":"left.value","second":"right.value"}},"as":"joined"}],"results":{"rows":{"from":"joined","fields":["id","first","second"]}}}],"results":{"answer":{"from":{"stage":"combine","result":"rows"}}}}
  client_composed_infer_test_program(authored=Some(document))
}

///|
test "two independent INFER Units retain distinct logical occurrences for the same item keys" {
  let prepared = client_two_independent_infer_test_program()
  // This old single-component getter must not silently choose just the first.
  assert_true(prepared_client_composed_infer_occurrence(prepared) is None)
  let occurrences = prepared_client_composed_infer_occurrences(prepared).unwrap()
  assert_eq(occurrences.length(), 2)
  assert_eq(client_infer_occurrence_coordinates(occurrences[0]), (1, 1, 1))
  assert_eq(client_infer_occurrence_coordinates(occurrences[1]), (2, 2, 1))
  assert_eq(
    client_infer_occurrence_target_name(occurrences[0]),
    Some("first_assessment"),
  )
  assert_eq(
    client_infer_occurrence_target_name(occurrences[1]),
    Some("second_assessment"),
  )
  for occurrence in occurrences {
    assert_true(client_infer_occurrence_matches(occurrence, prepared))
    assert_true(
      !client_infer_occurrence_matches(
        occurrence,
        client_composed_infer_test_program(),
      ),
    )
  }
}

///|
test "historical independent INFER scopes resolve the same checked Source by its graph edge" {
  let base = admit_client_check_environment(
    local_normalization_environment_wire,
    "sha256:afebeb63f2e0e48434bf005f65ab0af8a0c2704f0afb5a8c70df72e91b26e86e",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let document =
    #|{"version":"actql/0.1","id":"saved-shared-source","stages":[{"id":"source","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id >= 0"},{"select":["id","amount"],"as":"captured"}],"results":{"rows":{"from":"captured","fields":["id","amount"]}}},{"id":"first","inputs":{"items":{"result":{"stage":"source","result":"rows"}}},"steps":[{"derive":{"text":{"literal":"first"}}},{"assert_rows":{"unique_by":["id"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"text"}}},"as":"first_assessment"}],"results":{"rows":{"from":"first_assessment","fields":["id","outcome","value"]}}},{"id":"second","inputs":{"items":{"result":{"stage":"source","result":"rows"}}},"steps":[{"derive":{"text":{"literal":"second"}}},{"assert_rows":{"unique_by":["id"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"text"}}},"as":"second_assessment"}],"results":{"rows":{"from":"second_assessment","fields":["id","outcome","value"]}}}],"results":{"first":{"from":{"stage":"first","result":"rows"}},"second":{"from":{"stage":"second","result":"rows"}}}}
  let prepared = prepare_effect_free_client_program(
    document,
    Json,
    client_composed_effect_test_environment(base),
    None,
    client_standard_program_preparation_limits(),
  ).unwrap()
  let occurrences = prepared_client_composed_infer_occurrences(prepared).unwrap()
  assert_eq(occurrences.length(), 2)
  assert_eq(@strategy.graph_captured_prefix(prepared.graph), 1)
  let expected = @planning.query_acquisition_source_evidence_facts(
    prepare_client_query_acquisition(prepared, 0, 0).unwrap(),
  ).unwrap()
  for occurrence in occurrences {
    let resolved = infer_scope_expected_sources(occurrence).unwrap()
    assert_eq(resolved.length(), 1)
    assert_eq(resolved[0].0, "items")
    assert_eq(resolved[0].1.source_ref, expected.source_ref)
    assert_eq(resolved[0].1.source_contract_cid, expected.source_contract_cid)
    assert_eq(
      resolved[0].1.source_data_policy_cid,
      expected.source_data_policy_cid,
    )
  }
}

///|
test "common graph retains both independent Model barriers and rejects incomplete or substituted inventories" {
  let prepared = client_two_independent_infer_test_program()
  let occurrences = prepared_client_composed_infer_occurrences(prepared).unwrap()
  let components = occurrences.map(occurrence => {
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
  let issued = issue_prepared_client_multi_infer_task_plan_graph(
    prepared,
    components,
    run_materials_limits().sequence,
    100000,
    10000,
    100,
  ).unwrap()
  let graph = parse_plan_identity_value(issued.wire, 100000, 10000, 100).unwrap()
  guard @canonical.object_field(graph, "nodes") is Some(@canonical.Array(nodes)) &&
    @canonical.object_field(graph, "data_edges")
    is Some(@canonical.Array(edges)) &&
    @canonical.object_field(graph, "root_refs") is Some(@canonical.Array(roots)) else {
    fail("complete two-INFER graph")
  }
  assert_eq(@canonical.array_values(nodes).length(), 6)
  assert_eq(@canonical.array_values(edges).length(), 6)
  let ids = @canonical.array_values(nodes).map(node => {
    guard @canonical.object_field(node, "node_id")
      is Some(@canonical.String(id)) else {
      abort("Model graph node identity")
    }
    id
  })
  assert_true(ids.contains("task_1_infer_1"))
  assert_true(ids.contains("task_2_infer_1"))
  assert_eq(@canonical.array_values(roots).length(), 1)
  let compilation = issue_prepared_client_multi_infer_compilation(
    prepared,
    components,
    run_materials_manifests(),
    run_materials_limits().sequence,
    1000,
    10000,
    100000,
    10000,
    100,
  ).unwrap()
  assert_true(client_task_compilation_infer(compilation) is None)
  let retained = client_task_compilation_infers(compilation)
  assert_eq(retained.length(), 2)
  assert_true(physical_equal(retained[0], components[0]))
  assert_true(physical_equal(retained[1], components[1]))
  assert_eq(client_task_compilation_result_names(compilation), ["answer"])
  assert_true(
    issue_client_task_source_free_invocation(
      compilation,
      "sha256:" + "d".repeat(64),
      100000,
      10000,
      100,
    )
    is Err(@publication.RunEvidenceReferenceMismatch("model_capture")),
  )
  for
    inventory in [
      [components[0]],
      [components[0], components[0]],
      components.rev(),
    ] {
    assert_true(
      issue_prepared_client_multi_infer_task_plan_graph(
        prepared,
        inventory,
        run_materials_limits().sequence,
        100000,
        10000,
        100,
      )
      is Err(UnsupportedGraph),
    )
  }
  assert_true(
    issue_prepared_client_multi_infer_task_plan_graph(
      client_two_independent_infer_test_program(),
      components,
      run_materials_limits().sequence,
      100000,
      10000,
      100,
    )
    is Err(UnsupportedGraph),
  )
}

///|
test "composed egress follows checked source-free imports for each sibling" {
  let prepared = client_two_independent_infer_test_program()
  let occurrences = prepared_client_composed_infer_occurrences(prepared).unwrap()
  assert_eq(occurrences.length(), 2)
  let program = @strategy.graph_program(prepared_client_graph(prepared))
  for occurrence in occurrences {
    assert_true(
      @checked.prepare_infer_input_policy(
        program,
        occurrence.stage,
        occurrence.step,
        1000000,
        1000000,
        100000,
        100,
      )
      is Some(@checked.ClosedLocal),
    )
    let execution = client_infer_graph_test_execution(
      prepared,
      occurrence=Some(occurrence),
    )
    assert_true(
      admit_client_infer_occurrence_egress(occurrence, execution, () => {
        Some({
          classification: @environment.Public,
          region: "fixture-region",
          provider_retention: false,
          training_use: false,
        })
      })
      is Ok(_),
    )
  }
  let first = occurrences[0]
  try
    @checked.prepare_infer_input_policy(
      program,
      first.stage,
      first.step,
      1000000,
      1000000,
      100000,
      0,
    )
  catch {
    @checked.BudgetExceeded => ()
    issue => raise issue
  } noraise {
    _ => fail("checked imports require bounded traversal")
  }
}

///|
fn client_composed_whole_sibling_test_program(
  confidential? : Bool = false,
  unknown? : Bool = false,
  authored? : String? = None,
  project_second_model? : Bool = false,
) -> PreparedClientProgram raise {
  let base =
    #|{"version":"actql/0.1","id":"model-whole-egress","stages":[{"id":"source","inputs":{"left":{"connector":"crm/main","resource":"r","view":"v"},"right":{"connector":"crm/right","resource":"r","view":"v"}},"steps":[{"from":"left","join":{"with":"right","kind":"inner","on":[{"left":"id","right":"id"}],"max_output_rows":100,"select":{"id":"left.id","amount":"right.amount"}},"as":"joined"}],"results":{"rows":{"from":"joined","fields":["id","amount"]}}},{"id":"first","inputs":{"rows":{"result":{"stage":"source","result":"rows"}}},"steps":[{"from":"rows","assert_rows":{"unique_by":["id"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"literal":"fixture"}}},"as":"answer"}],"results":{"rows":{"from":"answer","fields":["id","outcome","value"]}}},{"id":"second","inputs":{"rows":{"result":{"stage":"source","result":"rows"}}},"steps":[{"from":"rows","assert_rows":{"unique_by":["id"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"literal":"fixture"}}},"as":"answer"}],"results":{"rows":{"from":"answer","fields":["id","outcome","value"]}}}],"results":{"a":{"from":{"stage":"first","result":"rows"}},"b":{"from":{"stage":"second","result":"rows"}}}}
  let document = if project_second_model {
    let final_result = "\"as\":\"answer\"}],\"results\":{\"rows\":{\"from\":\"answer\",\"fields\":[\"id\",\"outcome\",\"value\"]}}}],"
    base.replace(
      old=final_result,
      new="\"as\":\"answer\"},{\"select\":[\"id\",\"outcome\"],\"as\":\"projected\"}],\"results\":{\"rows\":{\"from\":\"projected\",\"fields\":[\"id\",\"outcome\"]}}}],",
    )
  } else {
    base
  }
  // The original right View and its Catalog are independently sealed with a
  // Confidential policy. Both controls keep the exact same Program and Tasks.
  let (environment_wire, environment_cid) = if unknown {
    (
      local_normalization_environment_wire, "sha256:afebeb63f2e0e48434bf005f65ab0af8a0c2704f0afb5a8c70df72e91b26e86e",
    )
  } else if confidential {
    let wire = mixed_known_policy_environment
      .replace_all(
        old="\"classification\":\"internal\"",
        new="\"classification\":\"confidential\"",
      )
      .replace_all(
        old="\"data_classification\":\"internal\"",
        new="\"data_classification\":\"confidential\"",
      )
      .replace_all(
        old="sha256:49c2c1c7fa4075fd3b6fe3f4475af5fc8928c0f4afb6555407777475e436fa71",
        new="sha256:fa43c4bc38c5d8122483eeef4309239e61a69752983a953d029e5c42411ea702",
      )
      .replace_all(
        old="sha256:dadbf9cb08280610faba740ca1699ba0f21e3f4f53c466bf1e47cc077aca7451",
        new="sha256:e4b0e5d281576fca9fbc98fad7340cc30fe5813739a92df07c11f2701fb3e10b",
      )
      .replace_all(
        old="sha256:370a20e504ba8d42463f6adf972fa3df9ae4e70657ba28e70f2da0e72f416f0d",
        new="sha256:1bd69695dbcdf833492f8137a9aa7bae945755dfe4df49de6c2a5c8aa35b9d53",
      )
      .replace_all(
        old="sha256:a789489e096d742e32125c57801a7b8662174befe3c3b2a6369e19533a471115",
        new="sha256:1fe36b910d3b3bb4f18a862533658777abfa7f9311a2e55980e45a19f9a2630e",
      )
    // The two exact Snapshot member hashes reverse order under the new wire.
    let value = parse_plan_identity_value(wire, 20000, 4000, 64).unwrap()
    let writer = @encode.writer(20000, 4000, 64)
    @encode.begin_object(writer)
    for (name, item) in @canonical.object_fields(value).unwrap() {
      @encode.key(writer, name)
      if name == "schema_snapshots" {
        guard item is @canonical.Array(original_snapshots) else {
          fail("Missing original fixture Snapshot array")
        }
        let snapshots = @canonical.array_values(original_snapshots)
        assert_eq(snapshots.length(), 2)
        @encode.begin_array(writer)
        @canonical.emit_value(snapshots[1], writer)
        @canonical.emit_value(snapshots[0], writer)
        @encode.end_array(writer)
      } else if name == "connector_catalogs" {
        guard item is @canonical.Array(original_catalogs) else {
          fail("Missing original fixture Catalog array")
        }
        let catalogs = @canonical.array_values(original_catalogs)
        assert_eq(catalogs.length(), 2)
        @encode.begin_array(writer)
        @encode.begin_object(writer)
        for (field, content) in @canonical.object_fields(catalogs[0]).unwrap() {
          @encode.key(writer, field)
          if field == "contracts" {
            guard content is @canonical.Array(original_contracts) else {
              fail("Missing original right Catalog contracts")
            }
            let contracts = @canonical.array_values(original_contracts)
            assert_eq(contracts.length(), 5)
            @encode.begin_array(writer)
            for index in [0, 2, 3, 4, 1] {
              @canonical.emit_value(contracts[index], writer)
            }
            @encode.end_array(writer)
          } else {
            @canonical.emit_value(content, writer)
          }
        }
        @encode.end_object(writer)
        @canonical.emit_value(catalogs[1], writer)
        @encode.end_array(writer)
      } else {
        @canonical.emit_value(item, writer)
      }
    }
    @encode.end_object(writer)
    (
      @encode.finish(writer),
      "sha256:1fe36b910d3b3bb4f18a862533658777abfa7f9311a2e55980e45a19f9a2630e",
    )
  } else {
    (
      mixed_known_policy_environment, "sha256:a789489e096d742e32125c57801a7b8662174befe3c3b2a6369e19533a471115",
    )
  }
  let known = admit_client_check_environment(
    environment_wire,
    environment_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  match
    prepare_effect_free_client_program(
      authored.unwrap_or(document),
      Json,
      client_composed_effect_test_environment(known),
      None,
      client_standard_program_preparation_limits(),
    ) {
    Ok(value) => value
    Err(Check(issue)) => raise @checked.diagnostic_cause(issue)
    Err(_) => fail("Whole sibling preparation")
  }
}

///|
test "composed egress retains both source policies at each sibling input" {
  let prepared = client_composed_whole_sibling_test_program()
  let occurrences = prepared_client_composed_infer_occurrences(prepared).unwrap()
  assert_eq(occurrences.length(), 2)
  let program = @strategy.graph_program(prepared_client_graph(prepared))
  for occurrence in occurrences {
    assert_true(
      @checked.prepare_infer_input_policy(
        program,
        occurrence.stage,
        occurrence.step,
        1000000,
        1000000,
        100000,
        100,
      )
      is Some(@checked.CheckedSources(@environment.Internal)),
    )
    let execution = client_infer_graph_test_execution(
      prepared,
      occurrence=Some(occurrence),
    )
    assert_true(
      admit_client_infer_occurrence_egress(occurrence, execution, () => {
        Some({
          classification: @environment.Public,
          region: "fixture-region",
          provider_retention: false,
          training_use: false,
        })
      })
      is Ok(_),
    )
  }
}

///|
test "composed egress refuses a Confidential contributing Whole View for either sibling" {
  let prepared = client_composed_whole_sibling_test_program(confidential=true)
  let occurrences = prepared_client_composed_infer_occurrences(prepared).unwrap()
  assert_eq(occurrences.length(), 2)
  let program = @strategy.graph_program(prepared_client_graph(prepared))
  for occurrence in occurrences {
    assert_true(
      @checked.prepare_infer_input_policy(
        program,
        occurrence.stage,
        occurrence.step,
        1000000,
        1000000,
        100000,
        100,
      )
      is Some(@checked.CheckedSources(@environment.Confidential)),
    )
    let execution = client_infer_graph_test_execution(
      prepared,
      occurrence=Some(occurrence),
    )
    assert_true(
      admit_client_infer_occurrence_egress(occurrence, execution, () => {
        Some({
          classification: @environment.Public,
          region: "fixture-region",
          provider_retention: false,
          training_use: false,
        })
      })
      is Err(ClassificationDenied),
    )
  }
}

///|
test "Whole sibling INFER prefixes receive the same original declared Result port" {
  let prepared = client_composed_whole_sibling_test_program()
  let graph = prepared_client_graph(prepared)
  let occurrences = prepared_client_composed_infer_occurrences(prepared).unwrap()
  assert_eq(occurrences.length(), 2)
  let mut previous : @results.ResultPort? = None
  for occurrence in occurrences {
    let mut selected : @results.ResultPort? = None
    for index in 0..<@strategy.graph_data_count(graph) {
      let edge = @strategy.graph_data_at(graph, index).unwrap()
      if @strategy.graph_task_unit_index(
          graph,
          @strategy.data_edge_consumer(edge),
        ) !=
        Some(occurrence.stage) {
        continue
      }
      if @strategy_view.graph_result_input_port(graph, index).unwrap()
        is Some(port) {
        assert_true(selected is None)
        assert_eq(
          @strategy.graph_task_unit_index(
            graph,
            @strategy.data_edge_producer(edge),
          ),
          Some(0),
        )
        assert_eq(@results.name(@results.port_result(port)), "rows")
        selected = Some(port)
      }
    }
    guard selected is Some(port) else {
      fail("missing original Whole Result import")
    }
    if previous is Some(first) {
      assert_true(physical_equal(first, port))
    }
    previous = Some(port)
  }

  let port = previous.unwrap()
  let program = @strategy.graph_program(graph)
  let policy = @checked.prepare_local_result_source_policy(
    program, 0, port, 100000, 65536, 8192, 64,
  ).unwrap()
  assert_false(policy.unknown_provenance)
  assert_eq(
    @checked.publication_policy_classification(policy),
    @environment.Internal,
  )
  assert_eq(@checked.publication_policy_source_count(policy), 2)
  let contributors = []
  for index in 0..<2 {
    let source = @checked.publication_policy_source_at(policy, index).unwrap()
    contributors.push(
      @acquisition.declaration(@checked.source_execution_subject(source).source).input_name,
    )
  }
  contributors.sort_by(@canonical_value.compare_utf16)
  assert_eq(contributors, ["left", "right"])
  assert_true(
    prepared_client_publication_data_policy_cid(prepared) != Some(policy.cid),
  )
  let foreign = @strategy.graph_program(
    prepared_client_graph(client_composed_whole_sibling_test_program()),
  )
  try
    @checked.prepare_local_result_source_policy(
      foreign, 0, port, 100000, 65536, 8192, 64,
    )
  catch {
    @checked.ForeignOwner => ()
    issue => raise issue
  } noraise {
    _ => fail("same-Program foreign producer port admitted")
  }
  try
    @checked.prepare_local_result_source_policy(
      program, 0, port, 0, 65536, 8192, 64,
    )
  catch {
    @checked.BudgetExceeded => ()
    issue => raise issue
  } noraise {
    _ => fail("producer policy accepted without work")
  }
}

///|
test "composed egress refuses unattested prior Model output without acquisitions" {
  let document =
    #|{"version":"actql/0.1","id":"model-output-policy-unproven","stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"text":{"type":"string","nullable":false}},"rows":[{"id":"one","text":"first prompt"}]},"as":"rows"}],"results":{"rows":{"from":"rows","fields":["id","text"]}}},{"id":"first","inputs":{"rows":{"result":{"stage":"source","result":"rows"}}},"steps":[{"from":"rows","assert_rows":{"unique_by":["id"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"text"}}},"as":"assessed"}],"results":{"rows":{"from":"assessed","fields":["id","outcome","value"]}}},{"id":"second","inputs":{"rows":{"result":{"stage":"first","result":"rows"}},"unused":{"result":{"stage":"first","result":"rows"}}},"steps":[{"from":"rows","assert_rows":{"unique_by":["id"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"outcome"}}},"as":"assessed"}],"results":{"rows":{"from":"assessed","fields":["id","outcome","value"]}}}],"results":{"answer":{"from":{"stage":"second","result":"rows"}}}}
  let prepared = client_composed_infer_test_program(authored=Some(document))
  let graph = prepared_client_graph(prepared)
  assert_eq(@strategy.graph_captured_prefix(graph), 0)
  let occurrences = prepared_client_composed_infer_occurrences(prepared).unwrap()
  assert_eq(occurrences.length(), 2)
  let observe = () => {
    Some({
      classification: @environment.Public,
      region: "fixture-region",
      provider_retention: false,
      training_use: false,
    })
  }
  let first = occurrences[0]
  let second = occurrences[1]
  let program = @strategy.graph_program(graph)
  guard @checked.prepare_infer_input_policy(
      program,
      second.stage,
      second.step,
      1000000,
      1000000,
      100000,
      100,
    )
    is Some(@checked.PendingModelOutputs(waiting)) else {
    fail("exact first Model output must remain pending at the receiving input")
  }
  assert_true(
    @checked.checked_infer_model_inputs_match(
      waiting,
      program,
      second.stage,
      second.step,
    ),
  )
  assert_true(
    !@checked.checked_infer_model_inputs_match(
      waiting,
      program,
      first.stage,
      first.step,
    ),
  )
  let foreign = client_composed_infer_test_program(authored=Some(document))
  assert_true(
    !@checked.checked_infer_model_inputs_match(
      waiting,
      @strategy.graph_program(prepared_client_graph(foreign)),
      second.stage,
      second.step,
    ),
  )
  let receiving = @checked.unit_result_import_at(program, second.stage, 0).unwrap()
  let unused = @checked.unit_result_import_at(program, second.stage, 1).unwrap()
  assert_eq(receiving.input_name, "rows")
  assert_eq(unused.input_name, "unused")
  assert_eq(receiving.result_name, unused.result_name)
  assert_eq(
    receiving.producer_unit_definition_cid,
    unused.producer_unit_definition_cid,
  )
  assert_true(
    @checked.checked_infer_model_result_dependency_matches(
      waiting,
      receiving,
      first.stage,
      first.step,
    ),
  )
  assert_false(
    @checked.checked_infer_model_result_dependency_matches(
      waiting,
      unused,
      first.stage,
      first.step,
    ),
  )
  let foreign_import = @checked.unit_result_import_at(
    @strategy.graph_program(prepared_client_graph(foreign)),
    second.stage,
    0,
  ).unwrap()
  assert_eq(receiving.cid, foreign_import.cid)
  assert_false(
    @checked.checked_infer_model_result_dependency_matches(
      waiting,
      foreign_import,
      first.stage,
      first.step,
    ),
  )
  assert_false(
    @checked.checked_infer_model_result_dependency_matches(
      waiting,
      receiving,
      first.stage,
      first.step + 1,
    ),
  )
  assert_eq(@checked.checked_infer_model_inputs_count(waiting), 1)
  assert_eq(
    @checked.checked_infer_model_input_at(waiting, 0),
    Some((first.stage, first.step)),
  )
  assert_eq(@checked.checked_infer_model_input_at(waiting, 1), None)
  assert_true(
    @checked.checked_infer_model_input_source_classification(waiting) is None,
  )
  assert_true(
    admit_client_infer_occurrence_egress(
      first,
      client_infer_graph_test_execution(prepared, occurrence=Some(first)),
      observe,
    )
    is Ok(_),
  )
  assert_true(
    admit_client_infer_occurrence_egress(
      second,
      client_infer_graph_test_execution(prepared, occurrence=Some(second)),
      observe,
    )
    is Err(UnknownClassification),
  )
}

///|
test "composed egress retains direct Whole policy beside a pending Model export" {
  let document =
    #|{"version":"actql/0.1","id":"model-whole-dependent-egress","stages":[{"id":"source","inputs":{"left":{"connector":"crm/main","resource":"r","view":"v"},"right":{"connector":"crm/right","resource":"r","view":"v"}},"steps":[{"from":"left","join":{"with":"right","kind":"inner","on":[{"left":"id","right":"id"}],"max_output_rows":100,"select":{"id":"left.id","amount":"right.amount"}},"as":"joined"}],"results":{"rows":{"from":"joined","fields":["id","amount"]}}},{"id":"first","inputs":{"rows":{"result":{"stage":"source","result":"rows"}}},"steps":[{"from":"rows","assert_rows":{"unique_by":["id"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"literal":"fixture"}}},"as":"answer"}],"results":{"rows":{"from":"answer","fields":["id","outcome","value"]}}},{"id":"second","inputs":{"first_rows":{"result":{"stage":"first","result":"rows"}},"source_rows":{"result":{"stage":"source","result":"rows"}}},"steps":[{"from":"first_rows","join":{"with":"source_rows","kind":"inner","on":[{"left":"id","right":"id"}],"max_output_rows":100,"select":{"id":"left.id","outcome":"left.outcome","amount":"right.amount"}}},{"assert_rows":{"unique_by":["id"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"outcome"}}},"as":"answer"}],"results":{"rows":{"from":"answer","fields":["id","outcome","value"]}}}],"results":{"answer":{"from":{"stage":"second","result":"rows"}}}}
  for
    (unknown, confidential, expected) in [
      (false, false, Some(@environment.Internal)),
      (false, true, Some(@environment.Confidential)),
      (true, false, None),
    ] {
    let authored = if unknown {
      document.replace_all(old=",\"view\":\"v\"", new="")
    } else {
      document
    }
    let prepared = client_composed_whole_sibling_test_program(
      unknown~,
      confidential~,
      authored=Some(authored),
    )
    let graph = prepared_client_graph(prepared)
    let program = @strategy.graph_program(graph)
    let occurrences = prepared_client_composed_infer_occurrences(prepared).unwrap()
    assert_eq(occurrences.length(), 2)
    let first = occurrences[0]
    let second = occurrences[1]
    let policy = @checked.prepare_infer_input_policy(
      program,
      second.stage,
      second.step,
      1000000,
      1000000,
      100000,
      100,
    )
    match expected {
      None =>
        assert_true(
          policy is Some(@checked.CheckedSources(@environment.Unknown)),
        )
      Some(classification) => {
        guard policy is Some(@checked.PendingModelOutputs(waiting)) else {
          fail("the checked Whole policy must survive the pending Model output")
        }
        let model_import = @checked.unit_result_import_at(
          program,
          second.stage,
          0,
        ).unwrap()
        let whole_import = @checked.unit_result_import_at(
          program,
          second.stage,
          1,
        ).unwrap()
        assert_eq(model_import.input_name, "first_rows")
        assert_eq(whole_import.input_name, "source_rows")
        assert_true(
          @checked.checked_infer_model_result_dependency_matches(
            waiting,
            model_import,
            first.stage,
            first.step,
          ),
        )
        assert_false(
          @checked.checked_infer_model_result_dependency_matches(
            waiting,
            whole_import,
            first.stage,
            first.step,
          ),
        )
        assert_eq(@checked.checked_infer_model_inputs_count(waiting), 1)
        assert_eq(
          @checked.checked_infer_model_input_at(waiting, 0),
          Some((first.stage, first.step)),
        )
        assert_eq(
          @checked.checked_infer_model_input_source_classification(waiting),
          Some(classification),
        )
      }
    }
    let execution = client_infer_graph_test_execution(
      prepared,
      occurrence=Some(second),
    )
    let observed : Ref[ClientInferEgressObservation?] = Ref(
      Some({
        classification: @environment.Public,
        region: "fixture-region",
        provider_retention: false,
        training_use: false,
      }),
    )
    assert_true(
      admit_client_infer_occurrence_egress(second, execution, () => observed.val)
      is Err(UnknownClassification),
    )
    let selected = prepare_client_infer_occurrence_egress(second, execution, () => {
      observed.val
    })
    if unknown {
      assert_true(selected is Err(UnknownClassification))
      continue
    }
    if confidential {
      assert_true(selected is Err(ClassificationDenied))
      continue
    }
    guard selected is Ok(EgressPending(pending)) else {
      fail("known Source policy with an unsettled producer must be pending")
    }
    assert_true(pending.candidate.classification == @environment.Internal)
    assert_eq(client_infer_pending_egress_result_count(pending), 1)
    assert_true(
      client_infer_pending_egress_accepts_classification(
        pending,
        @environment.Public,
      ),
    )
    assert_false(
      client_infer_pending_egress_accepts_classification(
        pending,
        @environment.Confidential,
      ),
    )
    assert_false(
      client_infer_pending_egress_accepts_classification(
        pending,
        @environment.Unknown,
      ),
    )
    assert_true(
      client_infer_pending_egress_classification(
        pending,
        @environment.Public,
        @environment.Internal,
      )
      is Ok(@environment.Internal),
    )
    assert_true(
      client_infer_pending_egress_classification(
        pending,
        @environment.Public,
        @environment.Confidential,
      )
      is Err(ClassificationDenied),
    )
    assert_true(
      client_infer_pending_egress_classification(
        pending,
        @environment.Public,
        @environment.Unknown,
      )
      is Err(UnknownClassification),
    )
    fn plan_for(
      occurrence : ClientInferOccurrence,
      selected_execution : @environment.ModelExecutionContract,
    ) -> ClientInferPlanGraph {
      issue_prepared_client_composed_infer_plan_graph(
        occurrence,
        selected_execution,
        "sha256:" + "b".repeat(64),
        "sha256:" + "c".repeat(64),
        run_materials_limits().sequence,
        100000,
        10000,
        100,
        include_results=false,
      ).unwrap()
    }
    let first_execution = client_infer_graph_test_execution(
      prepared,
      occurrence=Some(first),
    )
    let first_plan = plan_for(first, first_execution)
    let second_plan = plan_for(second, execution)
    let fresh = client_composed_whole_sibling_test_program(
      authored=Some(document),
    )
    let foreign = prepared_client_composed_infer_occurrences(fresh).unwrap()[0]
    let foreign_execution = client_infer_graph_test_execution(
      fresh,
      occurrence=Some(foreign),
    )
    let foreign_plan = plan_for(foreign, foreign_execution)
    let original = admit_client_infer_occurrence_egress(
      first,
      first_execution,
      () => observed.val,
    ).unwrap()
    assert_true(original.observed.classification == @environment.Public)
    assert_true(original.classification == @environment.Internal)
    assert_true(client_infer_pending_egress_matches(pending, second_plan))
    assert_false(client_infer_pending_egress_matches(pending, first_plan))
    assert_true(
      resolve_client_infer_pending_egress(pending, second_plan, [], () => true)
      is Err(ForeignOwner),
    )
    assert_true(
      client_infer_pending_egress_result_matches(
        pending, second_plan, 0, first_plan,
      ),
    )
    assert_false(
      client_infer_pending_egress_result_matches(
        pending, second_plan, 1, first_plan,
      ),
    )
    assert_false(
      client_infer_pending_egress_result_matches(
        pending, second_plan, 0, foreign_plan,
      ),
    )
    assert_false(
      client_infer_pending_egress_result_matches(
        pending, second_plan, 0, second_plan,
      ),
    )
    assert_true(check_client_infer_pending_egress_current(pending) is Ok(_))
    observed.val = Some({ ..observed.val.unwrap(), region: "elsewhere", })
    assert_true(
      check_client_infer_pending_egress_current(pending)
      is Err(ChangedObservation),
    )
    observed.val = None
    assert_true(
      check_client_infer_pending_egress_current(pending)
      is Err(MissingObservation),
    )
    let two_ports = document
      .replace(
        old="\"source_rows\":{\"result\":{\"stage\":\"source\",\"result\":\"rows\"}}",
        new="\"source_rows\":{\"result\":{\"stage\":\"first\",\"result\":\"rows\"}}",
      )
      .replace(
        old="\"outcome\":\"left.outcome\",\"amount\":\"right.amount\"",
        new="\"outcome\":\"left.outcome\",\"copy\":\"right.outcome\"",
      )
    let two_ports = client_composed_whole_sibling_test_program(
      authored=Some(two_ports),
    )
    let two = prepared_client_composed_infer_occurrences(two_ports).unwrap()
    let selected = client_infer_graph_test_execution(
      two_ports,
      occurrence=Some(two[1]),
    )
    let two_ports_policy = prepare_client_infer_occurrence_egress(
      two[1],
      selected,
      () => {
        Some({
          classification: @environment.Public,
          region: "fixture-region",
          provider_retention: false,
          training_use: false,
        })
      },
    ).unwrap()
    guard two_ports_policy is EgressPending(two_ports_policy) else {
      fail("two ports from one checked producer remain separate obligations")
    }
    assert_eq(
      @checked.checked_infer_model_inputs_count(two_ports_policy.dependency),
      1,
    )
    assert_eq(client_infer_pending_egress_result_count(two_ports_policy), 2)
    let receiving = plan_for(two[1], selected)
    let producing = plan_for(
      two[0],
      client_infer_graph_test_execution(two_ports, occurrence=Some(two[0])),
    )
    assert_true(
      client_infer_pending_egress_result_matches(
        two_ports_policy, receiving, 0, producing,
      ),
    )
    assert_true(
      client_infer_pending_egress_result_matches(
        two_ports_policy, receiving, 1, producing,
      ),
    )
  }
}

///|
test "composed egress binds the actual Unit and refuses changed or foreign authority" {
  let prepared = client_composed_infer_test_program()
  let occurrence = prepared_client_composed_infer_occurrence(prepared).unwrap()
  let execution = client_infer_graph_test_execution(
    prepared,
    occurrence=Some(occurrence),
  )
  let observed : Ref[ClientInferEgressObservation?] = Ref(
    Some({
      classification: @environment.Public,
      region: "fixture-region",
      provider_retention: false,
      training_use: false,
    }),
  )
  let admission = admit_client_infer_occurrence_egress(occurrence, execution, () => {
    observed.val
  }).unwrap()
  let graph = issue_prepared_client_composed_infer_plan_graph(
    occurrence,
    execution,
    "sha256:" + "b".repeat(64),
    "sha256:" + "c".repeat(64),
    run_materials_limits().sequence,
    100000,
    10000,
    100,
  ).unwrap()
  assert_true(client_infer_egress_matches(admission, prepared, graph))
  assert_true(check_client_infer_egress_current(admission) is Ok(_))
  let retained_reader = Ref(true)
  let dependent = {
    ..admission,
    dispatch_current: Some(() => retained_reader.val),
  }
  assert_true(check_client_infer_egress_current(dependent) is Ok(_))
  retained_reader.val = false
  assert_true(
    check_client_infer_egress_current(dependent) is Err(MissingObservation),
  )
  assert_true(check_client_infer_egress_observation(dependent) is Ok(_))
  assert_true(
    admit_client_infer_occurrence_egress(
      occurrence,
      client_infer_graph_test_execution(client_infer_prefix_test_program()),
      () => observed.val,
    )
    is Err(ForeignOwner),
  )
  observed.val = Some({
    classification: @environment.Public,
    region: "elsewhere",
    provider_retention: false,
    training_use: false,
  })
  assert_true(
    check_client_infer_egress_current(admission) is Err(ChangedObservation),
  )
  assert_true(
    check_client_infer_egress_observation(dependent) is Err(ChangedObservation),
  )
  observed.val = None
  assert_true(
    check_client_infer_egress_current(admission) is Err(MissingObservation),
  )
  assert_true(
    check_client_infer_egress_observation(dependent) is Err(MissingObservation),
  )
}

///|
test "joined task uses the existing Model barrier compiler with both inputs" {
  let prepared = client_composed_infer_test_program()
  let occurrence = prepared_client_composed_infer_occurrence(prepared).unwrap()
  let execution = client_infer_graph_test_execution(
    prepared,
    occurrence=Some(occurrence),
  )
  let issued = issue_prepared_client_composed_infer_plan_graph(
    occurrence,
    execution,
    "sha256:" + "b".repeat(64),
    "sha256:" + "c".repeat(64),
    run_materials_limits().sequence,
    100000,
    10000,
    100,
  ).unwrap()
  assert_eq(client_infer_plan_graph_coordinates(issued), (2, 2, 2))
  assert_true(client_infer_plan_graph_matches(issued, prepared, execution))
  assert_true(
    @checked.infer_item_limit_matches(
      issued.item_limit,
      @strategy.graph_program(prepared.graph),
      2,
      2,
    ),
  )
  assert_eq(@checked.infer_item_limit_maximum(issued.item_limit), 1L)
  let graph = parse_plan_identity_value(issued.graph.wire, 100000, 10000, 100).unwrap()
  guard @canonical.object_field(graph, "nodes") is Some(@canonical.Array(nodes)) &&
    @canonical.object_field(graph, "data_edges")
    is Some(@canonical.Array(edges)) &&
    @canonical.object_field(graph, "root_refs") is Some(@canonical.Array(roots)) else {
    fail("complete joined Model component")
  }
  let nodes = @canonical.array_values(nodes)
  assert_eq(nodes.length(), 2)
  assert_eq(@canonical.array_values(edges).length(), 1)
  assert_eq(@canonical.array_values(roots).length(), 1)
  assert_true(
    @canonical.object_field(nodes[1], "node_id")
    is Some(@canonical.String("task_2_infer_2")),
  )
  let inputs = @canonical.object_field(nodes[0], "input_contracts").unwrap()
  assert_true(@canonical.object_field(inputs, "left_rows") is Some(_))
  assert_true(@canonical.object_field(inputs, "right_rows") is Some(_))
  assert_eq(issued.input.node_id, "task_2_before_infer_2")
  assert_eq(issued.output.node_id, "task_2_infer_2")
  assert_true(
    issue_prepared_client_composed_infer_plan_graph(
      occurrence,
      client_infer_graph_test_execution(client_infer_prefix_test_program()),
      "sha256:" + "b".repeat(64),
      "sha256:" + "c".repeat(64),
      run_materials_limits().sequence,
      100000,
      10000,
      100,
    )
    is Err(ForeignExecution),
  )
}

///|
test "common graph connects independent producers to JOIN and the Model barrier" {
  let prepared = client_composed_infer_test_program()
  let occurrence = prepared_client_composed_infer_occurrence(prepared).unwrap()
  let execution = client_infer_graph_test_execution(
    prepared,
    occurrence=Some(occurrence),
  )
  let component = issue_prepared_client_composed_infer_plan_graph(
    occurrence,
    execution,
    "sha256:" + "b".repeat(64),
    "sha256:" + "c".repeat(64),
    run_materials_limits().sequence,
    100000,
    10000,
    100,
    include_results=false,
  ).unwrap()
  let issued = issue_prepared_client_composed_task_plan_graph(
    prepared,
    component,
    run_materials_limits().sequence,
    100000,
    10000,
    100,
  ).unwrap()
  let graph = parse_plan_identity_value(issued.wire, 100000, 10000, 100).unwrap()
  guard @canonical.object_field(graph, "nodes") is Some(@canonical.Array(nodes)) &&
    @canonical.object_field(graph, "data_edges")
    is Some(@canonical.Array(edges)) &&
    @canonical.object_field(graph, "root_refs") is Some(@canonical.Array(roots)) else {
    fail("complete common composed graph")
  }
  assert_eq(@canonical.array_values(nodes).length(), 4)
  assert_eq(@canonical.array_values(edges).length(), 3)
  let roots = @canonical.array_values(roots)
  assert_eq(roots.length(), 1)
  assert_true(
    @canonical.object_field(roots[0], "name")
    is Some(@canonical.String("answer")),
  )
  let from = @canonical.object_field(roots[0], "ref").unwrap()
  assert_true(
    @canonical.object_field(from, "node_id")
    is Some(@canonical.String("task_2_infer_2")),
  )
  assert_true(
    issue_prepared_client_composed_task_plan_graph(
      client_composed_infer_test_program(),
      component,
      run_materials_limits().sequence,
      100000,
      10000,
      100,
    )
    is Err(UnsupportedGraph),
  )
}

///|
fn client_composed_effect_test_environment(
  effect : @checked.CheckEnvironment,
) -> @checked.CheckEnvironment raise {
  let model = client_infer_prefix_test_program()
  let model_writer = @encode.writer(100000, 10000, 100)
  @environment.emit(
    @checked.checked_environment(@strategy.graph_program(model.graph)),
    model_writer,
  )
  let model_value = parse_plan_identity_value(
    @encode.finish(model_writer),
    100000,
    10000,
    100,
  ).unwrap()
  let tasks = @canonical.object_field(model_value, "model_task_contracts").unwrap()
  let effect_writer = @encode.writer(100000, 10000, 100)
  @environment.emit(@checked.checking_environment_wire(effect), effect_writer)
  let effect_value = parse_plan_identity_value(
    @encode.finish(effect_writer),
    100000,
    10000,
    100,
  ).unwrap()
  let writer = @encode.writer(100000, 10000, 100)
  @encode.begin_object(writer)
  for (key, value) in @canonical.object_fields(effect_value).unwrap() {
    if key == "evidence_bundle_cid" {
      continue
    }
    @encode.key(writer, key)
    @canonical.emit_value(
      if key == "model_task_contracts" {
        tasks
      } else {
        value
      },
      writer,
    )
  }
  @encode.end_object(writer)
  let unsigned = parse_plan_identity_value(
    @encode.finish(writer),
    100000,
    10000,
    100,
  ).unwrap()
  let cid = @canonical.cid_value(unsigned, 100000, 10000, 100)
  let wire = @canonical.stringify_value(
    @canonical.object_with_string_field(unsigned, "evidence_bundle_cid", cid).unwrap(),
    100000,
    10000,
    100,
  )
  admit_client_check_environment(
    wire,
    cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
}

///|
test "Effect compiler keeps the original Model barrier and KEEP in one Plan" {
  let (_, base, limits) = client_composed_effect_base_fixture()
  let environment = client_composed_effect_test_environment(base)
  let document =
    #|{"version":"actql/0.1","id":"infer-effect","stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"text":{"type":"string","nullable":true},"value":{"type":"number","nullable":false}},"rows":[{"id":"a","text":"hello","value":1}]},"as":"input"},{"assert_rows":{"unique_by":["id"]},"as":"joined"},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"text"}}},"as":"inferred"},{"join":{"with":"joined","kind":"inner","cardinality":"one_to_one","on":[{"left":"id","right":"id"}],"select":{"value":"right.value"}},"as":"selected"}],"results":{"out":{"from":"selected","fields":["value"]}},"effects":{"save":{"create":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"out"}}}}}],"results":{"published":{"from":{"stage":"source","result":"out"}}}}
  let owner = match
    prepare_client_effect_computation(
      document,
      Json,
      environment,
      None,
      [],
      limits,
    ) {
    Ok(owner) => owner
    Err(Candidate(@checked.Computation(issue))) => raise issue
    Err(Syntax(_)) => fail("Effect syntax")
    Err(Mapping(_)) => fail("Effect mapping")
    Err(Static(_)) => fail("Effect static")
    Err(Stage(_)) => fail("Effect stage")
    Err(Graph(_)) => fail("Effect graph")
    Err(_) => fail("composed Effect preparation")
  }
  let manifests = run_materials_manifests()
  assert_true(
    issue_prepared_client_effect_compilation(
      owner,
      manifests,
      run_materials_limits().sequence,
      1000,
      10000,
      100000,
      10000,
      100,
    )
    is Err(
      Graph(
        Fragment(
          Pipeline(Sequence(@lower.KernelFailure(2, @lower.MissingKernelNode)))
        )
      )
    ),
  )
  let occurrence = prepared_client_effect_infer_occurrence(owner).unwrap()
  let execution = client_infer_graph_test_execution(
    occurrence.owner,
    occurrence=Some(occurrence),
  )
  let component = issue_prepared_client_composed_infer_plan_graph(
    occurrence,
    execution,
    "sha256:" + "b".repeat(64),
    "sha256:" + "c".repeat(64),
    run_materials_limits().sequence,
    100000,
    10000,
    100,
    include_results=false,
  ).unwrap()
  let construction_input = {
    owner,
    components: [component],
    normalization: None,
  }
  let codec = {
    max_facts: 1000,
    max_witnesses: 10000,
    max_wire_bytes: 100000,
    max_nodes: 10000,
    max_depth: 100,
  }
  let storage = prepared_client_effect_measurement_storage(
    construction_input, codec,
  ).unwrap()
  assert_true(storage.record_headers > 0L && storage.reference_slots > 0L)
  let measured = measure_prepared_client_effect_compilation_construction(
    construction_input,
    manifests,
    run_materials_limits().sequence,
    codec,
  ).unwrap()
  assert_true(client_effect_compilation_construction_matches(measured, owner))
  assert_true(
    measure_prepared_client_model_compilation_construction(
      component.owner,
      [component],
      manifests,
      run_materials_limits().sequence,
      1000,
      10000,
      100000,
      10000,
      100,
    )
    is Err(TaskGraph(UnsupportedGraph)),
  )
  let compilation = issue_prepared_client_effect_compilation(
    owner,
    manifests,
    run_materials_limits().sequence,
    1000,
    10000,
    100000,
    10000,
    100,
    infer=Some(component),
  ).unwrap()
  assert_true(
    physical_equal(client_effect_compilation_owner(compilation), owner),
  )
  assert_true(physical_equal(compilation.compiled.infer.unwrap(), component))
  assert_eq(compilation.compiled.result_names, ["published"])
  let measured_geometry = client_effect_compilation_construction_geometry(
    measured,
  )
  let actual_plan = parse_plan_identity_value(
    compilation.compiled.plan.plan.wire,
    100000,
    10000,
    100,
  ).unwrap()
  for
    (name, bound) in [
      ("nodes", measured_geometry.nodes),
      ("data_edges", measured_geometry.edges),
      ("root_refs", measured_geometry.roots),
      ("execution_material", measured_geometry.material),
    ] {
    assert_compilation_geometry_covers(
      bound,
      @canonical.object_field(actual_plan, name).unwrap(),
    )
  }
  assert_compilation_geometry_covers(
    measured_geometry.executable_plan,
    actual_plan,
  )
  let allowed = issue_client_effect_allowed_run(
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = issue_client_effect_run_definition(
    allowed, "composed-scope", "composed-run", "2026-10-03T00:00:00.000Z", "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let host_policy_wire = "{\"classification\":\"unknown\",\"source_data_policy_cids\":[],\"source_response_policy_cids\":[],\"unknown_provenance\":true,\"version\":\"actql-effective-data-policy/0.1\"}"
  let host_policy_cid = "sha256:" + @sha.hex(@utf8.encode(host_policy_wire))
  assert_true(
    client_effect_allowed_infer_run(allowed) is Err(MissingResultPolicy),
  )
  let model_run = client_effect_allowed_infer_run_with_policy_body(
    allowed,
    Some(host_policy_cid),
    Some(host_policy_wire),
    1024,
    100,
    8,
  ).unwrap()
  assert_eq(client_compiled_run_has_infers(model_run), true)
  assert_eq(
    client_compiled_run_has_infers(model_run),
    !client_compiled_run_infers(model_run).is_empty(),
  )
  assert_true(
    client_effect_allowed_infer_run_with_policy_body(
      allowed,
      Some("sha256:" + "a".repeat(64)),
      Some(host_policy_wire),
      1024,
      100,
      8,
    )
    is Err(InvalidResultPolicy),
  )
  assert_true(client_compiled_run_matches_effect(model_run, owner, compilation))
  // Identical compilation bodies do not substitute their physical owner.
  let other_compilation = issue_prepared_client_effect_compilation(
    owner,
    manifests,
    run_materials_limits().sequence,
    1000,
    10000,
    100000,
    10000,
    100,
    infer=Some(component),
  ).unwrap()
  assert_false(
    client_compiled_run_matches_effect(model_run, owner, other_compilation),
  )
  let original = client_compiled_run_source_free_result_policy_body(model_run).unwrap()
  let result_policy = @publication.captured_effect_dependency_body_cid(original)
  assert_true(
    result_policy !=
    @environment.model_task_data_handling_cid(
      @environment.model_execution_task(component.execution),
    ),
  )
  assert_eq(
    client_compiled_run_infer_observation_policy(model_run),
    Some(result_policy),
  )
  assert_eq(
    @publication.captured_effect_dependency_body_json(original),
    host_policy_wire,
  )
  assert_true(
    @publication.admit_captured_effect_dependency_body(
      "data_policy",
      Some(result_policy),
      @publication.captured_effect_dependency_body_json(original),
      1024,
      100,
      8,
    )
    is Ok(_),
  )
  assert_true(
    check_client_compiled_run_definition(model_run, definition) is Ok(_),
  )
  assert_true(
    client_infer_occurrence_matches_compiled_run(occurrence, model_run),
  )
  assert_true(
    physical_equal(client_compiled_run_infer(model_run).unwrap(), component),
  )
  // The Model component shares the Effect admission, but cannot use an
  // Effect-free invocation issuer or substitute a second Run owner.
  assert_true(
    issue_client_compiled_source_free_task_invocation(
      model_run,
      definition,
      "sha256:" + "d".repeat(64),
      100000,
      10000,
      100,
    )
    is Err(_),
  )
  let plan = compilation.compiled.plan.plan
  let saved = admit_prepared_client_effect_compilation(
    owner,
    plan.wire,
    plan.fact_manifest_wire,
    @publication.run_evidence_value_json(compilation.compiled.template),
    @publication.publication_contract_json(compilation.compiled.compiled_plan),
    manifests,
    run_materials_limits().sequence,
    1000,
    10000,
    100000,
    10000,
    100,
    infer=Some(component),
  ).unwrap()
  assert_true(physical_equal(client_effect_compilation_owner(saved), owner))
  assert_true(
    admit_prepared_client_effect_compilation(
      owner,
      plan.wire,
      plan.fact_manifest_wire,
      @publication.run_evidence_value_json(compilation.compiled.template),
      @publication.publication_contract_json(compilation.compiled.compiled_plan),
      manifests,
      run_materials_limits().sequence,
      1000,
      10000,
      100000,
      10000,
      100,
    )
    is Err(Issue(Graph(_))),
  )
  let foreign = prepare_client_effect_computation(
    document,
    Json,
    environment,
    None,
    [],
    limits,
  ).unwrap()
  assert_true(
    issue_prepared_client_effect_compilation(
      foreign,
      manifests,
      run_materials_limits().sequence,
      1000,
      10000,
      100000,
      10000,
      100,
      infer=Some(component),
    )
    is Err(ForeignInferOwner),
  )
  assert_false(
    client_effect_compilation_construction_matches(measured, foreign),
  )
  assert_true(
    measure_prepared_client_effect_compilation_construction(
      { owner: foreign, components: [component], normalization: None, },
      manifests,
      run_materials_limits().sequence,
      codec,
    )
    is Err(TaskGraph(UnsupportedGraph)),
  )
  let template = parse_plan_identity_value(
    @publication.run_evidence_value_json(compilation.compiled.template),
    100000,
    10000,
    100,
  ).unwrap()
  guard @canonical.object_field(template, "required_profile_contracts")
    is Some(@canonical.Array(profiles)) else {
    fail("Model profile remains bound by the Effect template")
  }
  assert_eq(@canonical.array_values(profiles).length(), 1)
}

///|
test "two acquired roots JOIN INFER KEEP and downstream Effect compile together" {
  let (_, _, base_limits) = client_composed_effect_base_fixture()
  let limits = {
    ..base_limits,
    program: client_standard_program_preparation_limits(),
  }
  let base = admit_client_check_environment(
    local_normalization_environment_wire,
    "sha256:afebeb63f2e0e48434bf005f65ab0af8a0c2704f0afb5a8c70df72e91b26e86e",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let environment = client_composed_effect_test_environment(base)
  let document =
    #|{"version":"actql/0.1","id":"two-source-infer-effect","stages":[{"id":"left","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id >= 0"},{"select":["id","amount"],"as":"captured"}],"results":{"rows":{"from":"captured","fields":["id","amount"]}}},{"id":"right","inputs":{"remote":{"connector":"crm/right","resource":"r"}},"steps":[{"filter":"id >= 0"},{"select":["id","amount"],"as":"captured"}],"results":{"rows":{"from":"captured","fields":["id","amount"]}}},{"id":"classify","inputs":{"left_rows":{"result":{"stage":"left","result":"rows"}},"right_rows":{"result":{"stage":"right","result":"rows"}}},"steps":[{"from":"left_rows","join":{"with":"right_rows","kind":"inner","on":[{"left":"id","right":"id"}],"max_output_rows":2,"select":{"id":"left.id","value":"right.amount"}}},{"derive":{"text":{"literal":"hello"}}},{"assert_rows":{"unique_by":["id"]},"as":"joined"},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"text"}}},"as":"inferred"},{"join":{"with":"joined","kind":"inner","cardinality":"one_to_one","on":[{"left":"id","right":"id"}],"select":{"value":"right.value"}}},{"select":["value"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["value"]}}},{"id":"apply","inputs":{"classified":{"result":{"stage":"classify","result":"rows"}}},"steps":[{"filter":"value >= 1","as":"selected"}],"results":{"out":{"from":"selected","fields":["value"]}},"effects":{"save":{"create":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"out"}}}}}],"results":{"published":{"from":{"stage":"apply","result":"out"}}}}
  let owner = match
    prepare_client_effect_computation(
      document,
      Json,
      environment,
      None,
      [],
      limits,
    ) {
    Ok(owner) => owner
    Err(Candidate(@checked.Computation(issue))) => raise issue
    Err(Syntax(_)) => fail("Effect syntax")
    Err(Mapping(_)) => fail("Effect mapping")
    Err(Static(_)) => fail("Effect static")
    Err(Stage(_)) => fail("Effect stage")
    Err(Graph(_)) => fail("Effect graph")
    Err(_) => fail("acquired composed Effect preparation")
  }
  let occurrence = prepared_client_effect_infer_occurrence(owner).unwrap()
  assert_eq(client_infer_occurrence_coordinates(occurrence), (2, 2, 3))
  assert_true(
    issue_prepared_client_effect_compilation(
      owner,
      run_materials_manifests(),
      run_materials_limits().sequence,
      1000,
      10000,
      100000,
      10000,
      100,
    )
    is Err(
      Graph(
        Fragment(
          Pipeline(Sequence(@lower.KernelFailure(3, @lower.MissingKernelNode)))
        )
      )
    ),
  )
  let execution = client_infer_graph_test_execution(
    occurrence.owner,
    occurrence=Some(occurrence),
  )
  let component = issue_prepared_client_composed_infer_plan_graph(
    occurrence,
    execution,
    "sha256:" + "b".repeat(64),
    "sha256:" + "c".repeat(64),
    run_materials_limits().sequence,
    100000,
    10000,
    100,
    include_results=false,
  ).unwrap()
  let compilation = issue_prepared_client_effect_compilation(
    owner,
    run_materials_manifests(),
    run_materials_limits().sequence,
    1000,
    10000,
    100000,
    10000,
    100,
    infer=Some(component),
  ).unwrap()
  assert_true(
    physical_equal(client_effect_compilation_owner(compilation), owner),
  )
  assert_eq(compilation.compiled.result_names, ["published"])
  // Both independent captures remain prerequisites of the actual JOIN task.
  assert_eq(@strategy.graph_captured_prefix(occurrence.owner.graph), 2)
  let allowed = issue_client_effect_allowed_run(
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let model_run = client_effect_allowed_infer_run(allowed).unwrap()
  let source_policy = prepared_client_effect_publication_data_policy_cid(owner)
  assert_true(source_policy is Some(_))
  assert_true(
    client_effect_allowed_infer_run_with_policy_body(
      allowed,
      source_policy,
      Some(
        "{\"classification\":\"unknown\",\"source_data_policy_cids\":[],\"source_response_policy_cids\":[],\"unknown_provenance\":true,\"version\":\"actql-effective-data-policy/0.1\"}",
      ),
      1024,
      100,
      8,
    )
    is Err(InvalidResultPolicy),
  )
  assert_true(
    client_compiled_run_source_free_result_policy_body(model_run) is None,
  )
  assert_eq(
    client_compiled_run_infer_observation_policy(model_run),
    source_policy,
  )
  guard client_compiled_run_evaluation_policy_body(model_run)
    is Some((kind, policy_cid, wire)) else {
    fail("Source-backed Evidence needs the actual Result policy original")
  }
  assert_eq(kind, "data_policy")
  assert_eq(Some(policy_cid), source_policy)
  let policy = parse_plan_identity_value(wire, 16384, 1024, 20).unwrap()
  assert_true(
    @canonical.object_field(policy, "unknown_provenance")
    is Some(@canonical.Bool(true)),
  )
  guard @canonical.object_field(policy, "source_data_policy_cids")
    is Some(@canonical.Array(policies)) else {
    fail("Source constraints cannot be discarded by Evidence capture")
  }
  assert_eq(@canonical.array_values(policies).length(), 2)
  // The two declared source policies are unknown. A public provider-side
  // observation must not make their combined input eligible for dispatch.
  assert_true(
    admit_client_infer_occurrence_egress(occurrence, execution, () => {
      Some({
        classification: @environment.Public,
        region: "fixture-region",
        provider_retention: false,
        training_use: false,
      })
    })
    is Err(UnknownClassification),
  )
}

///|
test "composed Model construction geometry covers original repeated edges Results and final writer work" {
  for
    prepared in [
      client_infer_prefix_test_program(),
      client_composed_infer_test_program(),
      client_two_independent_infer_test_program(),
    ] {
    let bounds = run_materials_limits()
    let components = prepared_client_composed_infer_occurrences(prepared)
      .unwrap()
      .map(occurrence => {
        issue_installed_client_composed_infer_plan_graph(
          occurrence,
          client_infer_graph_test_execution(
            prepared,
            occurrence=Some(occurrence),
          ),
          bounds.sequence,
          bounds.max_evidence_bytes,
          bounds.max_evidence_nodes,
          bounds.max_evidence_depth,
        ).unwrap()
      })
    let geometry = measure_prepared_client_model_compilation_construction(
      prepared,
      components,
      run_materials_manifests(),
      bounds.sequence,
      bounds.max_sequence_steps,
      bounds.max_sequence_work,
      bounds.max_evidence_bytes,
      bounds.max_evidence_nodes,
      bounds.max_evidence_depth,
    ).unwrap()
    let count = Ref(-1L)
    let compiled = observe_prepared_client_multi_infer_plan_encoding(
      prepared,
      components,
      run_materials_manifests(),
      bounds.sequence,
      bounds.max_sequence_steps,
      bounds.max_sequence_work,
      bounds.max_evidence_bytes,
      bounds.max_evidence_nodes,
      bounds.max_evidence_depth,
      nodes_out=count,
    ).unwrap()
    let parsed = @source.parse_json_bytes_measured(
      @utf8.encode(compiled.plan.plan.wire),
      {
        max_input_bytes: bounds.max_evidence_bytes,
        max_nodes: bounds.max_evidence_nodes,
        max_depth: bounds.max_evidence_depth,
      },
    ).unwrap()
    assert_eq(count.val, 2L * parsed.usage.nodes.to_int64() - 1L)
    assert_true(parsed.usage.input_bytes <= geometry.executable_plan.0)
    assert_true(parsed.usage.nodes <= geometry.executable_plan.1)
    assert_true(parsed.usage.depth <= geometry.executable_plan.2)
    assert_eq(geometry.borrowed_inputs.length(), components.length())
    assert_eq(
      geometry.fragments.length() + components.length(),
      @strategy.graph_task_count(prepared.graph),
    )
    for index in 0..<components.length() {
      assert_true(physical_equal(compiled.infers[index], components[index]))
    }
    let limits = client_standard_pure_compilation_limits()
    let units = prepared_client_model_measurement_storage(
      prepared, components, limits,
    ).unwrap()
    assert_true(
      units ==
      prepared_client_model_measurement_storage(prepared, components, {
        ..limits,
        max_wire_bytes: 2000000,
        max_nodes: 200000,
        max_depth: 200,
      }).unwrap(),
    )
  }
}

///|
test "composed Model measurement retains foreign inventory refusal and bounded compiler failure prefix" {
  let (prepared, component) = original_infer_graph_parts_fixture()
  let bounds = run_materials_limits()
  let measure = (value, components) => {
    measure_prepared_client_model_compilation_construction(
      value,
      components,
      run_materials_manifests(),
      bounds.sequence,
      bounds.max_sequence_steps,
      bounds.max_sequence_work,
      bounds.max_evidence_bytes,
      bounds.max_evidence_nodes,
      bounds.max_evidence_depth,
    )
  }
  assert_true(
    measure(client_infer_prefix_test_program(), [component]) is Err(_),
  )
  assert_true(measure(prepared, [component, component]) is Err(_))
  measure(prepared, [component]).unwrap() |> ignore
  let successful = issue_prepared_client_multi_infer_compilation(
    prepared,
    [component],
    run_materials_manifests(),
    bounds.sequence,
    bounds.max_sequence_steps,
    bounds.max_sequence_work,
    bounds.max_evidence_bytes,
    bounds.max_evidence_nodes,
    bounds.max_evidence_depth,
  ).unwrap()
  let original = @source.parse_json_bytes_measured(
    @utf8.encode(successful.plan.plan.wire),
    {
      max_input_bytes: bounds.max_evidence_bytes,
      max_nodes: bounds.max_evidence_nodes,
      max_depth: bounds.max_evidence_depth,
    },
  ).unwrap()
  let one_short = original.usage.nodes - 1
  let count = Ref(-1L)
  let result = observe_prepared_client_multi_infer_plan_encoding(
    prepared,
    [component],
    run_materials_manifests(),
    bounds.sequence,
    bounds.max_sequence_steps,
    bounds.max_sequence_work,
    bounds.max_evidence_bytes,
    one_short,
    bounds.max_evidence_depth,
    nodes_out=count,
  )
  assert_true(result is Err(_))
  assert_true(count.val >= 0L && count.val <= 2L * one_short.to_int64())
}

///|
test "plural inventory count does not admit two Model boundaries inside one Whole Unit" {
  let authored =
    #|{"version":"actql/0.1","id":"same-unit-model-boundaries","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"text":{"type":"string","nullable":false}},"rows":[{"id":"a","text":"original"}]},"as":"items"},{"assert_rows":{"unique_by":["id"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"text"}}},"as":"first"},{"select":["id"]},{"derive":{"text":{"literal":"second"}}},{"assert_rows":{"unique_by":["id"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"text"}}},"as":"second"}],"results":{"rows":{"from":"second","fields":["id","outcome","value"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  let prepared = client_composed_infer_test_program(authored=Some(authored))
  let program = @strategy.graph_program(prepared_client_graph(prepared))
  assert_true(
    @checked.prepare_infer_input_policy(
      program, 0, 6, 1000000, 1000000, 100000, 100,
    )
    is Some(@checked.CheckedSources(@environment.Unknown)),
  )
  assert_true(prepared_client_composed_infer_occurrences(prepared) is None)
  assert_true(prepared_client_composed_infer_occurrence(prepared) is None)
}

///|
test "a direct same-Unit Model input identifies its predecessor without enabling the compiled route" {
  let authored =
    #|{"version":"actql/0.1","id":"same-unit-dependent-model-boundary","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"text":{"type":"string","nullable":false}},"rows":[{"id":"a","text":"original"}]},"as":"items"},{"assert_rows":{"unique_by":["id"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"text"}}},"as":"first"},{"assert_rows":{"unique_by":["id"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"outcome"}}},"as":"second"}],"results":{"rows":{"from":"second","fields":["id","outcome","value"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  let prepared = client_composed_infer_test_program(authored=Some(authored))
  let program = @strategy.graph_program(prepared_client_graph(prepared))
  guard @checked.prepare_infer_input_policy(
      program, 0, 4, 1000000, 1000000, 100000, 100,
    )
    is Some(@checked.PendingModelOutputs(waiting)) else {
    fail("the second checked occurrence must identify its first Model input")
  }
  assert_true(@checked.checked_infer_model_inputs_match(waiting, program, 0, 4))
  assert_eq(@checked.checked_infer_model_inputs_count(waiting), 1)
  assert_eq(@checked.checked_infer_model_input_at(waiting, 0), Some((0, 2)))
  assert_true(prepared_client_composed_infer_occurrences(prepared) is None)
  assert_true(prepared_client_composed_infer_occurrence(prepared) is None)
}
