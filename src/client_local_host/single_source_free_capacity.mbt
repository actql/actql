///|
// Pure checked-plan data. This retains no Host, Account decision, Ledger or
// physical allocation and cannot issue any of those originals.
struct ClientLocalSourceFreeRequirements {
  prepared : @publication_host.PreparedClientProgram
  registry : ClientInstalledSequenceContracts
  values : String
  fragment : String?
  ordered : String?
  sequences : Array[@execution.GeneratedSequence]
  capacity_plan : ClientLocalCapacityPlan
  capacity : ClientLocalSequenceCapacity
}

///|
/// Quote the checked graph's simultaneous reservations separately from the
/// existing maximum admission limits. A conservative requirement above those
/// maxima is not a claim that a smaller finite facility will satisfy it.
pub fn prepare_source_free_local_requirements(
  prepared : @publication_host.PreparedClientProgram,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> ClientLocalSourceFreeRequirements? {
  let graph = @publication_host.prepared_client_graph(prepared)
  let count = @strategy.graph_task_count(graph)
  if @publication_host.prepared_client_acquisition_count(prepared) != 0 ||
    @publication_host.prepared_client_uses_graph_carrier(prepared) ||
    @strategy.graph_program_has_effects(graph) ||
    !@strategy.graph_source_free_inputs_complete(graph) ||
    count < 1 {
    return None
  }
  for task in 0..<count {
    if @publication_host.prepared_client_infer_execution_occurrence(
        prepared, task,
      )
      is Some(_) {
      return None
    }
  }
  guard prepare_client_local_sequences(
      prepared, installed_contracts, values_body, fragment_body, ordered_body,
    )
    is Some(sequences) &&
    sequences.length() == count else {
    return None
  }
  // Count ports, not distinct predecessor tasks: repeated edges retain their
  // own import and bridge workspace. Captures and supplied inputs were refused
  // above, so no external Source can become a source-free allowance.
  let inputs = Array::make(count, 0)
  for index in 0..<@strategy.graph_data_count(graph) {
    guard @strategy.graph_data_at(graph, index) is Some(edge) else {
      return None
    }
    let producer = @strategy.data_edge_producer(edge)
    let consumer = @strategy.data_edge_consumer(edge)
    if producer < 0 ||
      producer >= count ||
      consumer < 0 ||
      consumer >= count ||
      inputs[consumer] == 2147483647 {
      return None
    }
    inputs[consumer] += 1
  }
  let capacity_plan = client_local_capacity_plan(
    sequences,
    @publication_host.prepared_client_values_max_rows(prepared),
    scalar_values=true,
    graph=Some(graph),
  )
  client_local_sequence_capacity_original(
    sequences,
    count,
    capacity_plan=Some(capacity_plan),
    retained_inputs=Some(inputs),
    max_rows=@publication_host.prepared_client_values_max_rows(prepared),
    include_simultaneous=true,
    simultaneous_graph=Some(graph),
  ).map(capacity => {
    prepared,
    registry: installed_contracts,
    values: values_body,
    fragment: fragment_body,
    ordered: ordered_body,
    sequences,
    capacity_plan,
    capacity,
  })
}

///|
pub fn ClientLocalSourceFreeRequirements::maximum_limits(
  self : ClientLocalSourceFreeRequirements,
) -> @resources.LedgerLimits {
  self.capacity.limits
}

///|
pub fn ClientLocalSourceFreeRequirements::simultaneous_limits(
  self : ClientLocalSourceFreeRequirements,
) -> @resources.LedgerLimits? {
  self.capacity.simultaneous.map(value => {
    let (retained, execution) = value
    {
      ..self.capacity.limits,
      retained_bytes: retained,
      execution_bytes: execution,
    }
  })
}

///|
/// Exact immutable preparation and installed inputs only. This comparison
/// supplies no current authorization, execution or physical capacity.
pub fn ClientLocalSourceFreeRequirements::matches(
  self : ClientLocalSourceFreeRequirements,
  prepared : @publication_host.PreparedClientProgram,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> Bool {
  physical_equal(self.prepared, prepared) &&
  physical_equal(self.registry, installed_contracts) &&
  self.values == values_body &&
  self.fragment == fragment_body &&
  self.ordered == ordered_body
}
