///|
// Canonical before-Step object with a checked CID, including its separator.
let installed_sample_resolved_breakpoint_wire_bytes = 128

///|
// An installed explicit profile, original Map and three issued records can
// coexist until the installed start receives the checked originals.
// The already funded Map is borrowed.
fn installed_sample_issuance_capacity(
  output_count : Int,
  reference_units : Int,
  profile_units : Int,
  namespace_bytes : Int,
  breakpoint_slots? : Int = 0,
  constructing_profile? : Bool = false,
) -> Int64? {
  let bytes = Int::max(
    1024 +
    74 * output_count +
    installed_sample_resolved_breakpoint_wire_bytes * breakpoint_slots,
    Int::max(3 * reference_units + 1024, 3 * profile_units + 1024),
  )
  let bytes = Int::max(bytes, namespace_bytes + 1024)
  let profile_nodes = if constructing_profile { 128 + 7 * breakpoint_slots } else { 128 }
  let nodes = Int::max(profile_nodes, output_count + 32 + 4 * breakpoint_slots)
  let depth = 12
  guard @publication.run_evidence_admission_construction_inventory(
      bytes, nodes, depth,
    )
    is Some(codec) &&
    @encode.text_writer_construction_inventory(bytes, nodes, depth)
    is Some(writer) else {
    return None
  }
  // Marked issuance borrows the admitted policy while materializing the
  // exact selectors and sealing its replacement. Its extra frames can
  // coexist with the existing resolved-profile and admission quote.
  let codecs = if constructing_profile { 7L } else { 5L }
  let writers = if constructing_profile { 3L } else { 2L }
  @execution.preparation_representation_cost({
    record_headers: codecs * codec.record_headers +
    writers * writer.record_headers +
    130L +
    3L * breakpoint_slots.to_int64(),
    reference_slots: codecs * codec.reference_slots +
    writers * writer.reference_slots +
    167L +
    5L * breakpoint_slots.to_int64(),
    scalar_words: codecs * codec.scalar_words +
    writers * writer.scalar_words +
    160L +
    3L * breakpoint_slots.to_int64(),
    owned_utf16_units: codecs * codec.owned_utf16_units +
    writers * writer.owned_utf16_units +
    3L * bytes.to_int64(),
    owned_wire_bytes: codecs * codec.owned_wire_bytes,
  })
}

