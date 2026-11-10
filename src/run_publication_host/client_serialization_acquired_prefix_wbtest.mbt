///|
test "acquired Serialize prefix retains its checked Source port and common internal sort" {
  let document =
    #|{"version":"actql/0.1","id":"acquired-content-prefix","stages":[{"id":"main","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id >= 0","as":"filtered"},{"assert_rows":{"unique_by":["id"]},"as":"unique"},{"serialize":{"format":"jsonl","fields":["id","amount"],"order_by":[{"id":"asc"}],"name":"out.jsonl"},"as":"attachment"}],"results":{"file":{"from":"attachment","fields":["name","content"]}}}],"results":{"file":{"from":{"stage":"main","result":"file"}}}}
  let owner = multi_source_prepared(document)
  assert_eq(prepared_client_acquisition_count(owner), 1)
  assert_eq(prepared_client_serialization_occurrences(owner), [(0, 2)])
  let prefix = issue_prepared_client_serialization_prefix_fragment(
    owner,
    0,
    2,
    10000,
    client_standard_values_sequence_limits(),
    1000000,
    100000,
    100,
  ).unwrap()
  let body = parse_plan_identity_value(prefix.wire, 1000000, 100000, 100).unwrap()
  let pipeline = @canonical.object_field(body, "pipeline").unwrap()
  let sources = @canonical.object_field(pipeline, "sources").unwrap()
  assert_eq(
    @canonical.stringify_value(sources, 10000, 1000, 20),
    "{\"remote\":{\"sort\":\"relation\"}}",
  )
  let contracts = @canonical.object_field(body, "input_contracts").unwrap()
  // Independently hashed bare Carrier schema, not the Catalog envelope CID:
  // {additional_properties:false,fields:{amount:{nullable:true,type:number},
  // id:{nullable:false,type:number}},nullable:false,type:object}.
  assert_eq(
    @canonical.stringify_value(contracts, 10000, 1000, 20),
    "{\"remote\":\"sha256:9acb07a25a365ae4cc47286f663bea8727eea912cdc188cddb55ca136c38c163\"}",
  )
  assert_true(prefix.wire.contains("REL.where"))
  assert_true(prefix.wire.contains("REL.orderByStable"))
  assert_false(prefix.wire.contains("REL.values"))
  assert_false(prefix.wire.contains("Content.serialize"))
  assert_eq(prefix.output_carrier, "relation")
  // A pure prefix is not acquisition evidence or a completed Content Run.
  // Until the capture inventory is connected, the old source-free issuer must
  // still refuse this Program rather than issue a fabricated empty inventory.
  assert_true(
    issue_prepared_client_serialization_plan_graph(
      owner,
      0,
      2,
      serialization_plan_test_policy(),
      10,
      1000,
      10000,
      client_standard_values_sequence_limits(),
      1000000,
      100000,
      100,
    )
    is Err(UnsupportedGraph),
  )
}

