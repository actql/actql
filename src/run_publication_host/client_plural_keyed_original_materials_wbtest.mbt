///|
// Same compiler-material seam as the public two-Model fixture: the first
// original has a real keyed file/Content profile; the second consumes its
// completed rows. No Source IO, Provider, Run/state/key or authority double.
fn plural_keyed_original_materials_fixture(
  declared? : Bool = false,
) -> (
  PreparedClientProgram,
  Array[ClientInferOccurrence],
  Array[ClientInferPlanGraph],
) raise {
  let (first, keyed, profile) = client_keyed_plan_test_inputs(
    plural=true,
    declared~,
  )
  let prepared = first.owner
  let occurrences = prepared_client_composed_infer_occurrences(prepared).unwrap()
  assert_eq(occurrences.length(), 2)
  let graphs = occurrences.mapi((index, occurrence) => {
    let execution = client_infer_graph_test_execution(
      prepared,
      occurrence=Some(occurrence),
    )
    issue_installed_client_composed_infer_plan_graph(
      occurrence,
      execution,
      client_standard_values_sequence_limits(),
      1000000,
      100000,
      100,
      keyed_native_read=if index == 0 { Some((keyed, profile)) } else { None },
    ).unwrap()
  })
  assert_true(client_infer_plan_native_keyed_read_profile(graphs[0]) is Some(_))
  assert_true(client_infer_plan_native_keyed_read_profile(graphs[1]) is None)
  (prepared, occurrences, graphs)
}

///|
test "plural original materials retain the actual first native-read compiler profile" {
  let (prepared, occurrences, graphs) = plural_keyed_original_materials_fixture()
  let limits = run_materials_limits()
  let wire = match
    encode_client_infer_original_inventory(occurrences, graphs, limits) {
    Ok(value) => value
    Err(Binding(UnsupportedProgram)) =>
      fail("OriginalInventoryBindingUnsupportedProgram")
    Err(Input(MaterialsEvidence(name))) =>
      fail("OriginalInventoryEvidence:" + name)
    Err(_) => fail("OriginalInventoryOtherTypedIssue")
  }
  let restored = read_plural_client_infer_run_graphs(prepared, wire, limits).unwrap()
  assert_eq(restored.length(), 2)
  for index in 0..<2 {
    assert_eq(restored[index].graph.wire, graphs[index].graph.wire)
  }
}

///|
fn plural_keyed_inventory_profile(
  wire : String,
  index : Int,
  profile : Json?,
) -> String raise {
  guard @json.parse(wire) is Array(entries) && entries[index] is Object(fields) else {
    fail("original inventory object")
  }
  match profile {
    None => {
      fields.remove("native_read_profile") |> ignore
      fields.remove("native_read_profile_kind") |> ignore
    }
    Some(value) => fields["native_read_profile"] = value
  }
  Json::array(entries).stringify()
}

///|
test "plural native profile admission binds the same Source schema and occurrence" {
  let (prepared, occurrences, graphs) = plural_keyed_original_materials_fixture()
  let bounds = run_materials_limits()
  let wire = encode_client_infer_original_inventory(occurrences, graphs, bounds).unwrap()
  let profile = @publication.publication_contract_json(
    client_infer_plan_native_keyed_read_profile(graphs[0]).unwrap(),
  )
  guard @json.parse(profile) is Object(fields) else {
    fail("original native profile")
  }
  // Both CIDs are real authored declaration members. The physical row view is
  // not the logical keyed Source selected by this checked occurrence.
  assert_true(
    fields["source_view_contract_cid"] !=
    fields["physical_source_view_contract_cid"],
  )
  fields["source_view_contract_cid"] = fields["physical_source_view_contract_cid"]
  let foreign = Json::object(fields).stringify()
  for
    changed in [
      Json::null(),
      Json::number(1),
      Json::string("{}"),
      Json::string(foreign),
    ] {
    assert_true(
      read_plural_client_infer_run_graphs(
        prepared,
        plural_keyed_inventory_profile(wire, 0, Some(changed)),
        bounds,
      )
      is Err(_),
    )
  }
  // An unchanged valid contract is still foreign to the dependent Model with
  // no keyed join; equal Task/execution CIDs cannot widen its original ports.
  assert_true(
    read_plural_client_infer_run_graphs(
      prepared,
      plural_keyed_inventory_profile(wire, 1, Some(Json::string(profile))),
      bounds,
    )
    is Err(_),
  )
}

