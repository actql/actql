///|
fn metadata_capacity_prepared(
  query : String,
  max_rows : Int,
) -> @publication_host.PreparedClientProgram raise {
  let assets = @publication_host.client_local_product_assets()
  guard @json.parse(assets.environment) is Object(fields) &&
    fields.get("evidence_bundle_cid") is Some(String(cid)) else {
    fail("ordinary product Environment evidence missing")
  }
  let environment = @publication_host.admit_client_check_environment(
    assets.environment,
    cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let lowered = @frontend.lower(
    query,
    @frontend.Sql,
    Some(@frontend.bind_query_context([], cid).unwrap()),
    public_primary=true,
  ).unwrap()
  let prepared = @publication_host.prepare_effect_free_client_program(
    lowered.document,
    lowered.format,
    environment,
    None,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  @publication_host.with_prepared_client_values_row_limit(prepared, max_rows).unwrap()
}

///|
test "metadata quote failure is distinguished before provider construction" {
  let assets = @publication_host.client_local_product_assets()
  let contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let prepared = metadata_capacity_prepared(
    "SELECT x FROM UNNEST([1, 2]) AS x", 10000000,
  )
  let sequences = prepare_client_local_sequences(
    prepared,
    contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let plan = client_local_capacity_plan(
    sequences,
    10000000,
    scalar_values=true,
    graph=Some(@publication_host.prepared_client_graph(prepared)),
  )
  assert_true(plan._retained_result_envelope is Some(_))
  assert_eq(plan.metadata_retained_bytes, 0L)
  assert_false(client_local_capacity_plan_matches(plan, sequences, 10000000))
  let mut factories = 0
  let result = prepare_installed_managed_source_free_with_contracts(
    prepared,
    contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
    retained_output=true,
    provider_factory=_ => {
      factories += 1
      []
    },
  )
  assert_true(result is Err(MetadataCapacityUnavailable))
  assert_eq(factories, 0)
}

///|
test "metadata capacity controls preserve successful scalar and general layouts" {
  let assets = @publication_host.client_local_product_assets()
  let contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  for
    (query, rows) in [
      ("SELECT x FROM UNNEST([1, 2]) AS x", 100),
      ("SELECT 7 AS x", 10000000),
      ("SELECT x FROM UNNEST([1, 2]) AS x WHERE FALSE", 100),
    ] {
    let prepared = metadata_capacity_prepared(query, rows)
    let sequences = prepare_client_local_sequences(
      prepared,
      contracts,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
    ).unwrap()
    let graph = @publication_host.prepared_client_graph(prepared)
    let plan = client_local_capacity_plan(
      sequences,
      rows,
      scalar_values=true,
      graph=Some(graph),
    )
    assert_true(plan.metadata_retained_bytes > 0L)
    assert_true(client_local_capacity_plan_matches(plan, sequences, rows))
    let envelope = plan._retained_result_envelope.unwrap()
    if query == "SELECT 7 AS x" {
      let proof = plan.schema_inventory.unwrap()
      let specialized = client_local_scalar_metadata_envelope(
        proof,
        graph,
        plan.execution.rows.max_rows,
        envelope,
      ).unwrap()
      assert_eq(plan.metadata_retained_bytes, specialized.0)
    } else {
      assert_true(plan.schema_inventory is None)
      assert_eq(
        client_local_result_metadata_retained(
          envelope,
          plan.execution.rows.max_rows,
          client_node_publication_schema_bytes(),
        ),
        Some(plan.metadata_retained_bytes),
      )
    }
    let generic = client_local_capacity_plan(
      sequences,
      rows,
      scalar_values=false,
      graph=Some(graph),
    )
    assert_eq(
      generic.metadata_retained_bytes,
      client_local_cleanup_retained_bytes(),
    )
    assert_true(client_local_capacity_plan_matches(generic, sequences, rows))
    let no_graph = client_local_capacity_plan(sequences, rows)
    assert_eq(no_graph.metadata_retained_bytes, 0L)
    assert_true(client_local_capacity_plan_matches(no_graph, sequences, rows))
  }
}

///|
test "metadata envelope absence at represented maximum keeps the existing fallback" {
  let assets = @publication_host.client_local_product_assets()
  let contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let prepared = metadata_capacity_prepared(
    "SELECT x FROM UNNEST([1, 2]) AS x", 2147483647,
  )
  let sequences = prepare_client_local_sequences(
    prepared,
    contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let plan = client_local_capacity_plan(
    sequences,
    2147483647,
    scalar_values=true,
    graph=Some(@publication_host.prepared_client_graph(prepared)),
  )
  assert_true(plan._retained_result_envelope is None)
  assert_eq(plan.metadata_retained_bytes, client_local_cleanup_retained_bytes())
  assert_true(client_local_capacity_plan_matches(plan, sequences, 2147483647))
}

///|
test "metadata quote retains empty typed Results with aliases and repeated order" {
  let prepared = result_envelope_fixture()
  let original = publication_plan_fixture(prepared)
  assert_true(original.capacity_plan._retained_result_envelope is Some(_))
  assert_true(original.capacity_plan.metadata_retained_bytes > 0L)
  assert_true(
    client_local_capacity_plan_matches(
      original.capacity_plan,
      original.sequences,
      @publication_host.prepared_client_values_max_rows(prepared),
    ),
  )
}
