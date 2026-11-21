///|
/// The SAME Request funds its complete finite direct Query construction before
/// the Host builds declarations/capture vectors. Query issuer/shape and writer
/// inventories are the existing Model/Content-shared Query domain recipes;
/// this entry creates no Model, Source reader, Plan, Run or grant.
pub fn[I] admit_request_query_acquisition_contracts(
  owner : ClientRequestPreparation[I],
  input : I,
  query : String,
  evidence : String,
) -> Result[
  (
    @planning.QueryEvidenceContracts,
    @publication_host.ClientDirectAcquisitionOccurrences,
  ),
  ClientRequestProgramPlanIssue,
] {
  guard owner.phase == ProgramPlanReserved &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.program_capacity is Some(_) &&
    owner.compiled_program is Some(prepared) &&
    !owner.program_body_attempted else {
    return Err(Preparation(WrongPhase))
  }
  // The original Plan quote already funds the typed direct-occurrence selector.
  // There is no caller-supplied skip count or opaque occurrence reconstruction.
  let direct = match installed_direct_occurrences_owned(Pure(prepared)) {
    Err(issue) => return Err(Installed(issue))
    Ok(value) => value
  }
  admit_request_query_acquisition_contracts_for_original(
    owner, input, prepared, direct, query, evidence,
  )
}

///|
fn[I] admit_request_query_acquisition_contracts_for_original(
  owner : ClientRequestPreparation[I],
  input : I,
  prepared : @publication_host.PreparedClientProgram,
  direct : @publication_host.ClientDirectAcquisitionOccurrences,
  query : String,
  evidence : String,
) -> Result[
  (
    @planning.QueryEvidenceContracts,
    @publication_host.ClientDirectAcquisitionOccurrences,
  ),
  ClientRequestProgramPlanIssue,
] {
  // Both checked callers already selected this inventory under the SAME
  // working Request. Query still requires one exact occurrence for each
  // capture task; the Quote below checks this mapping before construction.
  guard request_query_acquisition_constructor_bytes(
      prepared, direct, query, evidence,
    )
    is Some(bytes) else {
    return Err(Preparation(Policy))
  }
  owner.phase = Selecting
  let reserved = reserve_request_domain_graph_construction(
    owner, input, prepared, bytes,
  )
  // A current callback may retire the original parent. Never revive it by
  // restoring a former phase after the checked grow refused that transition.
  if owner.phase == Selecting {
    owner.phase = ProgramPlanReserved
  }
  match reserved {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let contracts = match
    @row_source_host.admit_row_acquisition_contracts(query, evidence) {
    Err(issue) => return Err(ModelSource(issue))
    Ok(value) => value
  }
  owner.program_domain_quote = None
  Ok((contracts, direct))
}

///|
// Existing Query/Row recipes plus the exact caller frontier, before entry.
// This quantity never admits protocols or creates a Source/Run/permission.
fn request_query_acquisition_constructor_bytes(
  prepared : @publication_host.PreparedClientProgram,
  direct : @publication_host.ClientDirectAcquisitionOccurrences,
  query : String,
  evidence : String,
) -> Int64? {
  let count = @publication_host.client_direct_acquisition_occurrence_count(
    direct,
  )
  guard count > 0 &&
    count ==
    @strategy.graph_captured_prefix(
      @publication_host.prepared_client_graph(prepared),
    ) &&
    @row_source_host.row_acquisition_contracts_construction_capacity(
      query.length(),
      evidence.length(),
    )
    is Some(protocols) &&
    @execution.preparation_array_representation(5L, 5L * count.to_int64(), true)
    is Some(arrays) &&
    @execution.preparation_representation_cost(arrays) is Some(array_bytes) &&
    @execution.preparation_representation_cost({
      // Fixed quote/grow/refusal/return products. Per Source: declared-source,
      // capability/candidate/choice, evidence context and limits, capacity and
      // Host locator products. Borrowed schema/Program/Provider are not copied.
      record_headers: 12L + 64L * count.to_int64(),
      reference_slots: 8L + 128L * count.to_int64(),
      scalar_words: 20L + 128L * count.to_int64(),
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(controls) else {
    return None
  }
  let mut bytes = Int64::max(
    @execution.execution_capacity_retained_bytes(protocols),
    @execution.execution_capacity_execution_bytes(protocols),
  )
  for index in 0..<count {
    guard @publication_host.client_direct_acquisition_occurrence_at(
        direct, index,
      )
      is Some((stage, source, task)) &&
      task == index &&
      request_local_original_query_construction_bytes(prepared, stage, source)
      is Some(query_bytes) &&
      @execution.checked_preparation_add_product(bytes, query_bytes, 1L)
      is Some(next) else {
      return None
    }
    bytes = next
  }
  guard @execution.checked_preparation_add_product(bytes, array_bytes, 1L)
    is Some(bytes) &&
    @execution.checked_preparation_add_product(bytes, controls, 1L)
    is Some(bytes) else {
    return None
  }
  Some(bytes)
}