///|
test "plural native original encoder preserves owner wire order and original caps" {
  let (_, occurrences, graphs) = plural_keyed_original_materials_fixture()
  let (_, _, foreign) = plural_keyed_original_materials_fixture()
  let bounds = run_materials_limits()
  let damaged = {
    ..graphs[0],
    graph: { ..graphs[0].graph, wire: graphs[0].graph.wire + " ", },
  }
  for
    changed in [
      [foreign[0], graphs[1]],
      [damaged, graphs[1]],
      [graphs[1], graphs[0]],
      [graphs[0], graphs[0]],
    ] {
    assert_true(
      encode_client_infer_original_inventory(occurrences, changed, bounds)
      is Err(_),
    )
  }
  let wire = encode_client_infer_original_inventory(occurrences, graphs, bounds).unwrap()
  for
    limited in [
      { ..bounds, max_evidence_bytes: 8, },
      { ..bounds, max_evidence_nodes: 1, },
      { ..bounds, max_evidence_depth: 1, },
    ] {
    assert_true(
      encode_client_infer_original_inventory(occurrences, graphs, limited)
      is Err(_),
    )
    assert_true(
      read_plural_client_infer_run_graphs(occurrences[0].owner, wire, limited)
      is Err(_),
    )
  }
}

///|
test "legacy plural entries neither invent native profiles nor preserve a removed native graph" {
  let (prepared, occurrences, graphs) = plural_keyed_original_materials_fixture()
  let bounds = run_materials_limits()
  let original = encode_client_infer_original_inventory(
    occurrences, graphs, bounds,
  ).unwrap()
  let removed = plural_keyed_inventory_profile(original, 0, None)
  let restored = read_plural_client_infer_run_graphs(prepared, removed, bounds).unwrap()
  assert_true(client_infer_plan_native_keyed_read_profile(restored[0]) is None)
  assert_true(restored[0].graph.wire != graphs[0].graph.wire)
  assert_eq(restored[1].graph.wire, graphs[1].graph.wire)
  let legacy = encode_client_infer_original_inventory(
    occurrences, restored, bounds,
  ).unwrap()
  assert_eq(legacy, removed)
  let compile = graphs => {
    issue_prepared_client_multi_infer_compilation(
      prepared,
      graphs,
      run_materials_manifests(),
      bounds.sequence,
      bounds.max_sequence_steps,
      bounds.max_sequence_work,
      bounds.max_evidence_bytes,
      bounds.max_evidence_nodes,
      bounds.max_evidence_depth,
    ).unwrap()
  }
  let original_plan = compile(graphs).compiled_plan
  let removed_plan = compile(restored).compiled_plan
  // The existing complete compiled-plan/Run fence cannot accept stripped
  // material as the original. Legacy absence never fabricates a read profile.
  assert_true(
    @publication.publication_contract_identity(original_plan) !=
    @publication.publication_contract_identity(removed_plan),
  )
}