///|
fn reserve_installed_sample_start_proof_copies(
  holder : @resources.PreparationBodyBorrow[
    @publication_host.PreparedClientProgram,
  ],
  prepared : @publication_host.PreparedClientProgram,
  intent : @publication.RunEvidenceValue,
  resolved : @publication.RunEvidenceValue,
  admission : @publication.RunEvidenceValue,
  profile : @publication.RunEvidenceValue,
) -> Result[Unit, InstalledRelationSampleProfileIssue] {
  guard @publication.run_evidence_value_wire_usage(intent)
    is Some((intent_bytes, _, _)) &&
    @publication.run_evidence_value_wire_usage(resolved)
    is Some((resolved_bytes, _, _)) &&
    @publication.run_evidence_value_wire_usage(admission)
    is Some((admission_bytes, _, _)) &&
    @publication.run_evidence_value_wire_usage(profile)
    is Some((profile_bytes, _, _)) else {
    return Err(SampleProfileLimits)
  }
  let bytes = intent_bytes.to_int64() +
    resolved_bytes.to_int64() +
    admission_bytes.to_int64() +
    profile_bytes.to_int64()
  // The issuer already owns each canonical wire. These extents cover the
  // outbound encoding, native bind copies and transient SQLite row assembly.
  // Reopening the persisted evidence has its own funded decode.
  guard @execution.checked_preparation_add_product(0L, bytes, 4L)
    is Some(copies) else {
    return Err(SampleProfileLimits)
  }
  grow_installed_sample_profile_binding(holder, prepared, copies)
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
  expected_breakpoint_map_cid? : String,
  submitted_breakpoints? : @publication_host.ClientSubmittedIntent,
) -> Result[
  (ClientCheckedRelationSampleProfile, String, String, String, String),
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
  let map_cid = @publication.run_evidence_value_identity(map)
  let (profile_map, breakpoint_slots, profile_units) = match submitted_breakpoints {
    Some(intent) => {
      let count = @publication_host.client_submitted_intent_entry_breakpoint_count(intent)
      guard expected_breakpoint_map_cid is None && count >= 1 && count <= 32 &&
        @publication_host.client_submitted_intent_breakpoint_map_matches(intent, map_cid) else {
        return Err(
          SampleProfileBinding(
            RunEvidenceReferenceMismatch("control_admission.breakpoint_map"),
          ),
        )
      }
      // One six-node selector uses fewer than 160 ASCII units.
      (Some(map_cid), count, profile_wire.length() + 160 * count)
    }
    None => {
      if expected_breakpoint_map_cid is Some(expected) && map_cid != expected {
        return Err(
          SampleProfileBinding(
            RunEvidenceReferenceMismatch("control_admission.breakpoint_map"),
          ),
        )
      }
      let slots = if expected_breakpoint_map_cid is Some(_) { profile_wire.length() / 71 } else { 0 }
      (expected_breakpoint_map_cid, slots, profile_wire.length())
    }
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
      profile_units,
      namespace_bytes.to_int(),
      breakpoint_slots~,
      constructing_profile=submitted_breakpoints is Some(_),
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
  let profile = match submitted_breakpoints {
    None => profile
    Some(intent) => {
      guard @publication.run_evidence_value_wire_usage(profile)
        is Some((_, policy_nodes, _)) else {
        return Err(SampleProfileLimits)
      }
      // Replacing the original empty array and terminal string preserves
      // their node counts. Each added selector has two objects and four
      // strings. The sealed policy already counts the self CID field.
      let marked_nodes = policy_nodes + 6 * breakpoint_slots
      // Each bounded ASCII identity is copied once. The marked quote pays
      // selector materialization, the two schema checks and both emissions.
      match
        @resources.charge_planning(ledger, 8 * profile_units + 64 * marked_nodes) {
        Err(issue) => return Err(SampleProfileWork(issue))
        Ok(_) => ()
      }
      guard installed_sample_profile_binding_current(
        observation, holder, prepared, compiled, captured,
      ) else {
        return Err(ForeignSampleProfile)
      }
      match @publication.issue_interactive_entry_breakpoint_profile(
        profile,
        breakpoint_slots,
        index => @publication_host.client_submitted_intent_breakpoint_step(intent, index),
        Int::min(max_bytes, profile_units),
        Int::min(max_nodes, marked_nodes),
        Int::min(depth, 12),
      ) {
        Err(issue) => return Err(SampleProfileBinding(issue))
        Ok(value) => value
      }
    }
  }
  if profile_map is Some(_) {
    let count = @publication.interactive_profile_breakpoint_count(profile)
    if count > breakpoint_slots {
      return Err(SampleProfileLimits)
    }
    // Each exact-ID selector has one complete original Step scan, and
    // its resolved member is emitted and sealed in the original record.
    let work_per_breakpoint = output_count +
      6 +
      8 * installed_sample_resolved_breakpoint_wire_bytes
    match @resources.charge_planning(ledger, count * work_per_breakpoint) {
      Err(issue) => return Err(SampleProfileWork(issue))
      Ok(_) => ()
    }
    guard installed_sample_profile_binding_current(
      observation, holder, prepared, compiled, captured,
    ) else {
      return Err(ForeignSampleProfile)
    }
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
      expected_breakpoint_map_cid?=profile_map,
    ) {
    Err(issue) => return Err(SampleProfileBinding(issue))
    Ok(value) => value
  }
  let checked = match
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
      measured_reference_bytes=Some(reference_bytes),
    ) {
    Err(issue) => return Err(issue)
    Ok(checked) => checked
  }
  reserve_installed_sample_start_proof_copies(
    holder, prepared, intent, resolved, admission, profile,
  ).map(_ => {
    (
      checked,
      @publication.run_evidence_value_json(intent),
      @publication.run_evidence_value_json(resolved),
      @publication.run_evidence_value_json(admission),
      @publication.run_evidence_value_json(profile),
    )
  })
}
