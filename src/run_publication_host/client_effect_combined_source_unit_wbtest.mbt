///|
fn combined_unit_finish_export(
  exported : @strategy.CapturedEffectLocalResultExport,
) -> @execution.CompletedRelationExportReceipt {
  let preparation = @strategy.captured_effect_local_result_export_preparation(
    exported,
  )
  for _ in 0..<100 {
    if @execution.advance_completed_result_relation_export(preparation, 64).unwrap().0 {
      break
    }
  }
  let stream = @execution.finish_completed_result_relation_export_preparation(
    preparation,
  ).unwrap()
  while @execution.next_completed_output_export_canonical_row(
          stream, 1000, 20, 1000,
        ).unwrap()
        is Some(_) {

  }
  @execution.finish_completed_relation_export(stream).unwrap().0
}

///|
// Actual checked same-Unit binary JOIN, original captures and completed local
// producer. Synthetic Source observations are not provider/Host acceptance.
fn combined_unit_whole_capture(
  prepared : PreparedClientEffectComputation,
  live : Ref[Bool],
  input_index : Int,
  stage? : Int = 0,
  availability_checks? : Ref[Int]? = None,
  original_catalog? : Bool = false,
) -> (
  @query.CapturedInputSource,
  @query.CapturedSourceRelationIdentity,
  @acquisition.SourceAcquisition,
  @publication.RunEvidenceValue,
  @publication.RunEvidenceValue,
) {
  let graph = @strategy.checked_effect_computation_graph(prepared.graph)
  let acquisition = prepare_client_effect_source_acquisition(
    prepared, stage, input_index,
  ).unwrap()
  let direct = select_client_effect_direct_acquisition_occurrences(
    prepared, 1000000,
  ).unwrap()
  let coordinate = direct.coordinates
    .iter()
    .find_first(value => value.0 == stage && value.1 == input_index)
    .unwrap()
  let owner = @strategy.graph_task_owner(graph, coordinate.2).unwrap()
  let input_slot = match @acquisition.source_acquisition_input(acquisition) {
    @pipeline.Input(slot) => slot
    _ => input_index
  }
  let model = prepared_client_effect_infer_occurrences(prepared).bind(values => {
    values.iter().find_first(value => value.stage == stage)
  })
  let sequence = match model {
    Some(original) =>
      @lower.prepare_sequence_with_infer_boundary(
        owner,
        original.step,
        run_materials_limits().sequence,
      ).unwrap()
    None =>
      @lower.prepare_sequence(owner, run_materials_limits().sequence).unwrap()
  }
  let rows = @execution.capture_input(
    owner,
    input_slot,
    [scalar_profile_cursor("{\"amount\":7,\"id\":1}")],
    max_rows=1,
    string_try_number_execution_limits().rows.input_values,
  ).unwrap()
  let original = @execution.prepare_supplied_relation_read(
    owner,
    input_slot,
    rows,
    () => {
      if availability_checks is Some(count) {
        count.val += 1
      }
      live.val
    },
  ).unwrap()
  let proof = Ref(original)
  let port = @query.prepare_trusted_source_input_capture_port(
    whole_source_capture_contracts(),
    sequence,
    acquisition,
    @checked.source_identity(@strategy.graph_program(graph)),
    2,
    8,
    fn(actual : Ref[@execution.SuppliedRelationRead]) {
      if physical_equal(actual, proof) && live.val {
        Some((actual.val, 41))
      } else {
        None
      }
    },
  ).unwrap()
  let captured = @query.capture_verified_source_input(port, proof).unwrap()
  let wire : @execution.RowWireLimits = {
    max_columns: 2,
    max_order_work: 10000,
    max_bytes: 20000,
    max_nodes: 10000,
    max_depth: 20,
  }
  let identity = @query.identify_captured_source_relation(
    captured,
    1,
    {
      max_nodes: 10000,
      max_text_bytes: 10000,
      max_depth: 20,
      max_work: 1000000,
    },
    wire,
    wire,
    { max_fields: 2, max_bytes: 10000, max_nodes: 1000, max_depth: 20, },
    20000,
  ).unwrap()
  let input = issue_captured_whole_source_input_logical(
    graph,
    captured,
    identity,
    acquisition,
    task=coordinate.2,
  ).unwrap()
  let facts = @planning.source_acquisition_evidence_facts(acquisition).unwrap()
  let authority = "sha256:" + "a".repeat(64)
  let (schema_evidence, capability_evidence) = if original_catalog {
    @environment.connector_source_evidence_member_cids(
      @planning.source_acquisition_evidence_members(acquisition).unwrap(),
    )
  } else {
    (facts.carrier_schema_contract_cid, "sha256:" + "b".repeat(64))
  }
  let observation = @publication.seal_completed_source_observation({
    input,
    source_ref: facts.source_ref,
    source_contract_cid: facts.source_contract_cid,
    schema_evidence_cid: schema_evidence,
    capability_evidence_cid: capability_evidence,
    authority_scope_cid: authority,
    source_data_policy_cid: facts.source_data_policy_cid,
    data_classification: facts.data_classification,
    source_view_contract_cid: facts.source_view_contract_cid,
    observed_at: "2026-11-11T00:00:01.000Z",
    snapshot_ref: "fixture-snapshot",
  }).unwrap()
  (captured, identity, acquisition, observation, input)
}

