///|
// An installed explicit profile, original Map and three issued records can
// coexist until admission returns. The already funded Map is borrowed.
fn installed_sample_issuance_capacity(
  output_count : Int,
  reference_units : Int,
  profile_units : Int,
  namespace_bytes : Int,
) -> Int64? {
  let bytes = Int::max(
    1024 + 74 * output_count,
    Int::max(3 * reference_units + 1024, 3 * profile_units + 1024),
  )
  let bytes = Int::max(bytes, namespace_bytes + 1024)
  let nodes = Int::max(128, output_count + 32)
  let depth = 12
  guard @publication.run_evidence_admission_construction_inventory(
      bytes, nodes, depth,
    )
    is Some(codec) &&
    @encode.text_writer_construction_inventory(bytes, nodes, depth)
    is Some(writer) else {
    return None
  }
  @execution.preparation_representation_cost({
    record_headers: 5L * codec.record_headers +
    2L * writer.record_headers +
    128L,
    reference_slots: 5L * codec.reference_slots +
    2L * writer.reference_slots +
    160L,
    scalar_words: 5L * codec.scalar_words + 2L * writer.scalar_words + 160L,
    owned_utf16_units: 5L * codec.owned_utf16_units +
    2L * writer.owned_utf16_units +
    3L * bytes.to_int64(),
    owned_wire_bytes: 5L * codec.owned_wire_bytes,
  })
}

///|
/// The authenticated Journal view passes the exact original reference wire.
/// The installed policy supplies a canonical explicit Profile. This method
/// issues and checks its original-bound records on the same prepared Run.
pub fn issue_installed_relation_sample_profile_journal_reference(
  owner : ClientInstalledManagedRun,
  request : @publication_host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  observation : ClientLogicalObservation,
  reference_wire : String,
  profile_wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  ClientCheckedRelationSampleProfile,
  InstalledRelationSampleProfileIssue,
] {
  if owner.source_free_opening || observation.reading {
    return Err(SampleProfileBusy)
  }
  guard observation.cleanup.original is Some((run, prepared, compiled)) &&
    observation.original is Some(original) &&
    physical_equal(run, owner) &&
    owner.source_free_captured is Some(captured) &&
    installed_relation_sample_start_matches(
      owner, prepared, request, compiled, definition, captured,
    ) &&
    @publication.run_definition_namespace(definition) is Some(namespace_id) else {
    return Err(ForeignSampleProfile)
  }
  let namespace_bytes = 6L * namespace_id.length().to_int64()
  if namespace_bytes > 130048L ||
    reference_wire.length() > 4096 ||
    profile_wire.length() > 4096 ||
    max_bytes <= 0 ||
    max_nodes <= 0 ||
    max_depth <= 0 {
    return Err(SampleProfileLimits)
  }
  owner.source_free_opening = true
  observation.reading = true
  defer {
    observation.reading = false
    owner.source_free_opening = false
  }
  let holder = observation.cleanup.holder
  let ledger = @strategy.captured_dag_ledger(captured)
  let depth = Int::min(max_depth, 64)
  let map = original.sealed_map
  guard @publication.run_evidence_value_fits(map, max_bytes, max_nodes, depth) &&
    @publication.run_evidence_value_wire_usage(map) is Some((_, nodes, _)) &&
    @identity.object_field(original.map, "steps")
    is Some(@identity.Array(steps)) else {
    return Err(SampleProfileLimits)
  }
  // The compiler creates exactly one output on each original Map step.
  // Quote the closed profile and three records before scanning their input.
  let output_count = @identity.array_count(steps)
  if output_count > (131072 - 1024) / 74 {
    return Err(SampleProfileLimits)
  }
  guard installed_sample_issuance_capacity(
      output_count,
      reference_wire.length(),
      profile_wire.length(),
      namespace_bytes.to_int(),
    )
    is Some(charge) else {
    return Err(SampleProfileLimits)
  }
  match grow_installed_sample_profile_binding(holder, prepared, charge) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  // Retain the exact compiler seal and cached geometry. The output scan is
  // still charged, and the independent binder checks original port keys.
  match
    @resources.charge_planning(
      ledger,
      reference_wire.length() + profile_wire.length(),
    ) {
    Err(issue) => return Err(SampleProfileWork(issue))
    Ok(_) => ()
  }
  guard installed_sample_profile_binding_current(
    observation, holder, prepared, compiled, captured,
  ) else {
    return Err(ForeignSampleProfile)
  }
  guard @scalar.admit_utf8_length(reference_wire, 4096) is Ok(reference_bytes) &&
    @scalar.admit_utf8_length(profile_wire, 4096) is Ok(profile_bytes) else {
    return Err(SampleProfileLimits)
  }
  let work = nodes +
    8 *
    (
      reference_bytes +
      profile_bytes +
      namespace_bytes.to_int() +
      1810 +
      74 * output_count
    )
  match @resources.charge_planning(ledger, work) {
    Err(issue) => return Err(SampleProfileWork(issue))
    Ok(_) => ()
  }
  guard installed_sample_profile_binding_current(
    observation, holder, prepared, compiled, captured,
  ) else {
    return Err(ForeignSampleProfile)
  }
  let profile = match
    @publication.admit_run_evidence_value(
      "control_profile",
      profile_wire,
      Int::min(max_bytes, 12288),
      Int::min(max_nodes, 128),
      Int::min(depth, 12),
    ) {
    Err(issue) => return Err(SampleProfileBinding(issue))
    Ok(value) => value
  }
  let (intent, resolved, admission) = match
    @publication.issue_interactive_relation_sample_admission(
      definition,
      @publication_host.client_compiled_run_plan(compiled),
      @publication_host.client_compiled_run_prepared(compiled),
      @publication_host.client_compiled_run_authorization(compiled),
      profile,
      map,
      reference_wire,
      @publication_host.client_request_intent_cid(request),
      @publication_host.client_request_authority_scope_cid(request),
      max_bytes,
      max_nodes,
      depth,
    ) {
    Err(issue) => return Err(SampleProfileBinding(issue))
    Ok(value) => value
  }
  check_installed_relation_sample_profile_original(
    request,
    definition,
    observation,
    prepared,
    compiled,
    captured,
    reference_wire,
    {
      intent,
      requested: profile,
      effective: profile,
      resolved,
      map,
      admission,
    },
    max_bytes,
    max_nodes,
    depth,
    decode_original=true,
    use_exact_map_nodes=true,
  )
}
