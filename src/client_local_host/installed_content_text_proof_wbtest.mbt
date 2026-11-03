///|
fn installed_content_text_plan(
  content : ClientInstalledEffectContentPreparation,
) -> ClientLocalCapacityPlan {
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let sequences = prepare_client_effect_local_sequences(
    content.prepared,
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  client_local_capacity_plan(
    sequences,
    100,
    scalar_values=true,
    graph=Some(installed_managed_owner_graph(Effect(content.prepared))),
    content=Some(content),
  )
}

///|
test "same serializer metadata text configures original providers and transport" {
  let content = installed_effect_content_fixture(keep_content=true)
  let plan = installed_content_text_plan(content)
  assert_true(plan.values.max_text_bytes < 500000)
  assert_eq(
    plan.measurement.max_nodes,
    2 * plan.value_node_demand.unwrap().nodes,
  )
  assert_eq(plan.measurement.max_bytes, 500000)
  assert_eq(plan.measurement.max_depth, 100)
  assert_eq(plan.measurement.max_work, 20000000)

  assert_eq(
    plan.execution.rows.input_values.max_text_bytes,
    plan.values.max_text_bytes,
  )
  assert_eq(
    plan.execution.rows.output_values.max_text_bytes,
    plan.values.max_text_bytes,
  )
  assert_true(plan.imports.wire.max_bytes < 1000000)
  assert_true(plan.exports.wire.max_bytes < 1000000)
  assert_true(client_local_capacity_plan_matches(plan, plan.sequences, 100))
  let foreign = installed_effect_content_fixture(keep_content=true)
  assert_true(
    installed_content_text_bound(
      foreign,
      plan.sequences,
      plan.value_node_demand.unwrap(),
      500000,
    )
    is None,
  )
}

///|
test "metadata overwrite is not the original serializer text proof" {
  let content = installed_effect_content_fixture(
    keep_content=true,
    suffix=",{\"derive\":[{\"name\":\"media_type\"}],\"as\":\"altered\"}",
  )
  let owner = @lower.serialization_owner(content.component.barrier)
  assert_true(
    installed_content_schema_node_bound(content, owner, 10000) is None,
  )
}

///|
test "original multirow input retains its independent text and row demand" {
  let content = installed_effect_content_fixture(
    rows="[{\"id\":1},{\"id\":2},{\"id\":3}]",
    keep_content=true,
  )
  let plan = installed_content_text_plan(content)
  assert_eq(plan.execution.rows.max_rows, 3)
  assert_true(plan.values.max_text_bytes < 500000)
  assert_true(client_local_capacity_plan_matches(plan, plan.sequences, 100))
}
