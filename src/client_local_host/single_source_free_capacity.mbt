///|
// Pure checked-plan data. This retains no Host, Account decision, Ledger or
// physical allocation and cannot issue any of those originals.
struct ClientLocalRequirements {
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
) -> ClientLocalRequirements? {
  prepare_local_requirements(
    prepared, installed_contracts, values_body, fragment_body, ordered_body, 0,
  )
}

///|
/// Retain the exact single captured-Source Compute tail. The Source acquisition
/// and its physical backing remain borrowed from their existing Owner.
/// The simultaneous quote includes only this Compute suffix; it must be
/// composed with the Source owner's actual live footprint before admission.
pub fn prepare_captured_local_requirements(
  prepared : @publication_host.PreparedClientProgram,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> ClientLocalRequirements? {
  prepare_local_requirements(
    prepared, installed_contracts, values_body, fragment_body, ordered_body, 1,
  )
}

///|
fn prepare_local_requirements(
  prepared : @publication_host.PreparedClientProgram,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  first : Int,
) -> ClientLocalRequirements? {
  let graph = @publication_host.prepared_client_graph(prepared)
  let count = @strategy.graph_task_count(graph)
  if @publication_host.prepared_client_acquisition_count(prepared) != first ||
    @publication_host.prepared_client_uses_graph_carrier(prepared) ||
    @strategy.graph_program_has_effects(graph) ||
    @strategy.graph_captured_prefix(graph) != first ||
    (first == 0 && !@strategy.graph_source_free_inputs_complete(graph)) ||
    count <= first {
    return None
  }
  // The legacy infer-execution selector takes a step of task zero, not a
  // task index. Inspect the original composed graph so later-stage Model
  // occurrences cannot be quoted as an ordinary Common suffix.
  guard @publication_host.prepared_client_composed_infer_occurrences(prepared)
    is Some(occurrences) &&
    occurrences.is_empty() else {
    return None
  }
  guard prepare_client_local_sequences(
      prepared, installed_contracts, values_body, fragment_body, ordered_body,
    )
    is Some(sequences) &&
    sequences.length() == count else {
    return None
  }
  // Count ports, not distinct predecessor tasks: repeated edges retain their
  // own import and bridge workspace. Only Compute consumers are quoted here;
  // an external captured Source keeps its original acquisition owner.
  let inputs = Array::make(count - first, 0)
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
      (consumer >= first && inputs[consumer - first] == 2147483647) {
      return None
    }
    if consumer >= first {
      inputs[consumer - first] += 1
    }
  }
  let compute_sequences = if first == 0 {
    sequences
  } else {
    Array::makei(count - first, index => sequences[index + first])
  }
  let capacity_plan = client_local_capacity_plan(
    compute_sequences,
    @publication_host.prepared_client_values_max_rows(prepared),
    scalar_values=first == 0,
    graph=Some(graph),
    graph_offset=first,
  )
  client_local_sequence_capacity_original(
    compute_sequences,
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
pub fn ClientLocalRequirements::maximum_limits(
  self : ClientLocalRequirements,
) -> @resources.LedgerLimits {
  self.capacity.limits
}

///|
pub fn ClientLocalRequirements::simultaneous_limits(
  self : ClientLocalRequirements,
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
pub fn ClientLocalRequirements::matches(
  self : ClientLocalRequirements,
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
