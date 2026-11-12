///|
// Same compiler-material seam as the public two-Model fixture: the first
// original has a real keyed file/Content profile; the second consumes its
// completed rows. No Source IO, Provider, Run/state/key or authority double.
fn plural_keyed_original_materials_fixture() -> (
  PreparedClientProgram,
  Array[ClientInferOccurrence],
  Array[ClientInferPlanGraph],
) raise {
  let (first, keyed, profile) = client_keyed_plan_test_inputs(plural=true)
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
    None => fields.remove("native_read_profile") |> ignore
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
