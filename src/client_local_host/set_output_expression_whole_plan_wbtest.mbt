///|
// Same SQL and checked fixture publication; no installed physical grant or Run
// evidence is supplied by this bounded component diagnostic.
fn set_output_expression_prepared(
  text? : String = "WITH chosen AS (SELECT id FROM records WHERE amount >= 20 UNION ALL SELECT id FROM records WHERE amount IS NULL ORDER BY 0 - id LIMIT 2) SELECT id FROM chosen ORDER BY id",
  format? : @frontend.Format = @frontend.Sql,
) -> @publication_host.PreparedClientProgram raise {
  let environment = @publication_host.admit_client_check_environment(
    source_query_original_environment,
    "sha256:05ee9059ef5f173069a3f3f1896e16ee62d34d0c842d81e9b0f8421db62e67a8",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let body = @json.parse(source_query_original_environment)
  guard body is Object(root) &&
    root["schema_snapshots"] is Array(snapshots) &&
    snapshots[0] is Object(snapshot) else {
    abort("fixture snapshot")
  }
  let publication : Json = {
    "environmentCid": "sha256:05ee9059ef5f173069a3f3f1896e16ee62d34d0c842d81e9b0f8421db62e67a8",
    "aliases": [
      {
        "name": "records",
        "sourceRef": snapshot["source_ref"],
        "sourceViewContractCid": snapshot["source_view_contract_cid"],
        "schemaContractCid": snapshot["carrier_schema_contract_cid"],
      },
    ],
  }
  let selected = @source_publication.prepare_published_query_environment(
    environment,
    publication.stringify(),
  ).unwrap()
  let (lowered, catalog) = @source_publication.lower_prepared_published_query(
    selected,
    environment,
    text,
    format,
    None,
    public_primary=true,
  ).unwrap()
  @publication_host.prepare_parsed_effect_free_client_program(
    lowered.program.unwrap(),
    environment,
    None,
    @publication_host.client_standard_program_preparation_limits(),
    source_catalog=Some(catalog),
  ).unwrap()
}

///|
test "set output expression Whole Source preparation retains its original graph" {
  let prepared = set_output_expression_prepared()
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "set-output-expression",
  ).unwrap()
  assert_true(installed_managed_owner_shape_supported(Pure(prepared), false))
  let direct = installed_direct_occurrences_owned(Pure(prepared)).unwrap()
  assert_eq(
    @publication_host.client_direct_acquisition_occurrence_count(direct),
    1,
  )
  guard select_installed_source_input(prepared, request, 0, 0).unwrap()
    is @sourceviews.WholeInputRoute(original) else {
    fail("set expression must use the original Whole input")
  }
  let source = prepare_installed_catalog_whole_source_capacity(
    prepared,
    original,
    contracts,
    installed_row_input_policy(10000, 10000000, 110101, 2, 10000),
  ).unwrap()
  let graph = @strategy.prepare_source_inputs_dag(
    @publication_host.prepared_client_graph(prepared),
    [source.original],
  ).unwrap()
  let sequences = prepare_client_local_sequences_owned(
    Pure(prepared),
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  assert_eq(@strategy.graph_task_count(graph), 12)
  assert_eq(@strategy.graph_captured_prefix(graph), 0)
  assert_eq(sequences.length(), 12)
  let first = @strategy.graph_captured_prefix(graph)
  let tail = sequences[first:sequences.length()].to_owned()
  let max_rows = Int::max(
    @publication_host.prepared_client_values_max_rows(prepared),
    @row_source_host.row_input_acquisition_max_rows(source.acquisition),
  )
  let capacity_plan = client_local_capacity_plan(
    tail,
    max_rows,
    scalar_values=true,
    graph=Some(graph),
    graph_offset=first,
  )
  let inputs = Array::makei(tail.length(), index => {
    @strategy.graph_task_input_count(graph, first + index).unwrap()
  })
  assert_true(
    client_local_sequence_capacity_original(
      tail,
      @strategy.graph_task_count(graph),
      capacity_plan=Some(capacity_plan),
      retained_inputs=Some(inputs),
      max_rows~,
    )
    is None,
  )
  let runtime_capacity = client_local_sequence_capacity_original(
    tail,
    @strategy.graph_task_count(graph),
    capacity_plan=Some(capacity_plan),
    retained_inputs=Some(inputs),
    max_rows~,
    runtime_admission=true,
  ).unwrap()
  assert_eq(
    runtime_capacity.limits.retained_bytes,
    client_local_retained_byte_ceiling(),
  )
  assert_eq(
    runtime_capacity.limits.execution_bytes,
    client_local_execution_byte_ceiling(),
  )
  let mut full_retained = 0L
  for sequence in tail {
    let quote = @execution.generated_sequence_capacity(
      sequence,
      capacity_plan.execution,
      capacity_plan.measurement,
    ).unwrap()
    full_retained += @execution.execution_capacity_retained_bytes(quote)
  }
  assert_true(full_retained > client_local_retained_byte_ceiling())
  assert_true(
    prepare_installed_compute_preparation(
      Pure(prepared),
      None,
      sequences,
      [],
      [10000000L],
      [239908928L],
      false,
      _ => [],
      physical_graph=Some(graph),
      whole_capacities=[source],
    )
    is Err(Unsupported),
  )
  let runtime = prepare_installed_compute_preparation(
    Pure(prepared),
    None,
    sequences,
    [],
    [10000000L],
    [239908928L],
    false,
    _ => [],
    runtime_admission=true,
    physical_graph=Some(graph),
    whole_capacities=[source],
  ).unwrap()
  assert_true(physical_equal(runtime.capacity_plan.graph.unwrap(), graph))
  assert_true(
    prepare_installed_managed_whole_source_plan(
      prepared,
      request,
      source,
      10000000L,
      239908928L,
      contracts,
      source_query_original_values,
      Some(source_query_original_fragment),
      None,
      retained_output=false,
      provider_factory=_ => [],
    )
    is Err(Unsupported),
  )
  let plan = prepare_installed_managed_whole_source_plan(
    prepared,
    request,
    source,
    10000000L,
    239908928L,
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    retained_output=false,
    provider_factory=_ => [],
    runtime_admission=true,
  ).unwrap()
  assert_true(physical_equal(plan.prepared, prepared))
  assert_true(physical_equal(plan.request, request))
  assert_true(physical_equal(plan.whole_sources[0], source))
  let (selector_retained, _) = installed_direct_occurrences_layout(1).unwrap()
  assert_eq(
    plan.limits.retained_bytes,
    runtime.limits.retained_bytes + selector_retained,
  )
  assert_eq(
    plan.limits.execution_bytes,
    runtime.limits.execution_bytes + selector_retained,
  )
  assert_eq(plan.limits.transfer_bytes, runtime.limits.transfer_bytes)
}
