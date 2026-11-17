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
/// The actual failed requirements phase, not a resource grant or a new
/// semantic verdict. Sequence preparation keeps its original typed refusal.
pub(all) enum ClientLocalRequirementsIssue {
  GraphShape
  ModelOccurrencesUnavailable
  ModelOccurrencesPresent
  SequencePreparation(ClientInstalledManagedRunIssue)
  SequenceCount
  MissingDataEdge
  InvalidDataEdge
  InputPortCountLimit
  CapacityQuoteUnavailable
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
/// Select demand for the managed Local runtime. Each actual provider, import
/// and output must still be admitted on the same finite original Ledger before
/// construction. A legacy whole-graph simultaneous quote is not a prerequisite.
pub fn prepare_source_free_runtime_requirements(
  prepared : @publication_host.PreparedClientProgram,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> ClientLocalRequirements? {
  prepare_source_free_runtime_requirements_result(
    prepared, installed_contracts, values_body, fragment_body, ordered_body,
  ).to_option()
}

///|
/// Same original checked graph/installed contracts and finite runtime demand.
/// This result retains why selection failed; it does not retry preparation,
/// enlarge a policy, infer a budget dimension, or issue execution authority.
pub fn prepare_source_free_runtime_requirements_result(
  prepared : @publication_host.PreparedClientProgram,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> Result[ClientLocalRequirements, ClientLocalRequirementsIssue] {
  prepare_local_requirements_result(
    prepared,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
    0,
    runtime_admission=true,
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
  runtime_admission? : Bool = false,
) -> ClientLocalRequirements? {
  prepare_local_requirements_result(
    prepared,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
    first,
    runtime_admission~,
  ).to_option()
}

///|
fn prepare_local_requirements_result(
  prepared : @publication_host.PreparedClientProgram,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  first : Int,
  runtime_admission? : Bool = false,
) -> Result[ClientLocalRequirements, ClientLocalRequirementsIssue] {
  let graph = @publication_host.prepared_client_graph(prepared)
  let count = @strategy.graph_task_count(graph)
  if @publication_host.prepared_client_acquisition_count(prepared) != first ||
    @publication_host.prepared_client_uses_graph_carrier(prepared) ||
    @strategy.graph_program_has_effects(graph) ||
    @strategy.graph_captured_prefix(graph) != first ||
    (first == 0 && !@strategy.graph_source_free_inputs_complete(graph)) ||
    count <= first {
    return Err(GraphShape)
  }
  // The legacy infer-execution selector takes a step of task zero, not a
  // task index. Inspect the original composed graph so later-stage Model
  // occurrences cannot be quoted as an ordinary Common suffix.
  let occurrences = match
    @publication_host.prepared_client_composed_infer_occurrences(prepared) {
    Some(original) => original
    None => return Err(ModelOccurrencesUnavailable)
  }
  if !occurrences.is_empty() {
    return Err(ModelOccurrencesPresent)
  }
  let sequences = match
    prepare_client_local_sequences_owned(
      Pure(prepared),
      installed_contracts,
      values_body,
      fragment_body,
      ordered_body,
    ) {
    Ok(original) => original
    Err(issue) => return Err(SequencePreparation(issue))
  }
  if sequences.length() != count {
    return Err(SequenceCount)
  }
  // Count ports, not distinct predecessor tasks: repeated edges retain their
  // own import and bridge workspace. Only Compute consumers are quoted here;
  // an external captured Source keeps its original acquisition owner.
  let inputs = Array::make(count - first, 0)
  for index in 0..<@strategy.graph_data_count(graph) {
    guard @strategy.graph_data_at(graph, index) is Some(edge) else {
      return Err(MissingDataEdge)
    }
    let producer = @strategy.data_edge_producer(edge)
    let consumer = @strategy.data_edge_consumer(edge)
    if producer < 0 || producer >= count || consumer < 0 || consumer >= count {
      return Err(InvalidDataEdge)
    }
    if consumer >= first && inputs[consumer - first] == 2147483647 {
      return Err(InputPortCountLimit)
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
  let capacity = match
    client_local_sequence_capacity_original(
      compute_sequences,
      count,
      capacity_plan=Some(capacity_plan),
      retained_inputs=Some(inputs),
      max_rows=@publication_host.prepared_client_values_max_rows(prepared),
      include_simultaneous=!runtime_admission,
      runtime_admission~,
      simultaneous_graph=Some(graph),
    ) {
    Some(original) => original
    None => return Err(CapacityQuoteUnavailable)
  }
  Ok({
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

///|
// Every nonterminal successful finalization poll must report positive work.
// The existing driver debits semantic steps from execution.max_work. After its
// receipt transfers, mandatory scratch retirement is separate: two admitted
// row/cell arrays, one reference-row/cell array, at most one reference per
// admitted value node, three column arrays and two closing transitions.
// This is a finite scheduling bound, never additional fuel, memory or authority.
fn local_finalization_round_bound(
  work : Int,
  rows : Int,
  fields : Int,
  nodes : Int,
) -> Int? {
  if work < 0 || rows < 0 || fields < 0 || nodes < 0 {
    return None
  }
  // The poll index is Int, but these conservative roles can overestimate a
  // small actual output. Saturate only this scheduling counter; never reject
  // an otherwise admissible task or change its separate work/size quotas.
  guard @execution.checked_preparation_add_product(
      3L,
      rows.to_int64(),
      3L * (fields.to_int64() + 1L),
    )
    is Some(bound) &&
    @execution.checked_preparation_add_product(bound, fields.to_int64(), 3L)
    is Some(bound) &&
    @execution.checked_preparation_add_product(bound, nodes.to_int64(), 1L)
    is Some(bound) &&
    @execution.checked_preparation_add_product(bound, work.to_int64(), 1L)
    is Some(bound) else {
    return Some(2147483647)
  }
  Some(Int64::min(bound, 2147483647L).to_int())
}

///|
/// Poll the same already-quoted task through finalization and its finite
/// scratch retirement. This metadata neither supplies its Ledger nor raises
/// the unchanged execution work or output admission limits.
pub fn ClientLocalRequirements::finalization_round_limit(
  self : ClientLocalRequirements,
  prepared : @publication_host.PreparedClientProgram,
) -> Int? {
  if !physical_equal(self.prepared, prepared) {
    return None
  }
  let plan = self.capacity_plan
  local_finalization_round_bound(
    plan.execution.max_work,
    plan.execution.rows.max_rows,
    plan.imports.wire.max_columns,
    plan.execution.rows.output_values.max_nodes,
  )
}
