///|
// Initial emitter has no field vector. Geometry H1/W9, Some/Ok H2/R2/W2,
// closed failure H3/R3/W3, one quote tuple+array H3/R5/W2, contract and
// wire-usage carriers H3/R7/W4, exported view/map entries H2/R7, and eight
// borrowed selected-field references plus the original scope-CID width
// reference. Hash identity text is distinct from
// its parsed final-body occurrence; all names/selected strings are borrowed.
fn initial_retention_control_capacity() -> @execution.ExecutionCapacity? {
  guard @encode.measuring_writer_construction_extent(9, 1) is Some(writer) else {
    return None
  }
  @execution.preparation_execution_capacity({
    retained: {
      record_headers: 14L,
      reference_slots: 33L,
      scalar_words: 20L,
      owned_utf16_units: 71L,
      owned_wire_bytes: 0L,
    },
    workspace: {
      record_headers: writer.record_headers + 1L,
      reference_slots: writer.reference_slots + 1L,
      scalar_words: writer.scalar_words + 7L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  })
}

///|
fn reserve_program_retention_capacity(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  capacity : @execution.ExecutionCapacity,
) -> Result[Unit, ClientClosedValuesPreparationIssue] {
  let holder = match managed_run_publication_body(owner, prepared) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let (r, e) = match
    @resources.preparation_body_borrow_reserved_extents(holder) {
    Ok(value) => value
    Err(issue) => return Err(Capacity(issue))
  }
  guard @execution.checked_preparation_add_product(
      r,
      @execution.execution_capacity_retained_bytes(capacity),
      1L,
    )
    is Some(next_r) &&
    @execution.checked_preparation_add_product(
      r,
      @execution.execution_capacity_execution_bytes(capacity),
      1L,
    )
    is Some(next_e) else {
    return Err(Policy)
  }
  match
    reserve_program_publication_phase(
      holder,
      prepared,
      next_r,
      Int64::max(e, next_e),
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard managed_run_publication_body(owner, prepared) is Ok(actual) &&
    physical_equal(actual, holder) else {
    return Err(ForeignOriginal)
  }
  Ok(())
}

///|
/// Initial retention DATA on the SAME PureManaged Program body. No clock/profile,
/// replacement admission, new owner or custody extension is selected here.
pub fn issue_program_initial_retention(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  retention_contract_cid : String,
  effective_data_policy_cid : String,
  available_until : String,
  delete_by : String,
  extension_ceiling_at : String,
  metadata_retention_policy_cid : String,
  metadata_delete_by : String,
  clock_contract_cid : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication.PublicationContract,
  ClientClosedValuesPreparationIssue,
] {
  if owner.source_free_opening {
    return Err(WrongPhase)
  }
  guard physical_equal(owner.request, request) else {
    return Err(ForeignOriginal)
  }
  let holder = match managed_run_publication_body(owner, prepared) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  if max_bytes < 1 || max_nodes < 1 || max_depth < 1 {
    return Err(PublicationRetention(@publication.InvalidLimits))
  }
  owner.source_free_opening = true
  defer {
    owner.source_free_opening = false
  }
  guard initial_retention_control_capacity() is Some(control) else {
    return Err(Policy)
  }
  // Fund measuring state and its failure/return carriers BEFORE measurement.
  match reserve_program_retention_capacity(owner, prepared, control) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let geometry = match
    @publication.initial_result_retention_construction_geometry(
      retention_contract_cid, effective_data_policy_cid, available_until, delete_by,
      extension_ceiling_at, metadata_retention_policy_cid, metadata_delete_by, clock_contract_cid,
      max_bytes, max_nodes, max_depth,
    ) {
    Err(issue) => return Err(PublicationRetention(issue))
    Ok(value) => value
  }
  // Existing shared codec/parser/hash inventories cover both preimage and
  // final self-CID body. Borrow the checked original Request scope CID for
  // WIDTH only, including when an untrusted selected field is malformed.
  // This never substitutes the Request identity for the issued policy CID.
  guard effect_unit_publication_capacity(
      [("result_retention_policy", geometry)],
      @publication_host.client_request_scope_cid(request),
    )
    is Some(body) else {
    return Err(Policy)
  }
  match reserve_program_retention_capacity(owner, prepared, body) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard managed_run_publication_body(owner, prepared) is Ok(current) &&
    physical_equal(current, holder) else {
    return Err(ForeignOriginal)
  }
  let issued = @publication.issue_initial_result_retention(
    retention_contract_cid, effective_data_policy_cid, available_until, delete_by,
    extension_ceiling_at, metadata_retention_policy_cid, metadata_delete_by, clock_contract_cid,
    max_bytes, max_nodes, max_depth,
  )
  guard managed_run_publication_body(owner, prepared) is Ok(current) &&
    physical_equal(current, holder) else {
    return Err(ForeignOriginal)
  }
  issued.map_err(issue => PublicationRetention(issue))
}

///|
/// Initial retention DATA on the SAME installed Effect Plan body. No clock/profile,
/// replacement admission, new owner or custody extension is selected here.
pub fn issue_installed_effect_initial_retention(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  plan : ClientInstalledEffectManagedPlan,
  retention_contract_cid : String,
  effective_data_policy_cid : String,
  available_until : String,
  delete_by : String,
  extension_ceiling_at : String,
  metadata_retention_policy_cid : String,
  metadata_delete_by : String,
  clock_contract_cid : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@publication.PublicationContract, ClientEffectUnitPreparationIssue] {
  if owner.effect_operation_opening || owner.effect_operation_closing {
    return Err(Run(AlreadyBound))
  }
  match check_installed_effect_managed_run_binding(owner, prepared, request) {
    Err(issue) => return Err(Run(issue))
    Ok(_) => ()
  }
  guard physical_equal(plan.prepared, prepared) else {
    return Err(Run(ForeignOriginal))
  }
  let holder = match effect_unit_publication_body(owner, plan, request) {
    Err(issue) => return Err(Run(issue))
    Ok(value) => value
  }
  if max_bytes < 1 || max_nodes < 1 || max_depth < 1 {
    return Err(Retention(@publication.InvalidLimits))
  }
  owner.effect_operation_opening = true
  defer {
    owner.effect_operation_opening = false
  }
  guard initial_retention_control_capacity() is Some(control) else {
    return Err(Run(InsufficientCapacity))
  }
  // Fund measuring state and its failure/return carriers BEFORE measurement.
  match
    reserve_effect_unit_publication_capacity(owner, plan, request, control) {
    Err(issue) => return Err(Run(issue))
    Ok(_) => ()
  }
  let geometry = match
    @publication.initial_result_retention_construction_geometry(
      retention_contract_cid, effective_data_policy_cid, available_until, delete_by,
      extension_ceiling_at, metadata_retention_policy_cid, metadata_delete_by, clock_contract_cid,
      max_bytes, max_nodes, max_depth,
    ) {
    Err(issue) => return Err(Retention(issue))
    Ok(value) => value
  }
  // Existing shared codec/parser/hash inventories cover both preimage and
  // final self-CID body. Borrow the checked original Request scope CID for
  // WIDTH only, including when an untrusted selected field is malformed.
  // This never substitutes the Request identity for the issued policy CID.
  guard effect_unit_publication_capacity(
      [("result_retention_policy", geometry)],
      @publication_host.client_request_scope_cid(request),
    )
    is Some(body) else {
    return Err(Run(InsufficientCapacity))
  }
  match reserve_effect_unit_publication_capacity(owner, plan, request, body) {
    Err(issue) => return Err(Run(issue))
    Ok(_) => ()
  }
  guard effect_unit_publication_body(owner, plan, request) is Ok(current) &&
    physical_equal(current, holder) else {
    return Err(Run(Retired))
  }
  let issued = @publication.issue_initial_result_retention(
    retention_contract_cid, effective_data_policy_cid, available_until, delete_by,
    extension_ceiling_at, metadata_retention_policy_cid, metadata_delete_by, clock_contract_cid,
    max_bytes, max_nodes, max_depth,
  )
  guard effect_unit_publication_body(owner, plan, request) is Ok(current) &&
    physical_equal(current, holder) else {
    return Err(Run(Retired))
  }
  issued.map_err(issue => Retention(issue))
}