///|
fn combined_source_unit_completed_fixture(
  foreign_controls? : Bool = false,
  canonical_request? : Bool = false,
  early_unit? : Bool = false,
  consumer_model? : Bool = false,
  late_run_binding? : Bool = false,
  saved_artifact_scope? : Bool = false,
  saved_artifact_controls? : Bool = false,
  shared_ancestry? : Bool = false,
  model_columns? : Bool = false,
  construction_geometry? : Bool = false,
  catalog_guard? : Bool = false,
  artifact_geometry? : Bool = false,
  model_scope_imports? : Bool = false,
  model_scope_backing? : Bool = false,
) -> Unit raise {
  let document =
    #|{"version":"actql/0.1","id":"combined-source-unit","stages":[{"id":"joined","inputs":{"left_rows":{"connector":"crm/main","resource":"r"},"right_rows":{"connector":"crm/right","resource":"r"}},"from":"left_rows","steps":[{"join":{"with":"right_rows","kind":"inner","on":[{"left":"id","right":"id"}],"max_output_rows":4,"select":{"value":"left.id"}},"as":"selected"}],"results":{"out":{"from":"selected","fields":["value"]}},"effects":{"save":{"create":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"out"}}}}}],"results":{"joined":{"from":{"stage":"joined","result":"out"}}}}
  let base_environment = if canonical_request {
    canonical_source_request_test_environment()
  } else {
    admit_client_check_environment(
      bound_effect_source_environment,
      "sha256:e3da0e91ef758728bdf6e58957c09fe044d97d1fa2a21c9c19e3bdf5109bf45b",
      { text_time: false, veca: false, },
      { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    ).unwrap()
  }
  let environment = if consumer_model {
    client_composed_effect_test_environment(base_environment)
  } else {
    base_environment
  }
  let document = if consumer_model {
    guard @json.parse(document) is Object(program) &&
      program["stages"] is Array(stages) &&
      stages[0] is Object(producer) else {
      fail("original joined producer")
    }
    if model_columns {
      guard producer["steps"] is Array(steps) &&
        steps[0] is Object(join_step) &&
        join_step["join"] is Object(join) else {
        fail("original JOIN")
      }
      join["select"] = @json.parse(
        "{\"value\":\"left.id\",\"other\":\"right.amount\"}",
      )
      producer["results"] = @json.parse(
        "{\"out\":{\"from\":\"selected\",\"fields\":[\"value\",\"other\"]}}",
      )
    }
    let effects = producer["effects"]
    producer.remove("effects") |> ignore
    let next = @json.parse(
      "{\"id\":\"model\",\"inputs\":{\"rows\":{\"result\":{\"stage\":\"joined\",\"result\":\"out\"}}},\"steps\":[{\"derive\":{\"text\":{\"literal\":\"later\"},\"model_key\":{\"literal\":\"joined-key\"}}},{\"assert_rows\":{\"unique_by\":[\"model_key\"]},\"as\":\"keyed\"},{\"infer\":{\"contract\":\"model-task:risk-score.v1\",\"key\":\"model_key\",\"input\":{\"text\":{\"field\":\"text\"}}},\"as\":\"inferred\"},{\"join\":{\"with\":\"keyed\",\"kind\":\"inner\",\"on\":[{\"left\":\"model_key\",\"right\":\"model_key\"}],\"max_output_rows\":4,\"select\":{\"value\":\"right.value\",\"outcome\":\"left.outcome\"}},\"as\":\"selected\"}],\"results\":{\"out\":{\"from\":\"selected\",\"fields\":[\"value\",\"outcome\"]}}}",
    )
    guard next is Object(next_fields) else { fail("original later Model") }
    if model_columns {
      guard next_fields["steps"] is Array(steps) &&
        steps[0] is Object(first) &&
        first["derive"] is Object(derived) else {
        fail("original Model input")
      }
      derived["text"] = @json.parse(
        "{\"concat\":[{\"cast\":{\"value\":{\"field\":\"value\"},\"target\":{\"type\":\"string\"}}},{\"literal\":\"|\"},{\"cast\":{\"value\":{\"field\":\"other\"},\"target\":{\"type\":\"string\"}}}]}",
      )
    }
    next_fields["effects"] = effects
    stages.push(next)
    program["results"] = @json.parse(
      "{\"published\":{\"from\":{\"stage\":\"model\",\"result\":\"out\"}}}",
    )
    Json::object(program).stringify()
  } else {
    document
  }
  let prepared = prepare_client_effect_computation(
    if canonical_request {
      canonical_source_request_test_document(document)
    } else {
      document
    },
    Json,
    environment,
    None,
    [],
    client_standard_effect_computation_limits(),
  ).unwrap()
  let bounds = run_materials_limits()
  let infers = if consumer_model {
    prepared_client_effect_infer_occurrences(prepared)
    .unwrap()
    .map(occurrence => {
      match
        issue_installed_client_composed_infer_plan_graph(
          occurrence,
          client_infer_graph_test_execution(
            occurrence.owner,
            occurrence=Some(occurrence),
          ),
          bounds.sequence,
          bounds.max_evidence_bytes,
          bounds.max_evidence_nodes,
          bounds.max_evidence_depth,
        ) {
        Ok(value) => value
        Err(UnsupportedProgram) => fail("later Model graph UnsupportedProgram")
        Err(ForeignExecution) => fail("later Model graph ForeignExecution")
        Err(InvalidDependency) => fail("later Model graph InvalidDependency")
        Err(ItemLimit(_)) => fail("later Model graph ItemLimit")
        Err(Input(_)) => fail("later Model graph Input")
        Err(Mapping(_)) => fail("later Model graph Mapping")
        Err(Result(_)) => fail("later Model graph Result")
        Err(Encoding) => fail("later Model graph Encoding")
        Err(_) => fail("later Model graph other typed issue")
      }
    })
  } else {
    []
  }
  let compilation = issue_prepared_client_effect_compilation(
    prepared,
    run_materials_manifests(),
    bounds.sequence,
    bounds.max_sequence_steps,
    bounds.max_sequence_work,
    bounds.max_evidence_bytes,
    bounds.max_evidence_nodes,
    bounds.max_evidence_depth,
    infer=if infers.length() == 1 { Some(infers[0]) } else { None },
    infers=if infers.length() == 1 { [] } else { infers },
  )
  let compilation = match compilation {
    Ok(value) => value
    Err(UnsupportedProgram) =>
      fail("later Model whole compilation UnsupportedProgram")
    Err(ForeignInferOwner) =>
      fail("later Model whole compilation ForeignInferOwner")
    Err(Graph(_)) => fail("later Model whole compilation Graph")
    Err(EffectPlan(_)) => fail("later Model whole compilation EffectPlan")
    Err(_) => fail("later Model whole compilation other typed issue")
  }
  let allowed = issue_client_effect_allowed_run(
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = issue_client_effect_run_definition(
    allowed, "combined-unit", "original-combined-run", "2026-11-11T00:00:00.000Z",
    "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let direct = select_client_effect_direct_acquisition_occurrences(
    prepared, 1000000,
  ).unwrap()
  assert_eq(direct.coordinates, [(0, 0, 0), (0, 1, 0)])
  let left_live = Ref(true)
  let right_live = Ref(true)
  let availability_checks = Ref(0)
  let left = combined_unit_whole_capture(
    prepared,
    left_live,
    0,
    original_catalog=catalog_guard,
    availability_checks=if construction_geometry {
      Some(availability_checks)
    } else {
      None
    },
  )
  let right = combined_unit_whole_capture(
    prepared,
    right_live,
    1,
    original_catalog=catalog_guard,
    availability_checks=if construction_geometry {
      Some(availability_checks)
    } else {
      None
    },
  )
  let captures = [left.0, right.0]
  let identities = [left.1, right.1]
  let originals = [WholeSourceOriginal(left.2), WholeSourceOriginal(right.2)]
  let sources = [left.3, right.3]
  let logical = [left.4, right.4]
  let authority = "sha256:" + "a".repeat(64)
  let policy = prepared_client_effect_publication_data_policy_cid(prepared).unwrap()
  let admission = client_effect_allowed_run_admission(allowed)
  let publication = if consumer_model {
    assert_true(
      prepare_client_effect_direct_sources_publication(
        prepared, compilation, admission, definition, direct, captures, identities,
        originals, sources, logical, authority, policy, "2026-11-11T00:00:01.000Z",
        "2026-11-11T00:00:02.000Z", 100000, 10000, 100,
      )
      is Err(@publication.RunEvidenceReferenceMismatch("model_capture")),
    )
    None
  } else {
    Some(
      prepare_client_effect_direct_sources_publication(
        prepared, compilation, admission, definition, direct, captures, identities,
        originals, sources, logical, authority, policy, "2026-11-11T00:00:01.000Z",
        "2026-11-11T00:00:02.000Z", 100000, 10000, 100,
      ).unwrap(),
    )
  }
  let retention = @publication.issue_result_retention_for_data_policy(
    product_expiry_original_retention(product_test_originals()),
    policy,
    100000,
    10000,
    100,
  ).unwrap()
  assert_true(
    issue_client_whole_native_effect_source_unit(
      prepared,
      direct,
      0,
      left.0,
      left.1,
      left.2,
      left.4,
      left.3,
      authority,
      retention,
      100000,
      10000,
      100,
    )
    is Err(Invocation(MissingUnit)),
  )
  let mut construction = None
  let combined = if consumer_model || late_run_binding {
    let originals = prepare_client_effect_source_unit_inputs(
      prepared, compilation, admission, definition, direct, captures, identities,
      originals, sources, logical, authority, policy, 100000, 10000, 100,
    ).unwrap()
    if construction_geometry {
      let before = availability_checks.val
      construction = Some(
        client_effect_source_unit_construction_geometry(
          originals, 0, retention, 100000, 10000, 100,
        ).unwrap(),
      )
      assert_eq(availability_checks.val, before)
    }
    prepare_client_effect_source_unit(
      originals, 0, retention, 100000, 10000, 100,
    ).unwrap()
  } else {
    prepare_client_effect_combined_source_unit(
      publication.unwrap(),
      0,
      retention,
      100000,
      10000,
      100,
    ).unwrap()
  }
  if catalog_guard {
    let calls = Ref(0)
    let declined = client_effect_combined_source_unit_catalog_bodies(
      combined,
      100000,
      10000,
      100,
      before_body=Some(fn(_, _, _) {
        calls.val += 1
        false
      }),
    )
    assert_true(declined is Err(Dependency(BudgetExceeded)))
    assert_eq(calls.val, 1)
    let geometries : Array[(Int, Int, Int)] = []
    let body_result = client_effect_combined_source_unit_catalog_bodies(
      combined,
      100000,
      10000,
      100,
      before_body=Some(fn(bytes, nodes, depth) {
        geometries.push((bytes, nodes, depth))
        true
      }),
    )
    let bodies = match body_result {
      Ok(value) => value
      Err(issue) =>
        fail("original Catalog body issue: " + @debug.to_string(issue))
    }
    assert_true(bodies.length() > 0)
    assert_eq(bodies.length(), geometries.length())
    for index in 0..<bodies.length() {
      assert_eq(@utf8.encode(bodies[index].2).length(), geometries[index].0)
      assert_true(geometries[index].1 > 0 && geometries[index].2 > 0)
    }
  }
  if construction is Some(shapes) {
    let expected : Map[String, Int] = Map([])
    for (kind, geometry) in shapes {
      let extra = if kind == "request_values" || kind == "local_computation" {
        0
      } else {
        let field = @publication.publication_contract_identity_field_for_name(
          kind,
        ).unwrap()
        @utf8.encode(
          ",\"" +
          field +
          "\":\"" +
          @publication.publication_contract_identity(definition) +
          "\"",
        ).length()
      }
      expected[kind] = expected.get(kind).unwrap_or(0) + geometry.bytes + extra
    }
    let actual : Map[String, Int] = Map([])
    let append = (kind : String, wire : String) => {
      actual[kind] = actual.get(kind).unwrap_or(0) + @utf8.encode(wire).length()
    }
    append(
      "acquisition_scope",
      @publication.publication_contract_json(combined.scope),
    )
    append("local_computation", combined.invocation.wire)
    for part in combined.contributions {
      append("request_values", @encode.document_text(part.request))
      for
        (kind, contract) in [
          ("acquisition_relation", part.relation),
          ("ordering_evidence", part.ordering),
          ("acquisition_scope", part.scope),
        ] {
        append(kind, @publication.publication_contract_json(contract))
      }
      if !physical_equal(part.retention, retention) {
        append(
          "result_retention_policy",
          @publication.publication_contract_json(part.retention),
        )
      }
    }
    assert_eq(expected.length(), actual.length())
    for (kind, size) in expected {
      assert_eq(actual.get(kind), Some(size))
    }
  }
  if canonical_request {
    for part in combined.contributions {
      assert_canonical_source_request_test_body(part.request, part.request_cid)
    }
  }
  assert_eq(combined.contributions.length(), 2)
  assert_eq(combined.contributions.map(value => value.slot), [0, 1])
  let wrong_unit = if consumer_model {
    prepare_client_effect_source_unit(
      combined.original,
      1,
      retention,
      100000,
      10000,
      100,
    )
  } else {
    prepare_client_effect_combined_source_unit(
      publication.unwrap(),
      1,
      retention,
      100000,
      10000,
      100,
    )
  }
  assert_true(wrong_unit is Err(_))
  assert_true(
    prepare_client_effect_source_unit_inputs(
      prepared,
      compilation,
      admission,
      definition,
      direct,
      [right.0, left.0],
      identities,
      originals,
      sources,
      logical,
      authority,
      policy,
      100000,
      10000,
      100,
    )
    is Err(_),
  )
  assert_true(
    prepare_client_effect_source_unit_inputs(
      prepared,
      compilation,
      admission,
      definition,
      direct,
      [left.0],
      [left.1],
      [originals[0]],
      [left.3],
      [left.4],
      authority,
      policy,
      100000,
      10000,
      100,
    )
    is Err(_),
  )
  let graph = @strategy.checked_effect_computation_graph(prepared.graph)
  let root = @strategy.graph_task_owner(graph, 0).unwrap()
  let assets = client_local_product_assets()
  let contracts = @local_query_time.prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let sequences = @local_query_time.prepare_client_effect_local_sequences(
    prepared,
    contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let sequence = sequences[0]
  let execution = string_try_number_execution_limits()
  let measure : @execution.FixedInputGuardMeasureLimits = {
    max_work: 100000,
    max_bytes: 20000,
    max_nodes: 10000,
    max_depth: 20,
  }
  let reads = captures.mapi((index, captured) => {
    let bound = @query.bind_captured_source_operation(captured, root, 0, index).unwrap()
    @execution.prepare_producer_read(root, bound, 10000, 20000).unwrap()
  })
  let provider = @local.local_bounded_relation_provider(
    execution, measure, sequence,
  ).unwrap()
  let child = @local.start_managed_provider_with_inputs_and_execution(
    provider,
    sequence,
    reads.map(@local.managed_provider_relation_input),
    100,
    20000,
    execution,
  ).unwrap()
  let mut completed = None
  for _ in 0..<10000 {
    match @local.advance_managed_provider(child, 31).unwrap() {
      @local.Complete(output, ..) => {
        completed = Some(output)
        break
      }
      @local.Continue(..) | @local.Settling(_, ..) => ()
      _ => fail("same original JOIN must complete")
    }
  }
  let output = completed.unwrap()
  assert_true(
    @execution.completed_cell(output, 0, if model_columns { 1 } else { 0 })
    is Some(Number(1.0)),
  )
  let bindings = [(0, 0, reads[0]), (0, 1, reads[1])]
  let proof = @execution.retain_completed_segment_inputs(
    output, sequence, bindings, 100000,
  ).unwrap()
  let bound = bind_prepared_client_effect_run(prepared, admission, definition).unwrap()
  let selected = @strategy.prepare_source_inputs_dag(graph, [left.2, right.2]).unwrap()
  let ledger = @resources.create_ledger({
    planning_work: 100000,
    attempts: 10,
    holdings: 10,
    transfer_bytes: 10000000L,
    retained_bytes: 10000000L,
    execution_bytes: 10000000L,
  }).unwrap()
  let run = @strategy.open_source_inputs_effect_run_dag(
    prepared_client_effect_run_graph(bound),
    selected,
    captures,
    ledger,
    source_results=[(0, sequence, bindings, proof)],
  ).unwrap()
  assert_true(
    @strategy.captured_task_completed(@strategy.captured_effect_run_dag(run), 0),
  )
  if early_unit {
    // Same completed JOIN, before a final input owner exists. No new Result,
    // Run or Source is issued to supply this upstream Artifact.
    assert_true(
      @strategy.pin_captured_effect_acquired_unit_results(run, 0, 0) is Err(_),
    )
    assert_true(
      @strategy.pin_captured_effect_acquired_unit_results(
        run,
        0,
        10,
        max_dependency_work=0,
      )
      is Err(_),
    )
    let unit = @strategy.pin_captured_effect_acquired_unit_results(run, 0, 10).unwrap()
    assert_eq(@strategy.captured_effect_local_unit_result_count(unit), 1)
    let wire : @execution.RowWireLimits = {
      max_columns: 2,
      max_order_work: 10000,
      max_bytes: 20000,
      max_nodes: 10000,
      max_depth: 20,
    }
    let exported = @strategy.start_captured_effect_local_unit_result_export(
      unit,
      0,
      {
        max_fields: 2,
        max_mapping_work: 1000,
        max_order_work: 10000,
        max_workspace_entries: 20,
      },
      10,
      execution.rows.input_values,
      wire,
      wire,
      { max_fields: 2, max_bytes: 10000, max_nodes: 1000, max_depth: 20, },
      1000,
    ).unwrap()
    let receipt = combined_unit_finish_export(exported)
    let metadata_geometry = if artifact_geometry {
      Some(
        client_effect_source_unit_artifact_construction_geometry(
          combined, "out", receipt, admission, 100000, 10000, 100,
        ).unwrap(),
      )
    } else {
      None
    }
    let local_definition = issue_client_effect_local_result_definition(
      prepared, 0, "out", 100000, 10000, 100,
    ).unwrap()
    let artifact = if consumer_model || late_run_binding {
      issue_preconsumer_client_effect_unit_result_artifact(
        prepared, unit, exported, combined, local_definition, receipt, admission,
        definition, 100000, 10000, 100,
      ).unwrap()
    } else {
      issue_combined_source_client_effect_unit_result_artifact(
        prepared,
        unit,
        exported,
        combined,
        local_definition,
        receipt,
        admission,
        definition,
        publication.unwrap().source.invocation,
        publication.unwrap().source.observation,
        100000,
        10000,
        100,
      ).unwrap()
    }
    let manifest_geometry = if artifact_geometry {
      Some(
        client_effect_local_manifest_construction_geometry(
          combined.invocation,
          [artifact],
          100000,
          10000,
          100,
        ).unwrap(),
      )
    } else {
      None
    }
    let manifest = issue_client_effect_local_manifest(
      prepared,
      combined.invocation,
      [artifact],
      100000,
      10000,
      100,
    )
    assert_true(manifest is Ok(_))
    if metadata_geometry is Some(geometries) {
      let actual = [
        client_effect_local_result_definition_json(local_definition),
        client_effect_local_result_derivation_json(artifact),
        client_effect_local_result_ordering_json(artifact),
        client_effect_local_result_artifact_json(artifact),
      ]
      for index in 0..<geometries.length() {
        let (name, geometry) = geometries[index]
        let extra = if name == "local_result_definition" {
          0
        } else {
          let field = @publication.publication_contract_identity_field_for_name(
            name,
          ).unwrap()
          // These existing registered identities are ASCII SHA256 CIDs.
          @utf8.encode(
            "\"" +
            field +
            "\":\"" +
            @publication.publication_contract_identity(definition) +
            "\",",
          ).length()
        }
        assert_eq(@utf8.encode(actual[index]).length(), geometry.bytes + extra)
      }
      assert_eq(
        @utf8.encode(client_effect_local_manifest_json(manifest.unwrap())).length(),
        manifest_geometry.unwrap().bytes,
      )
    }
    assert_eq(
      client_effect_local_artifact_invocation_cid(artifact),
      combined.invocation.cid,
    )
    let mut retained_model_scope = None
    if consumer_model {
      assert_true(
        client_effect_local_artifact_run_invocation_cid(artifact) is None,
      )
      let occurrence = infers[0].occurrence
      let prefix = @execution.select_generated_sequence_prefix(
        sequences[occurrence.task],
        occurrence.step - 1,
      ).unwrap()
      guard artifact.source is ResultSource(borrow, _) &&
        @strategy.captured_any_result_borrow_cell_output(borrow)
        is Some(producer) else {
        fail("original producer output")
      }
      let bound = @execution.bind_completed_input(
        occurrence.preparation,
        0,
        root,
        producer,
      ).unwrap()
      let read = @execution.prepare_producer_read(
        occurrence.preparation,
        bound,
        10000,
        20000,
      ).unwrap()
      let receiving_inputs = [@local.managed_provider_relation_input(read)]
      let prefix_child = @local_query_time.start_client_composed_infer_input(
        occurrence,
        prefix,
        receiving_inputs,
        execution,
        measure,
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
      receiving_inputs.clear()
      let mut input = None
      let mut model_rows = None
      for _ in 0..<10000 {
        match
          @local_query_time.advance_client_infer_input(prefix_child, 31).unwrap() {
          @local_query_time.Complete(rows, ..) => {
            model_rows = Some(rows)
            input = @local_query_time.client_infer_completed_input(prefix_child)
            break
          }
          @local_query_time.Continue(..) => ()
          _ => fail("original later Model prefix")
        }
      }
      let input = input.unwrap()
      let bindings = [(0, 0, read)]
      let proof = @execution.retain_completed_segment_inputs(
        input, prefix, bindings, 100000,
      ).unwrap()
      let imported = prepare_client_infer_result_artifact_input(
        occurrence,
        infers[0],
        0,
        input,
        prefix,
        bindings,
        proof,
        artifact,
        manifest.unwrap(),
      ).unwrap()
      let actual_import = @local_query_time.client_infer_completed_result_artifact_input(
        prefix_child,
        occurrence,
        infers[0],
        0,
        artifact,
        manifest.unwrap(),
      ).unwrap()
      assert_eq(
        client_infer_result_artifact_input_binding(
          actual_import, occurrence, input,
        ).unwrap(),
        client_infer_result_artifact_input_binding(imported, occurrence, input).unwrap(),
      )
      assert_true(
        @local_query_time.client_infer_completed_result_artifact_input(
          prefix_child,
          occurrence,
          infers[0],
          1,
          artifact,
          manifest.unwrap(),
        )
        is Err(ForeignInput),
      )
      assert_eq(
        client_infer_result_artifact_input_binding(imported, occurrence, input).unwrap(),
        ("rows", client_effect_local_result_artifact_cid(artifact)),
      )
      let model_wire : @execution.RowWireLimits = {
        max_columns: 10,
        max_order_work: 10000,
        max_bytes: 20000,
        max_nodes: 10000,
        max_depth: 20,
      }
      let identity = @execution.start_completed_relation_identity_scan(
        input,
        10,
        execution.rows.input_values,
        model_wire,
        model_wire,
        { max_fields: 10, max_bytes: 10000, max_nodes: 1000, max_depth: 20, },
        1000000,
        100000,
        incremental_metadata=true,
      ).unwrap()
      for _ in 0..<10000 {
        if @execution.advance_completed_relation_identity_scan(identity, 31).unwrap().0 {
          break
        }
      }
      let model_receipt = @execution.finish_completed_relation_identity_scan(
        identity,
      ).unwrap()
      let ancestry = if shared_ancestry {
        let value = admit_client_infer_composed_sources_owned(
          occurrence,
          captures,
          identities,
          [Whole(left.2), Whole(right.2)],
          logical,
          sources,
          authority,
          "2026-11-11T00:00:01.000Z",
          "2026-11-11T00:00:02.000Z",
        ).unwrap()
        assert_eq(value.inputs.length(), 2)
        assert_true(value.inputs.all(original => original.name == "rows"))
        assert_true(
          admit_client_infer_composed_sources_owned(
            occurrence,
            [left.0, left.0],
            [left.1, left.1],
            [Whole(left.2), Whole(left.2)],
            [left.4, left.4],
            [left.3, left.3],
            authority,
            "2026-11-11T00:00:01.000Z",
            "2026-11-11T00:00:02.000Z",
          )
          is Err(ForeignInput),
        )
        // Even genuine ancestry cannot stand in for the actual joined Result.
        assert_true(
          issue_client_infer_occurrence_call_scope(
            occurrence,
            infers[0],
            input,
            model_receipt,
            100000,
            10000,
            100,
            sources=Some(value),
          )
          is Err(ForeignInput),
        )
        Some(value)
      } else {
        None
      }
      let scope = issue_client_infer_occurrence_call_scope(
        occurrence,
        infers[0],
        input,
        model_receipt,
        100000,
        10000,
        100,
        result_inputs=[imported],
        sources=ancestry,
      ).unwrap()
      if model_scope_imports || model_scope_backing {
        let observations = issue_scope_model_result_import_observations(
          prepared, scope, 100000, 10000, 100,
        ).unwrap()
        assert_eq(observations.length(), 1)
        assert_true(physical_equal(observations[0].input, imported))
        assert_true(
          model_effect_imports_match(
            prepared,
            scope,
            occurrence,
            None,
            observations,
          ),
        )
        assert_false(
          model_effect_imports_match(prepared, scope, occurrence, None, []),
        )
        let sources = ancestry.unwrap()
        assert_eq(sources.inputs.length(), 2)
        for original in sources.inputs {
          assert_true(
            model_effect_scope_imported_source(observations, original),
          )
        }
        guard @json.parse(observations[0].wire) is Object(observed) else {
          fail("original import body")
        }
        assert_eq(observed["input_name"], Json::string("rows"))
        assert_eq(
          observed["result_artifact_cid"],
          Json::string(client_effect_local_result_artifact_cid(artifact)),
        )
        assert_eq(
          observed["producer_local_manifest_cid"],
          Json::string(client_effect_local_manifest_cid(manifest.unwrap())),
        )

        // Exercise the actual semantic Model closure with this genuine Scope.
        // The admitted body below is explicit test DATA, not a claim that a
        // Model ran or that physical construction/publication was funded.
        let (logical, schema) = @publication.model_input_artifact_relation_identities(
          scope.artifact,
        ).unwrap()
        let preimage = "{\"input_logical_relation_cid\":\"" +
          logical +
          "\",\"input_relation_schema_cid\":\"" +
          schema +
          "\",\"outcome_logical_relation_cid\":\"" +
          logical +
          "\",\"outcome_relation_schema_cid\":\"" +
          schema +
          "\",\"source_ordinal\":" +
          occurrence.step.to_string() +
          ",\"unit_definition_cid\":\"" +
          scope.unit_definition_cid +
          "\",\"version\":\"actql-local-model-observation/0.1\"}"
        let model_cid = "sha256:" + @sha.hex(@utf8.encode(preimage))
        let model = @publication.admit_local_effect_dependency_body(
          "local_model_observation",
          preimage.replace(
            old=",\"source_ordinal\":",
            new=",\"self_cid\":\"" + model_cid + "\",\"source_ordinal\":",
          ),
          100000,
          10000,
          100,
        ).unwrap()
        let acquired = issue_single_model_client_effect_acquired_evidence(
          client_effect_allowed_component_run(allowed, None),
          scope,
          model,
          sources,
          retention,
          100000,
          10000,
          100,
        ).unwrap()
        assert_true(physical_equal(acquired.call_scope, scope))
        assert_eq(acquired.scope_imports.length(), 1)
        assert_true(physical_equal(acquired.scope_imports[0].input, imported))
        assert_eq(acquired.scope_relations.length(), 1)
        assert_eq(
          effect_model_acquired_relation_cids(acquired).unwrap().length(),
          1,
        )
        assert_eq(
          @publication.publication_contract_identity(acquired.scope),
          @publication.publication_contract_identity(artifact.scope.unwrap()),
        )
        guard @json.parse(
            client_effect_local_invocation_json(acquired.invocation),
          )
          is Object(invocation) &&
          invocation["observation_cids"] is Array(cids) else {
          fail("original Model invocation")
        }
        assert_eq(cids.length(), 2)
        assert_true(cids.contains(Json::string(model_cid)))
        assert_true(cids.contains(Json::string(observations[0].cid)))
        let bodies = client_effect_model_acquired_scope_import_bodies(acquired)
        assert_eq(bodies.length(), 2)
        assert_eq(bodies[0].0, "result_import_observation")
        assert_eq(bodies[0].1, observations[0].cid)
        assert_eq(bodies[1].0, "acquisition_relation")
        if model_scope_backing {
          let kinds : Array[String] = []
          let valid_shapes = Ref(true)
          let backed = issue_single_model_client_effect_acquired_evidence(
            client_effect_allowed_component_run(allowed, None),
            scope,
            model,
            sources,
            retention,
            100000,
            10000,
            100,
            before_body=Some(fn(kind, shape) {
              valid_shapes.val = valid_shapes.val &&
                shape.bytes > 0 &&
                shape.nodes > 0
              kinds.push(kind)
              true
            }),
          ).unwrap()
          assert_eq(backed.invocation.cid, acquired.invocation.cid)
          assert_true(valid_shapes.val)
          assert_eq(
            @publication.publication_contract_identity(backed.scope),
            @publication.publication_contract_identity(acquired.scope),
          )
          for
            kind in [
              "result_import_observation", "local_computation", "request_values",
              "acquisition_scope", "ordering_evidence", "acquisition_relation",
            ] {
            let mut found : Int? = None
            for index, candidate in kinds {
              if candidate == kind && found is None {
                found = Some(index)
              }
            }
            let position = found.unwrap()
            let entered = Ref(0)
            assert_true(
              issue_single_model_client_effect_acquired_evidence(
                client_effect_allowed_component_run(allowed, None),
                scope,
                model,
                sources,
                retention,
                100000,
                10000,
                100,
                before_body=Some(fn(_, _) {
                  let slot = entered.val
                  entered.val += 1
                  slot != position
                }),
              )
              is Err(_),
            )
            assert_eq(entered.val, position + 1)
            assert_true(client_infer_call_scope_generation_available(scope))
          }
        }
      }
      guard @json.parse(@publication.run_evidence_value_json(scope.effective))
        is Object(effective) &&
        effective["input_artifacts"] is Object(upstream) else {
        fail("original upstream effective inputs")
      }
      assert_eq(upstream.length(), 1)
      assert_eq(
        upstream["rows"],
        Json::string(client_effect_local_result_artifact_cid(artifact)),
      )
      guard @json.parse(client_infer_call_scope_snapshot(scope).unwrap())
        is Object(snapshot) &&
        snapshot["result_inputs"] is Array(stored) else {
        fail("original upstream snapshot")
      }
      assert_eq(stored.length(), 1)
      if model_columns {
        let calls = Ref(0)
        let original_inputs = Ref(false)
        let provider = @model.install_model_provider("models/fixture", request => {
          calls.val += 1
          original_inputs.val = request.inputs.length() == 1 &&
            request.inputs[0].0 == "text" &&
            @values.canonical_scalar_text(request.inputs[0].1, 100) ==
            Some("1|7")
          Err(@model.Refusal)
        }).unwrap()
        let active = @model.start_model_execution(
          model_rows.unwrap(),
          provider,
          client_infer_plan_graph_request_cid(infers[0]),
          {
            max_items: 10,
            max_work: 100000,
            max_request_bytes: 10000L,
            max_response_bytes: 10000L,
            value_limits: {
              max_nodes: 1000,
              max_depth: 20,
              max_text_bytes: 10000,
            },
            ledger: {
              planning_work: 100000,
              attempts: 10,
              holdings: 10,
              transfer_bytes: 1000000L,
              retained_bytes: 1000000L,
              execution_bytes: 1000000L,
            },
          },
          call_scope=Some(scope),
        ).unwrap()
        for _ in 0..<100000 {
          match @model.advance_model_execution(active, 31).unwrap() {
            @model.Continue(_, _)
            | @model.Waiting(_, _)
            | @model.AwaitIo(_, _) => ()
            _ => break
          }
        }
        assert_eq(calls.val, 1)
        assert_true(original_inputs.val)
        @model.request_model_cancel(active) |> ignore
        assert_true(@model.cleanup_model_execution(active) is Ok(true))
      }
      if shared_ancestry {
        guard snapshot["sources"] is Array(ancestors) else {
          fail("original Source ancestry")
        }
        assert_eq(ancestors.length(), 2)
      }
      if saved_artifact_scope {
        // The existing test ports supply authenticated historical custody;
        // this is not a Store, cold process, physical holding or Model grant.
        let original_snapshot = client_infer_call_scope_snapshot(scope).unwrap()
        let saved_available = Ref(true)
        let restored = match
          read_client_infer_saved_call_scope(
            client_effect_allowed_component_run(allowed, None),
            definition,
            occurrence,
            infers[0],
            original_snapshot,
            authority,
            () => saved_available.val,
          ) {
          Ok(value) => value
          Err(issue) => {
            let kind = match issue {
              ForeignOwner => "foreign_owner"
              ForeignInput => "foreign_input"
              UnsupportedBindings => "unsupported_bindings"
              Encoding => "encoding"
              Evidence(_) => "evidence"
            }
            fail("OriginalArtifactSavedScope:" + kind)
          }
        }
        let rebound = restore_client_infer_call_scope(
          restored, input, model_receipt,
        ).unwrap()
        assert_eq(
          @publication.run_evidence_value_identity(rebound.artifact),
          @publication.run_evidence_value_identity(scope.artifact),
        )
        assert_eq(
          @publication.run_evidence_value_identity(rebound.effective),
          @publication.run_evidence_value_identity(scope.effective),
        )
        assert_eq(
          client_infer_call_scope_snapshot(rebound).unwrap(),
          original_snapshot,
        )
        if saved_artifact_controls {
          let canonical = (value : Json) => {
            @canonical.stringify_value(
              @canonical.from_json(value, 100000, 100, 1000000),
              1000000,
              100000,
              100,
            )
          }
          for mode in 0..<7 {
            guard @json.parse(original_snapshot) is Object(changed) &&
              changed["result_inputs"] is Array(entries) &&
              entries[0] is Object(entry) else {
              fail("original Saved Artifact entry")
            }
            match mode {
              0 => changed["extra"] = Json::null()
              1 => entries.push(entries[0])
              2 => entry["name"] = Json::string("another-original-port")
              3 =>
                entry["result_artifact_cid"] = Json::string(
                  "sha256:" + "0".repeat(64),
                )
              4 =>
                entry["producer_local_manifest_cid"] = Json::string("invalid")
              5 => changed["result_inputs"] = Json::null()
              _ => changed["result_inputs"] = Json::array([])
            }
            assert_true(
              read_client_infer_saved_call_scope(
                client_effect_allowed_component_run(allowed, None),
                definition,
                occurrence,
                infers[0],
                canonical(Json::object(changed)),
                authority,
                () => true,
              )
              is Err(ForeignInput),
            )
          }
          saved_available.val = false
          assert_false(client_infer_call_scope_generation_available(rebound))
          assert_true(
            client_infer_call_scope_snapshot(rebound) is Err(ForeignInput),
          )
          assert_true(
            restore_client_infer_call_scope(restored, input, model_receipt)
            is Err(ForeignInput),
          )
          // Retiring the receiving historical borrow does not retire or
          // replace the independently held original producer/input Scope.
          assert_true(client_infer_call_scope_generation_available(scope))
        }
      }
      assert_true(client_infer_call_scope_generation_available(scope))
      retained_model_scope = Some(scope)
      let foreign_read = @execution.prepare_producer_read(
        occurrence.preparation,
        bound,
        10000,
        20000,
      ).unwrap()
      assert_true(
        prepare_client_infer_result_artifact_input(
          occurrence,
          infers[0],
          0,
          input,
          prefix,
          [(0, 0, foreign_read)],
          proof,
          artifact,
          manifest.unwrap(),
        )
        is Err(ForeignInput),
      )
      @local_query_time.cancel_client_infer_input(prefix_child) |> ignore
      assert_true(
        @local_query_time.cleanup_client_infer_input(prefix_child) is Ok(true),
      )
      assert_true(
        @local_query_time.client_infer_completed_result_artifact_input(
          prefix_child,
          occurrence,
          infers[0],
          0,
          artifact,
          manifest.unwrap(),
        )
        is Err(ForeignInput),
      )
    } else {
      let final_inputs = @strategy.pin_captured_effect_sources(run, 10).unwrap()
      if late_run_binding {
        let cid = client_effect_local_result_artifact_cid(artifact)
        let wire = @publication.publication_contract_json(artifact.artifact)
        assert_true(
          client_effect_local_artifact_run_invocation_cid(artifact) is None,
        )
        let original = publication.unwrap().source
        // The final consumer can use the already selected Source-only Unit
        // context with the real final Run evidence. This independent issuer
        // checks semantic equality; the normal early Artifact is bound below.
        let final_artifact = issue_combined_source_client_effect_unit_result_artifact(
          prepared,
          unit,
          exported,
          combined,
          local_definition,
          receipt,
          admission,
          definition,
          original.invocation,
          original.observation,
          100000,
          10000,
          100,
        ).unwrap()
        assert_eq(client_effect_local_result_artifact_cid(final_artifact), cid)
        let foreign = issue_client_effect_run_definition(
          allowed, "combined-unit", "another-original-run", "2026-11-11T00:00:00.000Z",
          "2027-01-01T00:00:00.000Z",
        ).unwrap()
        assert_true(
          bind_client_effect_unit_artifact_run_context(
            prepared,
            final_inputs,
            artifact,
            admission,
            foreign,
            original.invocation,
            original.observation,
          )
          is Err(ForeignRun),
        )
        bind_client_effect_unit_artifact_run_context(
          prepared,
          final_inputs,
          artifact,
          admission,
          definition,
          original.invocation,
          original.observation,
        ).unwrap()
        bind_client_effect_unit_artifact_run_context(
          prepared,
          final_inputs,
          artifact,
          admission,
          definition,
          original.invocation,
          original.observation,
        ).unwrap()
        assert_eq(cid, client_effect_local_result_artifact_cid(artifact))
        assert_eq(
          wire,
          @publication.publication_contract_json(artifact.artifact),
        )
        let copied = @publication.issue_run_invocation(
          client_effect_compilation_template(compilation),
          original.observation,
          100000,
          10000,
          100,
        ).unwrap()
        assert_true(
          bind_client_effect_unit_artifact_run_context(
            prepared,
            final_inputs,
            artifact,
            admission,
            definition,
            copied,
            original.observation,
          )
          is Err(ForeignInvocation),
        )
      }
      assert_true(
        client_effect_local_artifact_matches_inputs(artifact, final_inputs),
      )
      assert_true(@strategy.release_captured_effect_inputs(final_inputs))
    }
    assert_true(
      @strategy.captured_effect_local_unit_result_export_retained(
        unit, exported,
      ),
    )
    if retained_model_scope is Some(scope) {
      assert_true(client_infer_call_scope_generation_available(scope))
    }
    assert_true(@strategy.release_captured_effect_local_unit_inputs(unit))
    if retained_model_scope is Some(scope) {
      assert_false(client_infer_call_scope_generation_available(scope))
    }
    assert_eq(@strategy.captured_effect_local_unit_result_count(unit), 0)
    assert_false(
      @strategy.captured_effect_local_unit_result_export_retained(
        unit, exported,
      ),
    )
    assert_false(
      client_effect_local_artifact_matches_computation(artifact, prepared),
    )
    assert_false(@strategy.release_captured_effect_local_unit_inputs(unit))
    @local.cancel_managed_provider(child) |> ignore
    assert_true(@local.cleanup_managed_provider(child) is Ok(true))
    return
  }

  let inputs = @strategy.pin_captured_effect_sources(run, 10).unwrap()
  let wire : @execution.RowWireLimits = {
    max_columns: 2,
    max_order_work: 10000,
    max_bytes: 20000,
    max_nodes: 10000,
    max_depth: 20,
  }
  let exported = @strategy.start_captured_effect_local_result_export(
    inputs,
    0,
    {
      max_fields: 2,
      max_mapping_work: 1000,
      max_order_work: 10000,
      max_workspace_entries: 20,
    },
    10,
    execution.rows.input_values,
    wire,
    wire,
    { max_fields: 2, max_bytes: 10000, max_nodes: 1000, max_depth: 20, },
    1000,
  ).unwrap()
  let receipt = combined_unit_finish_export(exported)
  let local_definition = issue_client_effect_local_result_definition(
    prepared, 0, "out", 100000, 10000, 100,
  ).unwrap()
  if foreign_controls {
    let foreign_definition = issue_client_effect_run_definition(
      allowed, "combined-unit", "foreign-combined-run", "2026-11-11T00:00:00.000Z",
      "2027-01-01T00:00:00.000Z",
    ).unwrap()
    assert_true(
      issue_combined_source_client_effect_local_result_artifact(
        prepared,
        inputs,
        exported,
        combined,
        local_definition,
        receipt,
        admission,
        foreign_definition,
        publication.unwrap().source.invocation,
        publication.unwrap().source.observation,
        100000,
        10000,
        100,
      )
      is Err(ForeignRun),
    )
    let other_export = @strategy.start_captured_effect_local_result_export(
      inputs,
      0,
      {
        max_fields: 2,
        max_mapping_work: 1000,
        max_order_work: 10000,
        max_workspace_entries: 20,
      },
      10,
      execution.rows.input_values,
      wire,
      wire,
      { max_fields: 2, max_bytes: 10000, max_nodes: 1000, max_depth: 20, },
      1000,
    ).unwrap()
    let other_preparation = @strategy.captured_effect_local_result_export_preparation(
      other_export,
    )
    for _ in 0..<100 {
      if @execution.advance_completed_result_relation_export(
          other_preparation, 64,
        ).unwrap().0 {
        break
      }
    }
    let other_stream = @execution.finish_completed_result_relation_export_preparation(
      other_preparation,
    ).unwrap()
    while @execution.next_completed_output_export_canonical_row(
            other_stream, 1000, 20, 1000,
          ).unwrap()
          is Some(_) {

    }
    let (other_receipt, _) = @execution.finish_completed_relation_export(
      other_stream,
    ).unwrap()
    assert_true(
      issue_combined_source_client_effect_local_result_artifact(
        prepared,
        inputs,
        exported,
        combined,
        local_definition,
        other_receipt,
        admission,
        definition,
        publication.unwrap().source.invocation,
        publication.unwrap().source.observation,
        100000,
        10000,
        100,
      )
      is Err(ForeignExport),
    )
  } else {
    let artifact = issue_combined_source_client_effect_local_result_artifact(
      prepared,
      inputs,
      exported,
      combined,
      local_definition,
      receipt,
      admission,
      definition,
      publication.unwrap().source.invocation,
      publication.unwrap().source.observation,
      100000,
      10000,
      100,
    ).unwrap()
    assert_eq(
      client_effect_local_artifact_invocation_cid(artifact),
      combined.invocation.cid,
    )
    right_live.val = false
    assert_true(
      issue_combined_source_client_effect_local_result_artifact(
        prepared,
        inputs,
        exported,
        combined,
        local_definition,
        receipt,
        admission,
        definition,
        publication.unwrap().source.invocation,
        publication.unwrap().source.observation,
        100000,
        10000,
        100,
      )
      is Err(ForeignOwner),
    )
  }
  @strategy.release_captured_effect_inputs(inputs) |> ignore
  @local.cancel_managed_provider(child) |> ignore
  assert_true(@local.cleanup_managed_provider(child) is Ok(true))
}

///|
test "combined Source Unit keeps both original inputs and requires its actual completed producer" {
  combined_source_unit_completed_fixture()
}

///|
test "combined Source Unit refuses a foreign Run and another actual export receipt" {
  combined_source_unit_completed_fixture(foreign_controls=true)
}

///|
test "completed two-Source JOIN retains its original Unit Results before the consumer" {
  combined_source_unit_completed_fixture(early_unit=true)
}

///|
test "two-Source producer Artifact exists before its original later Model" {
  combined_source_unit_completed_fixture(early_unit=true, consumer_model=true)
}

///|
test "preconsumer Artifact binds its final original Run once without reissuing its body" {
  combined_source_unit_completed_fixture(early_unit=true, late_run_binding=true)
}

///|
test "saved original Result input Scope preserves the authenticated Artifact snapshot" {
  combined_source_unit_completed_fixture(
    early_unit=true,
    consumer_model=true,
    saved_artifact_scope=true,
  )
}

///|
test "Saved Artifact metadata rejects malformed bindings and retains original custody" {
  combined_source_unit_completed_fixture(
    early_unit=true,
    consumer_model=true,
    saved_artifact_scope=true,
    saved_artifact_controls=true,
  )
}

///|
test "combined Source Unit publishes canonical Request bodies from original noncanonical fields" {
  combined_source_unit_completed_fixture(canonical_request=true)
}

///|
test "joined Result scope keeps two original Source ancestors with one Artifact through Saved restore" {
  combined_source_unit_completed_fixture(
    early_unit=true,
    consumer_model=true,
    saved_artifact_scope=true,
    saved_artifact_controls=true,
    shared_ancestry=true,
  )
}

///|
test "joined original Result delivers both Source columns to actual Model request" {
  combined_source_unit_completed_fixture(
    early_unit=true,
    consumer_model=true,
    shared_ancestry=true,
    model_columns=true,
  )
}

///|
test "Source Unit construction geometry precedes the original bodies without Source current callbacks" {
  combined_source_unit_completed_fixture(
    early_unit=true,
    consumer_model=true,
    construction_geometry=true,
  )
}

///|
test "Source Unit Catalog wire construction honors the original before-body backing refusal" {
  combined_source_unit_completed_fixture(
    early_unit=true,
    consumer_model=true,
    catalog_guard=true,
  )
}

///|
test "original Unit Result Definition Artifact and Manifest geometry match their existing issuers" {
  combined_source_unit_completed_fixture(
    early_unit=true,
    consumer_model=true,
    artifact_geometry=true,
  )
}

///|
test "Model Effect import matching retains both Source ancestors through the original Result Scope before final inputs" {
  combined_source_unit_completed_fixture(
    early_unit=true,
    consumer_model=true,
    shared_ancestry=true,
    model_scope_imports=true,
  )
}

///|
test "Model Scope semantic body backing refuses before each actual original emitter boundary" {
  combined_source_unit_completed_fixture(
    early_unit=true,
    consumer_model=true,
    shared_ancestry=true,
    model_scope_backing=true,
  )
}
