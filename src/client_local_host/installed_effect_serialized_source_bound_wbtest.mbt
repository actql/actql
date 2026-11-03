///|
test "serialized Effect endpoints do not multiply file operations by their input sort rows" {
  let input = Array::make(100, "{\"id\":1}").join(",")
  let content = installed_effect_content_fixture(rows="[" + input + "]")
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let request = @publication_host.prepare_client_effect_request_identity(
    content.prepared,
    "sha256:" + "a".repeat(64),
    "one-store",
    "sha256:" + "b".repeat(64),
  ).unwrap()
  let extent = prepare_installed_effect_operation_extent(
    "files.write",
    @execution.execution_capacity(1L, 1L).unwrap(),
    17L,
    true,
  ).unwrap()
  let demand = prepare_installed_effect_operation_demand(
    content.prepared,
    0,
    "save",
    [],
    [extent],
  ).unwrap()
  let plan = prepare_installed_effect_managed_plan(
    content.prepared,
    request,
    [],
    "",
    "",
    [],
    [],
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    [demand],
    content=Some(content),
    provider_factory=_ => [],
  ).unwrap()
  assert_eq(plan.capacity_plan.demand_inventory.unwrap().closed_rows, Some(100))
  assert_eq(plan.rows, 1)
  assert_eq(
    plan.limits.transfer_bytes - plan._observed_compute_limits.transfer_bytes,
    17L,
  )
  assert_eq(plan.limits.attempts - plan._observed_compute_limits.attempts, 1)
}
