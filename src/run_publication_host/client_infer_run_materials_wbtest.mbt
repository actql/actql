///|
fn infer_run_materials_fixture() -> (
  PreparedClientProgram,
  ClientCompiledRun,
  @publication.PublicationContract,
  String,
) raise {
  let prepared = client_infer_prefix_test_program()
  let (environment_wire, environment) = client_infer_prefix_test_environment()
  let bounds = run_materials_limits()
  let graph = issue_installed_client_infer_plan_graph(
    prepared,
    2,
    client_infer_graph_test_execution(prepared),
    bounds.sequence,
    bounds.max_evidence_bytes,
    bounds.max_evidence_nodes,
    bounds.max_evidence_depth,
  ).unwrap()
  let compilation = issue_prepared_client_infer_compilation(
    prepared,
    graph,
    run_materials_manifests(),
    bounds.max_sequence_steps,
    bounds.max_sequence_work,
    bounds.max_evidence_bytes,
    bounds.max_evidence_nodes,
    bounds.max_evidence_depth,
  ).unwrap()
  let compiled = issue_client_task_compiled_run(
    prepared,
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = issue_client_compiled_run_definition(
    compiled, "original-model-scope", "original-model-run", "2026-10-01T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let writer = @encode.writer(65536, 8192, 64)
  @syntax.emit_program_source(prepared.source, writer)
  let program = @encode.finish(writer)
  let materials = issue_client_infer_run_materials(
    compiled,
    definition,
    environment,
    environment_wire,
    program,
    None,
    bounds,
  ).unwrap()
  (prepared, compiled, definition, materials)
}

///|
fn infer_run_materials_admit(
  wire : String,
  definition : @publication.PublicationContract,
) -> Result[ClientTaskRunMaterials, ClientTaskRunMaterialsIssue] {
  admit_client_infer_run_materials(
    wire,
    @publication.publication_contract_identity(definition),
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    run_materials_manifests(),
    run_materials_limits(),
  )
}

///|
fn composed_infer_run_materials_fixture() -> (
  PreparedClientProgram,
  ClientCompiledRun,
  @publication.PublicationContract,
  String,
) raise {
  // This current admission fixture preserves both original Source members and
  // their reviewed dependency roles in canonical digest order. Historical
  // unsorted preimages remain independently tested in local_environment_order_history.
  let source = parse_plan_identity_value(
    client_composed_acquired_effect_environment, 65536, 4096, 64,
  ).unwrap()
  guard @canonical.object_field(source, "connector_capabilities")
    is Some(@canonical.Array(capabilities)) else {
    fail("original capability inventory")
  }
  let caps = @canonical.array_values(capabilities)
  assert_eq(caps.length(), 2)
  assert_true(
    @canonical.cid_value(caps[0], 65536, 4096, 64) <
    @canonical.cid_value(caps[1], 65536, 4096, 64),
  )
  let writer = @encode.writer(65536, 4096, 64)
  @encode.begin_object(writer)
  for (key, value) in @canonical.object_fields(source).unwrap() {
    if key == "evidence_bundle_cid" {
      continue
    }
    @encode.key(writer, key)
    if key == "connector_capabilities" {
      @encode.begin_array(writer)
      @canonical.emit_value(caps[0], writer)
      @canonical.emit_value(caps[1], writer)
      @encode.end_array(writer)
    } else {
      @canonical.emit_value(value, writer)
    }
  }
  @encode.end_object(writer)
  let unsigned = parse_plan_identity_value(
    @encode.finish(writer),
    65536,
    4096,
    64,
  ).unwrap()
  let cid = @canonical.cid_value(unsigned, 65536, 4096, 64)
  let original_environment = @canonical.stringify_value(
    @canonical.object_with_string_field(unsigned, "evidence_bundle_cid", cid).unwrap(),
    65536,
    4096,
    64,
  )
  let base = admit_client_check_environment(
    original_environment,
    cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let environment = client_composed_effect_test_environment(base)
  let document =
    #|{"version":"actql/0.1","id":"saved-two-source-infer","stages":[{"id":"left","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id >= 0"},{"select":["id","amount"],"as":"captured"}],"results":{"rows":{"from":"captured","fields":["id","amount"]}}},{"id":"right","inputs":{"remote":{"connector":"crm/right","resource":"r"}},"steps":[{"filter":"id >= 0"},{"select":["id","amount"],"as":"captured"}],"results":{"rows":{"from":"captured","fields":["id","amount"]}}},{"id":"classify","inputs":{"left_rows":{"result":{"stage":"left","result":"rows"}},"right_rows":{"result":{"stage":"right","result":"rows"}}},"steps":[{"from":"left_rows","join":{"with":"right_rows","kind":"inner","on":[{"left":"id","right":"id"}],"max_output_rows":2,"select":{"id":"left.id","amount":"right.amount"}}},{"derive":{"text":{"literal":"original source input"}}},{"assert_rows":{"unique_by":["id"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"text"}}},"as":"captured"}],"results":{"rows":{"from":"captured","fields":["id","outcome","value"]}}}],"results":{"answer":{"from":{"stage":"classify","result":"rows"}}}}
  let prepared = prepare_effect_free_client_program(
    document,
    Json,
    environment,
    None,
    client_standard_program_preparation_limits(),
  ).unwrap()
  assert_eq(prepared_client_acquisition_count(prepared), 2)
  assert_eq(prepared_client_infer_step(prepared), None)
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
  let compilation = issue_prepared_client_multi_infer_compilation(
    prepared,
    [graph],
    run_materials_manifests(),
    bounds.sequence,
    bounds.max_sequence_steps,
    bounds.max_sequence_work,
    bounds.max_evidence_bytes,
    bounds.max_evidence_nodes,
    bounds.max_evidence_depth,
  ).unwrap()
  assert_true(compilation.infer is None)
  let compiled = issue_client_task_compiled_run(
    prepared,
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = issue_client_compiled_run_definition(
    compiled, "original-model-scope", "original-two-source-run", "2026-10-01T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let wire = issue_prepared_client_infer_run_materials(
    compiled,
    definition,
    environment,
    None,
    bounds,
  ).unwrap()
  (prepared, compiled, definition, wire)
}

///|
test "saved composed INFER retains both original Sources same graph policy and complete Run" {
  let (prepared, compiled, definition, wire) = composed_infer_run_materials_fixture()
  let restored = infer_run_materials_admit(wire, definition).unwrap()
  let inverse = client_task_run_materials_compiled_original(restored).unwrap()
  assert_eq(prepared_client_acquisition_count(restored.prepared), 2)
  assert_eq(
    prepared_client_identity(restored.prepared),
    prepared_client_identity(prepared),
  )
  assert_false(physical_equal(restored.prepared, prepared))
  assert_eq(
    @publication.publication_contract_json(restored.run_definition),
    @publication.publication_contract_json(definition),
  )
  let original_graph = client_compiled_run_infers(compiled)[0]
  let inverse_graph = client_compiled_run_infers(inverse)[0]
  assert_eq(inverse_graph.graph.wire, original_graph.graph.wire)
  assert_eq(
    (inverse_graph.task, inverse_graph.stage, inverse_graph.source_ordinal),
    (2, 2, 3),
  )
  assert_true(physical_equal(inverse_graph.owner, restored.prepared))
  assert_false(physical_equal(inverse_graph.owner, prepared))
  assert_eq(
    @environment.model_execution_cid(inverse_graph.execution),
    @environment.model_execution_cid(original_graph.execution),
  )
  assert_true(client_compiled_run_evaluation_policy_body(compiled) is Some(_))
  assert_eq(
    client_compiled_run_evaluation_policy_body(inverse),
    client_compiled_run_evaluation_policy_body(compiled),
  )
  assert_true(
    client_compiled_run_source_free_result_policy_body(inverse) is None,
  )
}

///|
test "saved composed INFER refuses changed Run source contract Program and execution originals" {
  let (_, _, definition, wire) = composed_infer_run_materials_fixture()
  for
    changed in [
      wire.replace(old="original-two-source-run", new="another-run"),
      wire.replace(old="crm/right", new="crm/foreign"),
      wire.replace(old="original source input", new="replaced source input"),
      wire.replace(old="fixture-risk-model", new="new-current-model"),
    ] {
    assert_true(changed != wire)
    assert_true(infer_run_materials_admit(changed, definition) is Err(_))
  }
}

///|
fn plural_infer_run_materials_fixture() -> (
  PreparedClientProgram,
  ClientCompiledRun,
  @publication.PublicationContract,
  String,
) raise {
  let prepared = client_two_independent_infer_test_program()
  assert_true(prepared_client_composed_infer_occurrence(prepared) is None)
  let bounds = run_materials_limits()
  let components = prepared_client_composed_infer_occurrences(prepared)
    .unwrap()
    .map(occurrence => {
      issue_installed_client_composed_infer_plan_graph(
        occurrence,
        client_infer_graph_test_execution(prepared, occurrence=Some(occurrence)),
        bounds.sequence,
        bounds.max_evidence_bytes,
        bounds.max_evidence_nodes,
        bounds.max_evidence_depth,
      ).unwrap()
    })
  let compilation = issue_prepared_client_multi_infer_compilation(
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
  let compiled = issue_client_task_compiled_run(
    prepared,
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = issue_client_compiled_run_definition(
    compiled, "original-model-scope", "two-original-models", "2026-10-01T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let (_, environment) = client_infer_prefix_test_environment()
  let wire = issue_prepared_client_infer_run_materials(
    compiled,
    definition,
    environment,
    None,
    bounds,
  ).unwrap()
  (prepared, compiled, definition, wire)
}

///|
fn plural_infer_run_materials_entries(
  wire : String,
) -> Array[@canonical.CanonicalValue] raise {
  let body = parse_plan_identity_value(wire, 262144, 32, 2).unwrap()
  guard @canonical.object_field(body, "infer_execution_contracts_json")
    is Some(@canonical.String(inventory)) &&
    parse_plan_identity_value(inventory, 100000, 10000, 100)
    is Some(@canonical.Array(entries)) else {
    fail("original plural Model inventory")
  }
  @canonical.array_values(entries)
}

///|
fn plural_infer_run_materials_with_entries(
  wire : String,
  entries : Array[@canonical.CanonicalValue],
) -> String raise {
  let writer = @encode.writer(100000, 10000, 100)
  @encode.begin_array(writer)
  for entry in entries {
    @canonical.emit_value(entry, writer)
  }
  @encode.end_array(writer)
  let body = parse_plan_identity_value(wire, 262144, 32, 2).unwrap()
  @canonical.stringify_value(
    @canonical.object_with_string_field(
      @canonical.object_without_field(body, "infer_execution_contracts_json").unwrap(),
      "infer_execution_contracts_json",
      @encode.finish(writer),
    ).unwrap(),
    262144,
    32,
    2,
  )
}

///|
test "saved plural INFER retains every original occurrence and the complete Run without singular selection" {
  let (prepared, compiled, definition, wire) = plural_infer_run_materials_fixture()
  let restored = infer_run_materials_admit(wire, definition).unwrap()
  let inverse = client_task_run_materials_compiled_original(restored).unwrap()
  let graphs = client_compiled_run_infers(inverse)
  assert_eq(graphs.length(), 2)
  assert_true(
    prepared_client_composed_infer_occurrence(restored.prepared) is None,
  )
  assert_false(physical_equal(restored.prepared, prepared))
  for index in 0..<graphs.length() {
    let original = client_compiled_run_infers(compiled)[index]
    assert_eq(graphs[index].graph.wire, original.graph.wire)
    assert_eq(
      client_infer_occurrence_coordinates(graphs[index].occurrence),
      client_infer_occurrence_coordinates(original.occurrence),
    )
    assert_true(physical_equal(graphs[index].owner, restored.prepared))
    assert_true(
      client_infer_occurrence_matches_plan(
        graphs[index].occurrence,
        graphs[index],
      ),
    )
    assert_false(
      client_infer_occurrence_matches_plan(original.occurrence, graphs[index]),
    )
  }
  // Repeated Task/execution DATA is valid only for these distinct occurrences.
  assert_eq(
    @environment.model_execution_cid(graphs[0].execution),
    @environment.model_execution_cid(graphs[1].execution),
  )
  assert_eq(
    @publication.publication_contract_json(restored.run_definition),
    @publication.publication_contract_json(definition),
  )
  assert_eq(
    client_compiled_run_evaluation_policy_body(inverse),
    client_compiled_run_evaluation_policy_body(compiled),
  )
  assert_eq(
    client_compiled_run_source_free_result_policy_body(inverse).map(body => {
      @publication.captured_effect_dependency_body_json(body)
    }),
    client_compiled_run_source_free_result_policy_body(compiled).map(body => {
      @publication.captured_effect_dependency_body_json(body)
    }),
  )
  assert_true(wire.contains("infer_execution_contracts_json"))
  assert_false(wire.contains("\"infer_execution_contract_cid\""))
}

///|
test "saved plural INFER refuses omitted duplicate swapped foreign and corrupt inventory" {
  let (_, _, definition, wire) = plural_infer_run_materials_fixture()
  let entries = plural_infer_run_materials_entries(wire)
  let foreign = @canonical.object_with_replaced_fields(entries[0], [
    ("task", parse_plan_identity_value("99", 16, 2, 2).unwrap()),
  ]).unwrap()
  let missing = @canonical.object_without_field(
    entries[0],
    "execution_contract_json",
  ).unwrap()
  let corrupt = @canonical.object_with_string_field(
    @canonical.object_without_field(entries[0], "execution_contract_cid").unwrap(),
    "execution_contract_cid",
    "sha256:" + "0".repeat(64),
  ).unwrap()
  for
    changed in [
      [],
      [entries[0]],
      [entries[0], entries[0]],
      [entries[1], entries[0]],
      [foreign, entries[1]],
      [missing, entries[1]],
      [corrupt, entries[1]],
      [entries[0], entries[1], entries[1]],
    ] {
    assert_true(
      infer_run_materials_admit(
        plural_infer_run_materials_with_entries(wire, changed),
        definition,
      )
      is Err(_),
    )
  }
  for
    changed in [
      wire.replace(old="two-original-models", new="another-run"),
      wire.replace(old="fixture-risk-model", new="current-other-model"),
      wire.replace(
        old="infer_execution_contracts_json",
        new="foreign_contracts_json",
      ),
    ] {
    assert_true(changed != wire)
    assert_true(infer_run_materials_admit(changed, definition) is Err(_))
  }
  let body = parse_plan_identity_value(wire, 262144, 32, 2).unwrap()
  let first = entries[0]
  guard @canonical.object_field(first, "execution_contract_cid")
    is Some(@canonical.String(cid)) &&
    @canonical.object_field(first, "execution_contract_json")
    is Some(@canonical.String(contract)) else {
    fail("original execution contract")
  }
  let both = @canonical.object_with_string_field(
    @canonical.object_with_string_field(
      body, "infer_execution_contract_cid", cid,
    ).unwrap(),
    "infer_execution_contract_json",
    contract,
  ).unwrap()
  assert_true(
    infer_run_materials_admit(
      @canonical.stringify_value(both, 262144, 32, 2),
      definition,
    )
    is Err(Input(MaterialsMalformed)),
  )
  let wrong_shape = @canonical.object_with_replaced_fields(body, [
    (
      "infer_execution_contracts_json",
      parse_plan_identity_value("null", 16, 2, 2).unwrap(),
    ),
  ]).unwrap()
  assert_true(
    infer_run_materials_admit(
      @canonical.stringify_value(wrong_shape, 262144, 32, 2),
      definition,
    )
    is Err(Input(MaterialsMalformed)),
  )
}

///|
test "saved plural INFER remains bounded and refuses Values Source and Effect readers" {
  let (prepared, _, definition, wire) = plural_infer_run_materials_fixture()
  let body = parse_plan_identity_value(wire, 262144, 32, 2).unwrap()
  guard @canonical.object_field(body, "infer_execution_contracts_json")
    is Some(@canonical.String(inventory)) else {
    fail("original plural inventory")
  }
  assert_true(
    read_plural_client_infer_run_graphs(
      prepared,
      inventory,
      run_materials_limits(),
    )
    is Ok(_),
  )
  assert_true(
    read_plural_client_infer_run_graphs(prepared, inventory, {
      ..run_materials_limits(),
      max_evidence_bytes: @utf8.encode(inventory).length() - 1,
    })
    is Err(_),
  )
  assert_true(
    read_plural_client_infer_run_graphs(prepared, inventory, {
      ..run_materials_limits(),
      max_evidence_nodes: 1,
    })
    is Err(_),
  )
  let cid = @publication.publication_contract_identity(definition)
  let expressions : @context.ExpressionProfiles = {
    text_time: false,
    veca: false,
  }
  let operations : @context.PureOperationProfiles = {
    rela: true,
    sga: false,
    tea: false,
    calendar: false,
    text_rank: false,
  }
  assert_true(
    admit_client_values_run_materials(
      wire,
      cid,
      expressions,
      operations,
      run_materials_manifests(),
      run_materials_limits(),
    )
    is Err(MaterialsEvidence("infer_execution_contracts")),
  )
  assert_true(
    admit_client_task_run_materials(
      wire,
      cid,
      expressions,
      operations,
      run_materials_manifests(),
      run_materials_limits(),
    )
    is Err(Input(MaterialsEvidence("infer_execution_contracts"))),
  )
  assert_true(
    admit_client_run_materials(
      wire,
      cid,
      expressions,
      operations,
      run_materials_manifests(),
      run_materials_limits(),
    )
    is Err(Values(MaterialsEvidence("infer_execution_contracts"))),
  )
  assert_true(
    admit_client_effect_run_materials(
      wire,
      cid,
      expressions,
      operations,
      run_materials_manifests(),
      run_materials_limits(),
      client_standard_effect_computation_limits(),
    )
    is Err(Input(MaterialsEvidence("infer_execution_contracts"))),
  )
}

///|
test "prepared INFER material projection preserves original source Environment and bytes" {
  let (_, compiled, definition, wire) = infer_run_materials_fixture()
  let (_, environment) = client_infer_prefix_test_environment()
  let projected = issue_prepared_client_infer_run_materials(
    compiled,
    definition,
    environment,
    None,
    run_materials_limits(),
  ).unwrap()
  assert_eq(projected, wire)
  let restored = infer_run_materials_admit(projected, definition).unwrap()
  let original = client_task_run_materials_compiled_original(restored).unwrap()
  assert_eq(
    @publication.run_evidence_value_json(original.prepared),
    @publication.run_evidence_value_json(compiled.prepared),
  )
}

///|
test "saved INFER materials retain exact original Task settings and same Run" {
  let (prepared, original, definition, wire) = infer_run_materials_fixture()
  let restored = infer_run_materials_admit(wire, definition).unwrap()
  let compiled = client_task_run_materials_compiled_original(restored).unwrap()
  assert_eq(
    @publication.publication_contract_json(restored.run_definition),
    @publication.publication_contract_json(definition),
  )
  assert_eq(
    prepared_client_identity(restored.prepared),
    prepared_client_identity(prepared),
  )
  assert_false(physical_equal(restored.prepared, prepared))
  let original_graph = client_compiled_run_infer(original).unwrap()
  let restored_graph = client_compiled_run_infer(compiled).unwrap()
  assert_true(
    client_infer_plan_graph_matches(
      restored_graph,
      restored.prepared,
      restored_graph.execution,
    ),
  )
  assert_false(
    client_infer_plan_graph_matches(
      restored_graph,
      prepared,
      original_graph.execution,
    ),
  )
  assert_eq(
    client_infer_plan_graph_wire(restored_graph),
    client_infer_plan_graph_wire(original_graph),
  )
  assert_eq(
    @environment.model_task_identity(
      @environment.model_execution_task(restored_graph.execution),
    ),
    @environment.model_task_identity(
      @environment.model_execution_task(original_graph.execution),
    ),
  )
  assert_eq(
    @environment.model_execution_cid(restored_graph.execution),
    @environment.model_execution_cid(original_graph.execution),
  )
  assert_eq(client_compiled_run_infer_observation_policy(compiled), None)
  assert_true(
    issue_client_compiled_source_free_task_invocation(
      compiled,
      restored.run_definition,
      "sha256:" + "c".repeat(64),
      100000,
      10000,
      100,
    )
    is Err(_),
  )
}

///|
test "saved INFER materials refuse another Run and replaced original contract" {
  let (_, _, definition, wire) = infer_run_materials_fixture()
  let changed_run = wire.replace(
    old="original-model-run",
    new="foreign-model-run",
  )
  assert_true(changed_run != wire)
  assert_true(infer_run_materials_admit(changed_run, definition) is Err(_))
  for
    changed in [
      wire.replace(
        old="564c77f8cde8da49fda0b61b072ddce8ee598116eada536c71d27457f1b478da",
        new="0".repeat(64),
      ),
      wire.replace(old="fixture-risk-model", new="current-other-model"),
      wire.replace(
        old="max_output_tokens\\\":32",
        new="max_output_tokens\\\":31",
      ),
      wire.replace(old="temperature\\\":0", new="temperature\\\":1"),
    ] {
    assert_true(changed != wire)
    assert_true(infer_run_materials_admit(changed, definition) is Err(_))
  }
}

///|
test "saved INFER materials do not enter legacy Values or ordinary Task readers" {
  let (_, _, definition, wire) = infer_run_materials_fixture()
  let cid = @publication.publication_contract_identity(definition)
  let expressions : @context.ExpressionProfiles = {
    text_time: false,
    veca: false,
  }
  let operations : @context.PureOperationProfiles = {
    rela: true,
    sga: false,
    tea: false,
    calendar: false,
    text_rank: false,
  }
  assert_true(
    admit_client_values_run_materials(
      wire,
      cid,
      expressions,
      operations,
      run_materials_manifests(),
      run_materials_limits(),
    )
    is Err(MaterialsEvidence("infer_execution_contract")),
  )
  assert_true(
    admit_client_task_run_materials(
      wire,
      cid,
      expressions,
      operations,
      run_materials_manifests(),
      run_materials_limits(),
    )
    is Err(Input(MaterialsEvidence("infer_execution_contract"))),
  )
  let missing = wire.replace(
    old="infer_execution_contract_cid",
    new="foreign_execution_contract_cid",
  )
  assert_true(
    infer_run_materials_admit(missing, definition)
    is Err(Input(MaterialsMalformed)),
  )
}

///|
test "saved INFER projection refuses foreign preparation and substituted Environment" {
  let (prepared, compiled, definition, _) = infer_run_materials_fixture()
  let (environment_wire, environment) = client_infer_prefix_test_environment()
  let writer = @encode.writer(65536, 8192, 64)
  @syntax.emit_program_source(prepared.source, writer)
  let program = @encode.finish(writer)
  let foreign = client_infer_prefix_test_program()
  assert_true(
    issue_client_infer_run_materials(
      { ..compiled, owner: foreign, },
      definition,
      environment,
      environment_wire,
      program,
      None,
      run_materials_limits(),
    )
    is Err(Binding(ForeignRun)),
  )
  let (changed_wire, changed) = client_infer_prefix_test_environment(
    host_items=999,
  )
  assert_true(
    issue_client_infer_run_materials(
      compiled,
      definition,
      changed,
      changed_wire,
      program,
      None,
      run_materials_limits(),
    )
    is Err(Input(MaterialsEnvironment)),
  )
}

///|
test "saved INFER projection refuses custom dependency graphs before material issuance" {
  let prepared = client_infer_prefix_test_program()
  let bounds = run_materials_limits()
  let custom = client_infer_material_test_graph(prepared)
  let compilation = issue_prepared_client_infer_compilation(
    prepared,
    custom,
    run_materials_manifests(),
    bounds.max_sequence_steps,
    bounds.max_sequence_work,
    bounds.max_evidence_bytes,
    bounds.max_evidence_nodes,
    bounds.max_evidence_depth,
  ).unwrap()
  let compiled = issue_client_task_compiled_run(
    prepared,
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = issue_client_compiled_run_definition(
    compiled, "original-model-scope", "original-model-run", "2026-10-01T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let (environment_wire, environment) = client_infer_prefix_test_environment()
  let writer = @encode.writer(65536, 8192, 64)
  @syntax.emit_program_source(prepared.source, writer)
  assert_true(
    issue_client_infer_run_materials(
      compiled,
      definition,
      environment,
      environment_wire,
      @encode.finish(writer),
      None,
      bounds,
    )
    is Err(Binding(UnsupportedProgram)),
  )
}

///|
test "plural saved inventory uses original checked Model occurrences beyond128 and caller codec limits" {
  let stages = [
    (
      #|{"id":"input","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false}},"rows":[{"id":"a"}]},"as":"items"}],"results":{"rows":{"from":"items","fields":["id"]}}}
    ),
  ]
  for index in 0..<129 {
    let previous = if index == 0 {
      "input"
    } else {
      "model_" + (index - 1).to_string()
    }
    stages.push(
      "{\"id\":\"model_" +
      index.to_string() +
      "\",\"inputs\":{\"rows\":{\"result\":{\"stage\":\"" +
      previous +
      "\",\"result\":\"rows\"}}},\"steps\":[{\"select\":[\"id\"]},{\"derive\":{\"text\":{\"literal\":\"original\"}}},{\"assert_rows\":{\"unique_by\":[\"id\"]}},{\"infer\":{\"contract\":\"model-task:risk-score.v1\",\"key\":\"id\",\"input\":{\"text\":{\"field\":\"text\"}}},\"as\":\"assessment\"}],\"results\":{\"rows\":{\"from\":\"assessment\",\"fields\":[\"id\",\"outcome\",\"value\"]}}}",
    )
  }
  let authored = "{\"version\":\"actql/0.1\",\"id\":\"complete-model-inventory\",\"stages\":[" +
    stages.join(",") +
    "],\"results\":{\"answer\":{\"from\":{\"stage\":\"model_128\",\"result\":\"rows\"}}}}"
  let fixture = client_infer_prefix_test_program()
  let environment = @checked.checking_environment(
    @checked.checked_environment(@strategy.graph_program(fixture.graph)),
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    model_tasks=@checked.checked_model_tasks(
      @strategy.graph_program(fixture.graph),
    ),
  )
  // Explicit finite caller profile; preserve one Model per Whole Unit.
  let preparation = client_standard_program_preparation_limits()
  let prepared = prepare_effect_free_client_program(
    authored,
    Json,
    environment,
    None,
    {
      ..preparation,
      checking: {
        input: { ..preparation.checking.input, max_stages: 130, },
        compilation: {
          ..preparation.checking.compilation,
          structure: {
            ..preparation.checking.compilation.structure,
            stages: 130,
          },
        },
      },
    },
  ).unwrap()
  let occurrences = prepared_client_composed_infer_occurrences(prepared).unwrap()
  assert_eq(occurrences.length(), 129)
  // Explicit finite codec bounds for this larger authored fixture. No normal
  // preparation/Run policy is increased, and no physical backing is asserted.
  let bounds = {
    ..run_materials_limits(),
    max_evidence_bytes: 1000000,
    max_evidence_nodes: 100000,
  }
  let graphs = occurrences.map(occurrence => {
    issue_installed_client_composed_infer_plan_graph(
      occurrence,
      client_infer_graph_test_execution(prepared, occurrence=Some(occurrence)),
      bounds.sequence,
      bounds.max_evidence_bytes,
      bounds.max_evidence_nodes,
      bounds.max_evidence_depth,
    ).unwrap()
  })
  let wire = encode_client_infer_original_inventory(occurrences, graphs, bounds).unwrap()
  let inverse = read_plural_client_infer_run_graphs(prepared, wire, bounds).unwrap()
  assert_eq(inverse.length(), 129)
  for index in 0..<occurrences.length() {
    assert_true(
      client_infer_occurrence_matches_plan(occurrences[index], inverse[index]),
    )
    assert_eq(inverse[index].graph.wire, graphs[index].graph.wire)
  }
  assert_true(
    encode_client_infer_original_inventory(occurrences, graphs, {
      ..bounds,
      max_evidence_bytes: 64,
    })
    is Err(_),
  )
  assert_true(
    encode_client_infer_original_inventory(
      occurrences,
      graphs[:128].to_owned(),
      bounds,
    )
    is Err(Binding(UnsupportedProgram)),
  )
}