///|
test "plural Node original materials preserve the actual declared-file contract kind" {
  let (prepared, occurrences, graphs) = plural_keyed_original_materials_fixture(
    declared=true,
  )
  let profile = client_infer_plan_native_keyed_read_profile(graphs[0]).unwrap()
  assert_eq(
    @publication.publication_contract_name(profile),
    "declared_file_content_read",
  )
  assert_true(
    @publication.admit_publication_contract(
      "native_file_content_read",
      @publication.publication_contract_json(profile),
      100000,
      10000,
      100,
    )
    is Err(_),
  )
  let bounds = run_materials_limits()
  let wire = encode_client_infer_original_inventory(occurrences, graphs, bounds).unwrap()
  let restored = match
    read_plural_client_infer_run_graphs(prepared, wire, bounds) {
    Ok(value) => value
    Err(_) => fail("NodeDeclaredProfileRestoreRejected")
  }
  assert_eq(restored.length(), 2)
  for index in 0..<2 {
    assert_eq(restored[index].graph.wire, graphs[index].graph.wire)
  }
  let original = client_infer_plan_native_keyed_read_profile(restored[0]).unwrap()
  assert_eq(
    @publication.publication_contract_name(original),
    "declared_file_content_read",
  )
  assert_eq(
    @publication.publication_contract_identity(original),
    @publication.publication_contract_identity(profile),
  )
}

///|
fn plural_keyed_inventory_field(
  wire : String,
  field : String,
  value : Json?,
) -> String raise {
  guard @json.parse(wire) is Array(entries) && entries[0] is Object(fields) else {
    fail("original inventory kind pair")
  }
  match value {
    None => fields.remove(field) |> ignore
    Some(value) => fields[field] = value
  }
  Json::array(entries).stringify()
}

///|
test "plural file profile kind is closed paired and never a Native fallback for Node" {
  for declared in [false, true] {
    let (prepared, occurrences, graphs) = plural_keyed_original_materials_fixture(
      declared~,
    )
    let bounds = run_materials_limits()
    let wire = encode_client_infer_original_inventory(
      occurrences, graphs, bounds,
    ).unwrap()
    let wrong_kind = if declared {
      "native_file_content_read"
    } else {
      "declared_file_content_read"
    }
    for
      (field, value) in [
        ("native_read_profile_kind", None),
        ("native_read_profile", None),
        ("native_read_profile_kind", Some(Json::null())),
        ("native_read_profile_kind", Some(Json::number(1))),
        (
          "native_read_profile_kind",
          Some(Json::string("unknown_file_content_read")),
        ),
        ("native_read_profile_kind", Some(Json::string(wrong_kind))),
      ] {
      assert_true(
        read_plural_client_infer_run_graphs(
          prepared,
          plural_keyed_inventory_field(wire, field, value),
          bounds,
        )
        is Err(_),
      )
    }
  }
}

