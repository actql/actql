///|
/// Test-only preparation of the existing unselected constructor/Subgraph
/// provider. Public Program planning can split these into selected tasks; that
/// route must not stand in for this provider's stored-input entrypoint.
struct SubgraphCancelFixture {
  execution : @local_connector.ManagedProviderExecution
  input : @execution.ProducerRead
}

///|
#export_name("subgraphCancelCreate")
pub fn subgraph_cancel_create(
  source : String,
  steps : String,
  registry_json : String,
  values_json : String,
  fragment_json : String,
) -> SubgraphCancelFixture raise {
  let checked = @pipeline.check(cursor(source), [], None, None, {
    max_steps: 10,
    max_work: 100000,
    max_text_bytes: 100000,
    max_nodes: 10000,
    max_tokens: 10000,
    max_depth: 100,
  }).unwrap()
  let owner = @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 1000,
      max_references: 1000,
      max_work: 100000,
      max_identifier_bytes: 10000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  let completed = @execution.execute_generated_sequence(
    fixture_generated(owner, registry_json, values_json, fragment_json, false),
    [],
    issued_execution_limits(100),
  ).unwrap()
  let output = @execution.completed_output(completed, Step(0)).unwrap()
  let consumer = issued_fixture_consumer(owner, steps~, target=Step(0))
  let generated = fixture_generated(
    consumer, registry_json, values_json, fragment_json, false,
  )
  assert_eq(
    @execution.completion_preparation_selected_step(
      @execution.generated_completion_preparation(generated),
    ),
    None,
  )
  assert_eq(@execution.generated_sequence_step_count(generated), 2)
  let bound = @execution.bind_completed_input(consumer, 0, owner, output).unwrap()
  let input = @execution.prepare_producer_read(consumer, bound, 100, 10000).unwrap()
  let provider = @local_sga_provider.provider(
    {
      max_input_rows: 100,
      max_nodes: 100,
      max_edges: 100,
      max_value_bytes: 1000,
      max_total_value_bytes: 10000,
      max_retained_value_bytes: 10000,
      max_value_nodes: 100,
      max_value_depth: 10,
      max_contract_work: 10000,
      max_work: 100000,
      max_workspace_slots: 10000,
    },
    1000000L,
    @execution.generated_sequence_capacity(
      generated,
      issued_execution_limits(100),
      { max_work: 100000, max_bytes: 100000, max_nodes: 10000, max_depth: 100, },
    ).unwrap(),
  )
  assert_true(@local_connector.managed_provider_accepts(provider, generated))
  let execution = @local_connector.start_managed_provider(
    provider,
    generated,
    [input],
    100,
    1000,
  ).unwrap()
  { execution, input, }
}

///|
#export_name("subgraphCancelAdvance")
pub fn subgraph_cancel_advance(f : SubgraphCancelFixture) -> Array[Int64] {
  match @local_connector.advance_managed_provider(f.execution, 1).unwrap() {
    @local_connector.Continue(progress~, work~) => [0L, progress, work]
    @local_connector.Stopped(progress~, work~) => [1L, progress, work]
    _ => abort("unexpected fused Subgraph completion or failure")
  }
}

///|
#export_name("subgraphCancelRequest")
pub fn subgraph_cancel_request(f : SubgraphCancelFixture) -> Bool {
  @local_connector.cancel_managed_provider(f.execution)
}

///|
#export_name("subgraphCancelStopped")
pub fn subgraph_cancel_stopped(f : SubgraphCancelFixture) -> Bool {
  @local_connector.managed_provider_stopped(f.execution)
}

///|
#export_name("subgraphCancelCleanup")
pub fn subgraph_cancel_cleanup(f : SubgraphCancelFixture) -> Bool {
  @local_connector.cleanup_managed_provider(f.execution).unwrap()
}

///|
#export_name("subgraphCancelInputAvailable")
pub fn subgraph_cancel_input_available(f : SubgraphCancelFixture) -> Bool {
  @execution.producer_read_available(f.input)
}