///|
test "acquired Serialize Plan retains its complete checked policy without source-free evidence" {
  let document =
    #|{"version":"actql/0.1","id":"acquired-content-plan","stages":[{"id":"main","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id >= 0","as":"filtered"},{"select":["id","amount"],"as":"captured"},{"assert_rows":{"unique_by":["id"]},"as":"unique"},{"serialize":{"format":"jsonl","fields":["id","amount"],"order_by":[{"id":"asc"}],"name":"out.jsonl"},"as":"attachment"}],"results":{"file":{"from":"attachment","fields":["name","content"]}}}],"results":{"file":{"from":{"stage":"main","result":"file"}}}}
  let owner = multi_source_prepared(document)
  let bodies = match
    prepared_client_publication_policy_bodies(owner, 1000000, 100000, 100) {
    Ok(bodies) => bodies
    Err(@checked.MissingUnit) =>
      fail("original publication policy bodies: MissingUnit")
    Err(@checked.MissingDependency) =>
      fail("original publication policy bodies: MissingDependency")
    Err(@checked.Encoding(_)) =>
      fail("original publication policy bodies: Encoding")
    Err(@checked.ForeignBody) =>
      fail("original publication policy bodies: ForeignBody")
    Err(@checked.BudgetExceeded) =>
      fail("original publication policy bodies: BudgetExceeded")
  }
  assert_eq(
    bodies[0].1,
    prepared_client_publication_data_policy_cid(owner).unwrap(),
  )
  // Independent Catalog pin for the input Source policy, not the Result's
  // effective policy or the Host's empty unknown-provenance policy.
  assert_true(
    bodies[0].2.contains(
      "sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf",
    ),
  )
  assert_false(bodies[0].2.contains("\"source_data_policy_cids\":[]"))
  assert_eq(@strategy.graph_task_count(owner.graph), 1)
  assert_eq(prepared_client_acquisition_count(owner), 1)
  assert_true(client_single_direct_observation_covers_sources(owner))
  let component = match
    issue_prepared_client_acquired_serialization_plan_graph(
      owner,
      0,
      3,
      10,
      1000,
      10000,
      client_standard_values_sequence_limits(),
      1000000,
      100000,
      100,
    ) {
    Ok(value) => value
    Err(Policy(_)) => fail("checked policy rejected: " + bodies[0].2)
    Err(UnsupportedGraph) => fail("acquired graph shape rejected")
    Err(Preparation(_)) => fail("Serialize preparation rejected")
    Err(Input(_)) => fail("Serialize input fragment rejected")
    Err(Root(_)) => fail("Serialize Result root rejected")
    Err(Encoding) => fail("Serialize graph encoding rejected")
    Err(PolicyClosure(_)) => fail("Serialize policy closure rejected")
    Err(_) => fail("another acquired graph issue")
  }
  assert_eq(
    @publication.captured_effect_dependency_body_cid(component.policy),
    bodies[0].1,
  )
  assert_eq(
    @publication.captured_effect_dependency_body_json(component.policy),
    bodies[0].2,
  )
  assert_true(component.input.wire.contains("\"remote\""))
  assert_true(component.input.wire.contains("REL.orderByStable"))
  assert_false(component.input.wire.contains("REL.values"))
  let intermediate = issue_prepared_client_acquired_serialization_plan_component(
    owner,
    0,
    3,
    10,
    1000,
    10000,
    client_standard_values_sequence_limits(),
    1000000,
    100000,
    100,
  ).unwrap()
  assert_eq(intermediate.input.wire, component.input.wire)
  assert_eq(intermediate.output.wire, component.output.wire)
  assert_eq(
    @publication.captured_effect_dependency_body_cid(intermediate.policy),
    bodies[0].1,
  )
  let body = parse_plan_identity_value(
    intermediate.graph.wire,
    1000000,
    100000,
    100,
  ).unwrap()
  assert_eq(
    @canonical.stringify_value(
      @canonical.object_field(body, "root_refs").unwrap(),
      10000,
      1000,
      20,
    ),
    "[]",
  )
  let compilation = issue_prepared_client_serialization_compilation(
    owner,
    component,
    run_materials_manifests(),
    1000,
    1000,
    1000000,
    100000,
    100,
  ).unwrap()
  let run = issue_client_task_compiled_run(
    owner,
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  assert_true(client_compiled_run_source_free_result_policy_body(run) is None)
  assert_true(
    client_compiled_run_serialization_policy_body(run) is Some(original) &&
    physical_equal(original, component.policy),
  )
  assert_true(
    issue_client_task_source_free_invocation(
      compilation,
      bodies[0].1,
      1000000,
      100000,
      100,
    )
    is Err(@publication.RunEvidenceReferenceMismatch("content_generation")),
  )
  assert_true(
    issue_prepared_client_acquired_serialization_plan_graph(
      serialization_preparation_test_program(),
      0,
      1,
      10,
      1000,
      10000,
      client_standard_values_sequence_limits(),
      1000000,
      100000,
      100,
    )
    is Err(UnsupportedGraph),
  )
  assert_true(
    issue_prepared_client_acquired_serialization_plan_component(
      serialization_preparation_test_program(),
      0,
      1,
      10,
      1000,
      10000,
      client_standard_values_sequence_limits(),
      1000000,
      100000,
      100,
    )
    is Err(UnsupportedGraph),
  )
  assert_true(
    issue_prepared_client_acquired_serialization_plan_graph(
      owner,
      0,
      3,
      10,
      1000,
      10000,
      client_standard_values_sequence_limits(),
      1,
      100000,
      100,
    )
    is Err(PolicyClosure(_)),
  )
  assert_true(
    issue_prepared_client_acquired_serialization_plan_component(
      owner,
      0,
      2,
      10,
      1000,
      10000,
      client_standard_values_sequence_limits(),
      1000000,
      100000,
      100,
    )
    is Err(SourcePolicy(@checked.ForeignOwner)),
  )
  assert_true(
    issue_prepared_client_acquired_serialization_plan_component(
      owner,
      0,
      3,
      10,
      1000,
      0,
      client_standard_values_sequence_limits(),
      1000000,
      100000,
      100,
    )
    is Err(PolicyClosure(@checked.BudgetExceeded)),
  )
}
