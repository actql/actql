///|
/// Fixed conformance Host, not a general native query compiler.
struct ManagedTakeFixture {
  owner : @lower.BoundPrepared
  input : @execution.ManagedProducerRead[Int]
  values : @execution.ManagedOutputValues
  selection : @execution.ManagedViewSelection[Int]
  completion : @execution.ManagedCompletionPort[
    (
      @execution.ManagedOutputValueReceipt,
      @execution.ManagedRetainedOutput[Int],
    ),
    Int,
  ]
}

///|
#export_name("managedTakeFixture")
pub fn managed_take_fixture(
  source : OwnedFixedFixture,
  output : @execution.ManagedCompletedOutput[Int],
  profile : @execution.ManagedExecutionProfile,
  registry : String,
  values_contract : String,
  fragment : String,
  verify : () -> Bool,
) -> ManagedTakeFixture raise {
  let producer = @duckdb.fixed_query_owner(
    @duckdb.fixed_compute_query(source.compute),
  )
  let owner = issued_fixture_consumer(
    producer,
    steps="[{\"take\":2},{\"select\":[\"amount\"]}]",
    target=@duckdb.fixed_query_target(
      @duckdb.fixed_compute_query(source.compute),
    ),
  )
  let input = @execution.prepare_managed_producer_read(
    owner, 0, producer, output, 100, 10000,
  ).unwrap()
  let kernels = Array::makei(2, i => {
    @lower.prepare_kernel(owner, i, max_bindings=100, max_name_bytes=1000, {
      max_nodes: 100,
      max_work: 1000,
      max_depth: 100,
      max_literal_nodes: 100,
      max_literal_text_bytes: 1000,
    }).unwrap()
  })
  let plan = @execution.prepare_managed_view_plan(
    input, kernels, 1000, 10000, 100,
  ).unwrap()
  let rows = Int::min(2, @execution.managed_producer_read_row_count(input))
  let selection = @execution.prepare_managed_view_selection(
    plan,
    Array::makei(rows, i => i),
    100,
    1000,
  ).unwrap()
  let measured = @execution.prepare_reused_managed_producer_measurement(
    [input],
    Step(1),
    max_rows=100,
    max_value_bytes=10000,
    { max_work: 10000, max_bytes: 10000, max_nodes: 1000, max_depth: 100, },
    1000,
  ).unwrap()
  let values = @execution.prepare_reused_managed_output_values(measured, {
    max_work: 10000,
    max_nodes: 1000,
    max_text_bytes: 10000,
    max_depth: 100,
  }).unwrap()
  let generated = fixture_generated(
    owner, registry, values_contract, fragment, false,
  )
  let completion = @execution.prepare_managed_completion_port(
    profile,
    @execution.generated_completion_preparation(generated),
    Step(1),
    1000,
    10000,
    (
      proof : (
        @execution.ManagedOutputValueReceipt,
        @execution.ManagedRetainedOutput[Int],
      ),
    ) => {
      let (receipt, material) = proof
      if !verify() ||
        !@execution.managed_output_value_managed_measurement_matches(
          receipt, measured,
        ) ||
        !@execution.managed_retained_output_matches(material, receipt) {
        None
      } else {
        Some(material)
      }
    },
    managed_inputs=[input],
  ).unwrap()
  { owner, input, values, selection, completion, }
}

///|
#export_name("managedTakeInput")
pub fn managed_take_input(
  value : ManagedTakeFixture,
) -> @execution.ManagedProducerRead[Int] {
  value.input
}

///|
#export_name("managedTakeOccurrence")
pub fn managed_take_occurrence(value : ManagedTakeFixture, row : Int) -> Int {
  @execution.managed_view_selection_row(value.selection, row).unwrap()
}

///|
#export_name("managedTakeValues")
pub fn managed_take_values(
  value : ManagedTakeFixture,
) -> @execution.ManagedOutputValues {
  value.values
}

///|
#export_name("managedTakeSelection")
pub fn managed_take_selection(
  value : ManagedTakeFixture,
) -> @execution.ManagedViewSelection[Int] {
  value.selection
}

///|
#export_name("managedTakeCompletion")
pub fn managed_take_completion(
  value : ManagedTakeFixture,
) -> @execution.ManagedCompletionPort[
  (@execution.ManagedOutputValueReceipt, @execution.ManagedRetainedOutput[Int]),
  Int,
] {
  value.completion
}

///|
#export_name("managedTakeNextInput")
pub fn managed_take_next_input(
  value : ManagedTakeFixture,
  output : @execution.ManagedCompletedOutput[Int],
) -> @execution.ManagedProducerRead[Int] {
  let receiver = issued_fixture_consumer(
    value.owner,
    steps="[{\"select\":[\"amount\"]}]",
    target=Step(1),
  )
  @execution.prepare_managed_producer_read(
    receiver,
    0,
    value.owner,
    output,
    100,
    10000,
  ).unwrap()
}

///|
#export_name("managedTakeNextIndexFacts")
pub fn managed_take_next_index_facts(
  input : @execution.ManagedProducerRead[Int],
) -> Array[Int] {
  let owner = @execution.managed_producer_read_receiver(input)
  let kernel = @lower.prepare_kernel(
    owner,
    0,
    max_bindings=100,
    max_name_bytes=1000,
    {
      max_nodes: 100,
      max_work: 1000,
      max_depth: 100,
      max_literal_nodes: 100,
      max_literal_text_bytes: 1000,
    },
  ).unwrap()
  let plan = @execution.prepare_managed_view_plan(
    input,
    [kernel],
    1000,
    10000,
    100,
  ).unwrap()
  let rows = Array::makei(@execution.managed_producer_read_row_count(input), i => {
    return i
  })
  let facts = @execution.managed_view_selection_measurements(plan, rows, 1000).unwrap()[0].unwrap()
  [facts.rows, facts.bytes, facts.nodes, facts.max_value_bytes, facts.null_rows]
}