///|
fn single_keyed_effect_original_fixture(
  declared? : Bool = false,
) -> ClientEffectCompilation raise {
  let (first, _, profile) = client_keyed_plan_test_inputs(
    plural=true,
    declared~,
  )
  let checked = @strategy.graph_program(first.owner.graph)
  let (effect_document, effect_environment, _) = local_update_normalization_fixture()
  let writer = @encode.writer(1000000, 100000, 100)
  @environment.emit(@checked.checked_environment(checked), writer)
  guard @json.parse(@encode.finish(writer)) is Object(environment_fields) else {
    fail("original keyed Environment")
  }
  let writer = @encode.writer(1000000, 100000, 100)
  @environment.emit(
    @checked.checking_environment_wire(effect_environment),
    writer,
  )
  guard @json.parse(@encode.finish(writer)) is Object(effect_fields) &&
    environment_fields["connector_manifest"] is Object(manifest) &&
    manifest["connectors"] is Array(connectors) &&
    effect_fields["connector_manifest"] is Object(effect_manifest) &&
    effect_manifest["connectors"] is Array(effect_connectors) else {
    fail("actual Effect declaration metadata")
  }
  for connector in effect_connectors {
    connectors.push(connector)
  }
  let cid = (value : Json) => {
    @canonical.cid_value(
      @canonical.from_json(value, 100000, 100, 1000000),
      1000000,
      100000,
      100,
    )
  }
  // Mapping references name the same individual connector-manifest entry,
  // not the aggregate list. Appending the checked Source changes no entry.
  for
    name in [
      "connector_catalogs", "contract_registry", "source_views", "schema_snapshots",
      "connector_capabilities", "command_contracts", "mapping_contracts",
    ] {
    guard environment_fields[name] is Array(originals) &&
      effect_fields[name] is Array(additions) else {
      fail("actual declaration member array")
    }
    for value in additions {
      originals.push(value)
    }
    let ordered = originals.map(value => (cid(value), value))
    ordered.sort_by((a, b) => a.0.compare(b.0))
    originals.clear()
    for value in ordered {
      originals.push(value.1)
    }
  }
  environment_fields.remove("evidence_bundle_cid") |> ignore
  let environment_cid = cid(Json::object(environment_fields))
  environment_fields["evidence_bundle_cid"] = Json::string(environment_cid)
  let environment = admit_client_check_environment(
    @canonical.stringify_value(
      @canonical.from_json(
        Json::object(environment_fields),
        100000,
        100,
        1000000,
      ),
      1000000,
      100000,
      100,
    ),
    environment_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let writer = @encode.writer(1000000, 100000, 100)
  @syntax.emit_program_source(first.owner.source, writer)
  guard @json.parse(@encode.finish(writer)) is Object(fields) &&
    fields["stages"] is Array(stages) else {
    fail("same original keyed stages")
  }
  guard @json.parse(effect_document) is Object(effect_fields) &&
    effect_fields["stages"] is Array(effect_stages) else {
    fail("original authored Effect stage")
  }
  fields["stages"] = Json::array([stages[0], stages[1], effect_stages[0]])
  fields["results"] = @json.parse(
    (
      #|{"answer":{"from":{"stage":"main","result":"rows"}}}
    ),
  )
  let prepared = match
    prepare_client_effect_computation(
      Json::object(fields).stringify(),
      Json,
      environment,
      None,
      [],
      client_standard_effect_computation_limits(),
    ) {
    Ok(value) => value
    Err(Candidate(Computation(issue))) => raise issue
    Err(Candidate(MissingEffects)) => fail("SingleEffectMissingEffects")
    Err(Candidate(_)) => fail("SingleEffectCandidate")
    Err(Mapping(issue)) =>
      fail("SingleEffectMapping:" + @debug.to_string(issue))
    Err(Graph(issue)) => fail("SingleEffectGraph:" + @debug.to_string(issue))
    Err(Static(_)) => fail("SingleEffectStatic")
    Err(_) => fail("SingleEffectOtherPreparation")
  }
  let occurrence = prepared_client_effect_infer_occurrence(prepared).unwrap()
  let keyed = select_client_effect_model_keyed_acquisition(prepared, occurrence)
    .unwrap()
    .unwrap()
  let bounds = run_materials_limits()
  let graph = issue_installed_client_composed_infer_plan_graph(
    occurrence,
    client_infer_graph_test_execution(
      occurrence.owner,
      occurrence=Some(occurrence),
    ),
    bounds.sequence,
    bounds.max_evidence_bytes,
    bounds.max_evidence_nodes,
    bounds.max_evidence_depth,
    keyed_native_read=Some((keyed, profile)),
  ).unwrap()
  issue_prepared_client_effect_compilation(
    prepared,
    run_materials_manifests(),
    bounds.sequence,
    bounds.max_sequence_steps,
    bounds.max_sequence_work,
    bounds.max_evidence_bytes,
    bounds.max_evidence_nodes,
    bounds.max_evidence_depth,
    infer=Some(graph),
  ).unwrap()
}

///|
test "single Node Effect originals restore their actual declared-file profile" {
  let original = single_keyed_effect_original_fixture(declared=true)
  let input = client_effect_original_infer_input(original).unwrap()
  let profile = client_effect_original_infer_native_read_profile(original).unwrap()
  let restored = match
    restore_client_effect_original_infer(
      original.owner,
      input,
      run_materials_limits(),
      native_read_profile=profile,
    ) {
    Ok(Some(value)) => value
    _ => fail("SingleNodeDeclaredProfileRestoreRejected")
  }
  assert_eq(restored.graph.wire, original.compiled.infer.unwrap().graph.wire)
  assert_eq(
    @publication.publication_contract_name(
      client_infer_plan_native_keyed_read_profile(restored).unwrap(),
    ),
    "declared_file_content_read",
  )
}

///|
test "single file originals retain Native wire and reject Source Model profile and bound substitutions" {
  for declared in [false, true] {
    let original = single_keyed_effect_original_fixture(declared~)
    let graph = original.compiled.infer.unwrap()
    let profile = client_infer_plan_native_keyed_read_profile(graph).unwrap()
    let kind = @publication.publication_contract_name(profile)
    let body = @publication.publication_contract_json(profile)
    let input = client_effect_original_infer_input(original).unwrap()
    assert_eq(
      client_effect_original_infer_native_read_profile(original).unwrap(),
      Some(body),
    )
    let bounds = run_materials_limits()
    let restored = restore_client_effect_original_infer(
        original.owner,
        input,
        bounds,
        native_read_profile=Some(body),
      )
      .unwrap()
      .unwrap()
    assert_eq(restored.graph.wire, graph.graph.wire)
    assert_eq(
      @publication.publication_contract_name(
        client_infer_plan_native_keyed_read_profile(restored).unwrap(),
      ),
      kind,
    )
    guard @json.parse(body) is Object(fields) else {
      fail("original file profile body")
    }
    let source = fields["physical_source_view_contract_cid"]
    fields.remove(@publication.publication_contract_identity_field(profile))
    |> ignore
    fields["source_view_contract_cid"] = source
    let canonical = (value : Json) => {
      @canonical.stringify_value(
        @canonical.from_json(value, 100000, 100, 1000000),
        1000000,
        100000,
        100,
      )
    }
    let foreign = @publication.seal_publication_contract(
      kind,
      canonical(Json::object(fields)),
      100000,
      10000,
      100,
    ).unwrap()
    for
      changed in [
        @publication.publication_contract_json(foreign),
        body.replace(old="\"text\"", new="\"unbound\""),
        body.replace(
          old=if declared {
            "actql-declared-file-content-read/0.1"
          } else {
            "actql-native-file-content-read/0.1"
          },
          new="actql-unknown-file-content-read/0.1",
        ),
      ] {
      assert_true(
        restore_client_effect_original_infer(
          original.owner,
          input,
          bounds,
          native_read_profile=Some(changed),
        )
        is Err(_),
      )
    }
    let (_, execution_wire) = input.unwrap()
    guard @json.parse(execution_wire) is Object(execution) else {
      fail("original execution body")
    }
    execution.remove("self_cid") |> ignore
    execution["model_task_contract_cid"] = source
    let foreign_execution = @canonical.from_json(
      Json::object(execution),
      100000,
      100,
      1000000,
    )
    let foreign_cid = @canonical.cid_value(
      foreign_execution, 1000000, 100000, 100,
    )
    execution["self_cid"] = Json::string(foreign_cid)
    assert_true(
      restore_client_effect_original_infer(
        original.owner,
        Some((foreign_cid, canonical(Json::object(execution)))),
        bounds,
        native_read_profile=Some(body),
      )
      is Err(_),
    )
    for
      limited in [
        { ..bounds, max_evidence_bytes: 8, },
        { ..bounds, max_evidence_nodes: 1, },
        { ..bounds, max_evidence_depth: 1, },
      ] {
      assert_true(
        restore_client_effect_original_infer(
          original.owner,
          input,
          limited,
          native_read_profile=Some(body),
        )
        is Err(_),
      )
    }
  }
}
