///|
// One actual rebind operation, before the measuring Writer or its result.
// Geometry:1H9W; its Some/Ok:2H2R2W; closed failure forwarding at most
//3H3R3W. Payload tags are included, not erased as VM implementation detail.
fn installed_effect_retention_control_capacity() -> @execution.ExecutionCapacity? {
  guard @encode.measuring_writer_construction_extent(9, 1) is Some(writer) &&
    @execution.preparation_array_representation(1L, 9L, false) is Some(fields) else {
    return None
  }
  @execution.preparation_execution_capacity({
    retained: {
      // The same fixed nine-name field vector is live in either emitter pass.
      // Keep its existing fixed-array backing through the body writer too.
      record_headers: 6L + fields.record_headers,
      reference_slots: 5L + fields.reference_slots,
      scalar_words: 14L + fields.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
    workspace: {
      // The existing measuring inventory includes sink/frame/finish storage.
      // GeometryOutput adds its six-word state and tagged payload reference.
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
/// Rebind only the contributing Source policy on the SAME admitted retention.
/// The existing installed Plan holder owns construction and failed prefixes;
/// no retention extension, permission, replacement Request or Ledger is issued.
pub fn rebind_installed_effect_result_retention(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  plan : ClientInstalledEffectManagedPlan,
  original : @publication.PublicationContract,
  policy : String,
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
  guard physical_equal(plan.prepared, prepared) &&
    effect_unit_publication_body(owner, plan, request) is Ok(holder) else {
    return Err(Run(ForeignOriginal))
  }
  if max_bytes < 1 || max_nodes < 1 || max_depth < 1 {
    return Err(Retention(@publication.InvalidLimits))
  }
  owner.effect_operation_opening = true
  defer {
    owner.effect_operation_opening = false
  }
  guard installed_effect_retention_control_capacity() is Some(control) else {
    return Err(Run(InsufficientCapacity))
  }
  // This grow observes the original Resource currentness and then rechecks
  // the SAME holder. Its charged prefix survives a later refused body grow.
  match
    reserve_effect_unit_publication_capacity(owner, plan, request, control) {
    Err(issue) => return Err(Run(issue))
    Ok(_) => ()
  }
  let geometry = match
    @publication.result_retention_policy_construction_geometry(
      original, policy, max_bytes, max_nodes, max_depth,
    ) {
    Err(issue) => return Err(Retention(issue))
    Ok(value) => value
  }
  if geometry is Some(body) {
    match
      reserve_installed_effect_keyed_encoding(
        owner,
        plan,
        request,
        @publication.publication_contract_identity(original),
        "result_retention_policy",
        body,
      ) {
      Err(issue) => return Err(Run(issue))
      Ok(_) => ()
    }
  }
  guard effect_unit_publication_body(owner, plan, request) is Ok(current) &&
    physical_equal(current, holder) else {
    return Err(Run(Retired))
  }
  let issued = @publication.issue_result_retention_for_data_policy(
    original, policy, max_bytes, max_nodes, max_depth,
  )
  guard effect_unit_publication_body(owner, plan, request) is Ok(current) &&
    physical_equal(current, holder) else {
    return Err(Run(Retired))
  }
  issued.map_err(issue => Retention(issue))
}
