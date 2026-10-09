///|
test "Effect retained projection preserves the admitted closure and ordinary refusal" {
  let materials = effect_source_restored_materials(
    effect_source_dispatch_fixture(),
  )
  let bound = @host.bind_client_effect_compiled_run(
    materials.prepared,
    materials.allowed,
    materials.run_definition,
  ).unwrap()
  let checked = @host.prepared_client_effect_run_graph(bound)
  assert_true(
    @strategy.prepare_retained_task_projection(
      @strategy.checked_effect_run_graph(checked),
      1,
    )
    is Err(UnsupportedGraph),
  )
  let projection = @strategy.prepare_retained_effect_task_projection(checked).unwrap()
  assert_eq(@strategy.retained_task_projection_producer(projection), 0)
  assert_eq(@strategy.retained_task_projection_consumer(projection), 1)
  let edge = @host.prepare_client_effect_retained_input_edge(
    materials.allowed,
    materials.run_definition,
  ).unwrap()
  assert_eq(
    @host.client_retained_input_edge_projection(edge)[0],
    @publication.publication_contract_identity(materials.run_definition),
  )
}
