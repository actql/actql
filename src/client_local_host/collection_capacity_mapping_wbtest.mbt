///|
// Match the ordinary Local service's selected row ceiling before compilation.
// This changes fixture Environment DATA, not the existing Resource authority.
fn collection_capacity_selected_environment(
  rows : Int,
) -> @checked.CheckEnvironment raise {
  let assets = @publication_host.client_local_product_assets()
  let parsed = @json.parse(assets.environment)
  guard parsed is Object(fields) &&
    fields["host_policy_profile"] is Object(profile) &&
    profile["capacity"] is Object(capacity) else {
    fail("Local fixture capacity")
  }
  fields.remove("evidence_bundle_cid")
  for
    name in [
      "max_relation_output_rows", "max_artifact_rows", "max_file_listing_items",
    ] {
    capacity[name] = @json.parse(rows.to_string())
  }
  let body = @identity.from_json(parsed, 100000, 100, 1000000)
  let cid = @identity.cid_value(body, 1000000, 100000, 100)
  fields["evidence_bundle_cid"] = @json.parse("\"" + cid + "\"")
  let wire = @identity.stringify_value(
    @identity.from_json(parsed, 100000, 100, 1000000),
    1000000,
    100000,
    100,
  )
  @publication_host.admit_client_check_environment(
    wire,
    cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
}

///|
fn collection_capacity_selected_prepared(
  sql : String,
  rows : Int,
) -> @publication_host.PreparedClientProgram raise {
  let environment = collection_capacity_selected_environment(rows)
  let cid = @checked.checking_environment_cid(environment)
  let original = @frontend.lower(
    sql,
    @frontend.Sql,
    Some(@frontend.bind_query_context([], cid).unwrap()),
    public_primary=true,
  ).unwrap()
  @publication_host.prepare_parsed_effect_free_client_program(
    original.program.unwrap(),
    environment,
    None,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
}

///|
// Pure constructor/capacity correspondence only; no Account, Run or provider work.
test "collection Append startup fits the original Local execution authority" {
  let digits : Array[String] = []
  for n in 0..<10 {
    digits.push("SELECT " + n.to_string() + " AS n")
  }
  let sql = "WITH d AS (" +
    digits.join(" UNION ALL ") +
    ") SELECT 0 AS n FROM d a CROSS JOIN d b CROSS JOIN d c CROSS JOIN d e CROSS JOIN d f WHERE a.n + 10*b.n + 100*c.n + 1000*e.n + 10000*f.n < 9999"
  let rows = client_local_materialized_row_ceiling(
    client_local_resource_policy(),
  ).unwrap()
  let prepared = collection_capacity_selected_prepared(sql, rows)
  // The Environment ceiling and the standard compiler row limit are distinct.
  assert_true(
    @publication_host.prepared_client_values_max_rows(prepared) <= rows,
  )
  let assets = @publication_host.client_local_product_assets()
  let contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let original = prepare_installed_managed_source_free_with_contracts(
    prepared,
    contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
    retained_output=false,
    provider_factory=_ => [],
  ).unwrap()
  let configuration = original.configuration.unwrap()
  let registration = @connector.capability_registration_at(
    configuration.registry,
    0,
  ).unwrap()
  let physical = Array::makei(original.sequences.length(), index => {
    let sequence = original.sequences[index]
    match @strategy.graph_task_selected_step(configuration.graph, index) {
      Some(step) =>
        @execution.select_generated_sequence_step(sequence, step).unwrap()
      None =>
        match @strategy.graph_task_prefix_end(configuration.graph, index) {
          Some(last) =>
            @execution.select_generated_sequence_prefix(sequence, last).unwrap()
          None => sequence
        }
    }
  })
  let installed = @local.prepare_local_compute_module(
    configuration.registry,
    registration,
    physical,
    original.capacity_plan.execution,
    original.capacity_plan.measurement,
    100,
    physical.length(),
    managed_capacity=configuration.capacity,
  ).unwrap()
  let mut matched = 0
  for index, sequence in physical {
    let full = @local.local_module_capacity_for_sequence(
      installed, index, sequence,
    ).unwrap()
    let start = @local.local_module_metered_output_start_capacity(
      installed, index, sequence,
    ).unwrap_or(full)
    let execution = start.execution_bytes + start.retained_bytes
    let retained = start.retained_bytes +
      original.capacity_plan.metadata.retained_bytes
    if @execution.generated_sequence_step_at(sequence, 0)
      is Some(@lower.AppendStep(_)) &&
      @execution.generated_sequence_step_count(sequence) == 1 {
      matched += 1
      assert_true(execution < client_local_execution_byte_ceiling())
      assert_eq(retained, 144648L)
    }
  }
  assert_true(matched > 0)
}
