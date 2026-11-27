///|
/// Already admitted immutable records supplied by the original profile
/// admission. This group neither retains output nor grants control or read.
pub(all) struct InstalledRelationSampleProfileEvidence {
  intent : @publication.RunEvidenceValue
  requested : @publication.RunEvidenceValue
  effective : @publication.RunEvidenceValue
  resolved : @publication.RunEvidenceValue
  map : @publication.RunEvidenceValue
  admission : @publication.RunEvidenceValue
}

///|
pub(all) enum InstalledRelationSampleProfileIssue {
  ForeignSampleProfile
  SampleProfileBusy
  SampleProfileLimits
  SampleProfileNotSelected
  SampleProfileCapacity(@resources.PreparationCapacityIssue)
  SampleProfileWork(@resources.LedgerIssue)
  SampleProfileBinding(@publication.RunEvidenceValueIssue)
}

///|
priv enum InstalledRelationSampleStartMode {
  UnattendedTerminal
  PausedEntry
  PausedBeforeBreakpoint(Int, Int, String, ReadOnlyArray[String])
  UnsupportedControl
}

///|
/// Borrowed policy facts for this live, checked physical setup. The opaque
/// original is retained by the existing Run reservation after observation
/// return. It grants neither capture nor disclosure.
struct ClientCheckedRelationSampleProfile {
  owner : ClientInstalledManagedRun
  prepared : @publication_host.PreparedClientProgram
  request : @publication_host.ClientRequestIdentity
  compiled : @publication_host.ClientCompiledRun
  definition : @publication.PublicationContract
  captured : @strategy.CapturedDAG
  selection : @publication.InteractiveRelationSampleSelection
  start_mode : InstalledRelationSampleStartMode
  driver_outputs : Map[Int, (String, String, String)]
  control_admission_cid : String
  resolved_profile_cid : String
  logical_map_cid : String
}

///|
pub(all) struct InstalledRelationSampleRetention {
  limits : @publication.InteractiveRelationSampleLimits
  control_admission_cid : String
  resolved_profile_cid : String
}

///|
// This fixed prefix covers the held-record inputs, current/return checks,
// scalar quotation controls and both call frames (H40/R72/W54).
// The nominal receipt, exact selection and bounds, Result/bridge carriers
// and the logical output, selection and authority checks add H18/R48/W18
// under the same Run. The already-funded output-ID map stays on this
// reservation; it is not rebuilt at each completed output.
let installed_relation_sample_profile_controls : Int64 = @execution.preparation_representation_cost({
    record_headers: 58L,
    reference_slots: 120L,
    scalar_words: 72L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  },
).unwrap()

///|
let installed_sample_profile_reference_bytes : Int64 = {
  let (bytes, nodes, depth) = @publication.interactive_submission_reference_limits()
  let emitter = compilation_canonical_emitter_layout(depth).unwrap()
  let writer = @encode.text_writer_construction_inventory(bytes, nodes, depth).unwrap()
  // The closed emitter visits one original subtree. Its canonical text and
  // both comparison outcomes coexist with the writer and ancestry.
  @execution.preparation_representation_cost({
    record_headers: emitter.record_headers + writer.record_headers + 4L,
    reference_slots: emitter.reference_slots + writer.reference_slots + 5L,
    scalar_words: emitter.scalar_words + writer.scalar_words + 4L,
    owned_utf16_units: emitter.owned_utf16_units + writer.owned_utf16_units,
    owned_wire_bytes: emitter.owned_wire_bytes,
  }).unwrap()
}

///|
// The reference decoder retains the outer parse, converts its epoch twice,
// and rebuilds the reference and derived request identity. Co-count the
// closed parser, writer and hash inventories through the final comparison.
let installed_sample_journal_reference_bytes : Int64 = {
  let (bytes, nodes, depth) = @publication.interactive_submission_reference_limits()
  let layout = program_artifact_parse_layout((bytes, nodes, depth)).unwrap()
  let epoch = @decode.preserving_json_admission_construction_inventory(
    bytes, nodes, depth,
  ).unwrap()
  let writer = @encode.text_writer_construction_inventory(bytes, nodes, depth).unwrap()
  let emitter = compilation_canonical_emitter_layout(depth).unwrap()
  let hash = @encode.hash_writer_construction_inventory(8, 1).unwrap()
  let (utf8_h, utf8_r, utf8_w) = @scalar.utf8_length_admission_construction_units()
  @execution.preparation_representation_cost({
    // Two preserving/canonical parses and two preserving/indexed epoch
    // decodes. The raw Digest and the request-ID writer each own a SHA sink.
    // Fixed controls include the epoch tag Array/Bytes, prepared/returned
    // records and the active bridge arguments, scalar admission and results.
    record_headers: 2L *
    (
      layout.temporary.record_headers +
      epoch.record_headers +
      emitter.record_headers
    ) +
    5L * writer.record_headers +
    3L * hash.record_headers +
    96L +
    utf8_h,
    reference_slots: 2L *
    (
      layout.temporary.reference_slots +
      epoch.reference_slots +
      emitter.reference_slots
    ) +
    5L * writer.reference_slots +
    3L * hash.reference_slots +
    128L +
    utf8_r,
    scalar_words: 2L *
    (layout.temporary.scalar_words + epoch.scalar_words + emitter.scalar_words) +
    5L * writer.scalar_words +
    3L * hash.scalar_words +
    192L +
    utf8_w,
    owned_utf16_units: 2L *
    (layout.temporary.owned_utf16_units + epoch.owned_utf16_units) +
    5L * writer.owned_utf16_units +
    3L * hash.owned_utf16_units +
    bytes.to_int64(),
    owned_wire_bytes: 2L * layout.temporary.owned_wire_bytes +
    3L * hash.owned_wire_bytes +
    5L * bytes.to_int64(),
  }).unwrap()
}

///|
// One selected driver completion wrapper and its synchronous callback/control
// arguments per declared output. The same reservation prepays the adoption
// entry's fixed original lookups, inventory records and quotation calls.
// The pending-return receiver and the existing Driver's additional cleanup
// wrapper retain the exact prefix and its close controls (H10/R24/W12).
let installed_sample_completion_receiver_bytes : Int64 = @execution.preparation_representation_cost({
    record_headers: 79L,
    reference_slots: 142L,
    scalar_words: 274L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  },
).unwrap()

///|
fn grow_installed_sample_profile_binding(
  holder : @resources.PreparationBodyBorrow[
    @publication_host.PreparedClientProgram,
  ],
  prepared : @publication_host.PreparedClientProgram,
  bytes : Int64,
) -> Result[Unit, InstalledRelationSampleProfileIssue] {
  let (r, e) = match
    @resources.preparation_body_borrow_reserved_extents(holder) {
    Err(issue) => return Err(SampleProfileCapacity(issue))
    Ok(extents) => extents
  }
  guard @execution.checked_preparation_add_product(r, bytes, 1L) is Some(r) &&
    @execution.checked_preparation_add_product(e, bytes, 1L) is Some(e) else {
    return Err(SampleProfileLimits)
  }
  @resources.reserve_preparation_publication_phase(holder, prepared, r, e).map_err(issue => {
      SampleProfileCapacity(issue)
    },
  )
}

///|
fn installed_sample_profile_binding_current(
  observation : ClientLogicalObservation,
  holder : @resources.PreparationBodyBorrow[
    @publication_host.PreparedClientProgram,
  ],
  prepared : @publication_host.PreparedClientProgram,
  compiled : @publication_host.ClientCompiledRun,
  captured : @strategy.CapturedDAG,
) -> Bool {
  !observation.closing &&
  physical_equal(observation.cleanup.holder, holder) &&
  observation.cleanup.original is Some((run, _, _)) &&
  run.source_free_captured is Some(actual) &&
  physical_equal(actual, captured) &&
  logical_observation_original(observation) is Some((current, plan)) &&
  physical_equal(current, prepared) &&
  physical_equal(plan, compiled)
}

///|
/// Bind declared Sample targets to the existing same-Run compiler observation.
/// Both phases reserve on its original body before scanning or constructing
/// maps and key codecs. Current capture/read rights remain separate.
pub fn check_installed_relation_sample_profile(
  owner : ClientInstalledManagedRun,
  request : @publication_host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  observation : ClientLogicalObservation,
  original_reference : @publication_host.ClientSubmissionReferenceRecord,
  records : InstalledRelationSampleProfileEvidence,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  ClientCheckedRelationSampleProfile,
  InstalledRelationSampleProfileIssue,
] {
  check_installed_relation_sample_profile_input(
    owner,
    request,
    definition,
    observation,
    @publication_host.client_submission_reference_record_wire(
      original_reference,
    ),
    records,
    max_bytes,
    max_nodes,
    max_depth,
    matches=@publication_host.client_submission_reference_matches_request(
      original_reference, request,
    ),
    decode_original=false,
  )
}

///|
/// The installed port supplies only the authenticated reference of the same
/// accepted Run. Parsing checks its shape and correspondence, not the HMAC.
pub fn check_installed_relation_sample_profile_journal_reference(
  owner : ClientInstalledManagedRun,
  request : @publication_host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  observation : ClientLogicalObservation,
  reference_wire : String,
  records : InstalledRelationSampleProfileEvidence,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  ClientCheckedRelationSampleProfile,
  InstalledRelationSampleProfileIssue,
] {
  check_installed_relation_sample_profile_input(
    owner,
    request,
    definition,
    observation,
    reference_wire,
    records,
    max_bytes,
    max_nodes,
    max_depth,
    matches=true,
    decode_original=true,
  ).bind(checked => {
    reserve_installed_sample_start_proof_copies(
      observation.cleanup.holder,
      checked.prepared,
      records.intent,
      records.resolved,
      records.admission,
      records.effective,
    ).map(_ => checked)
  })
}

///|
/// The recovery Read funds the four coexisting evidence constructors and the
/// original submission-reference decoder before passing their wires in.
pub fn retained_relation_sample_profile_read_bytes(
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  stored_bytes : Int,
) -> Int64? {
  let stored = stored_bytes.to_int64()
  guard stored >= 0L &&
    result_read_data_cost(stored, 6L * stored, 2L * stored) is Some(metadata) &&
    @execution.checked_preparation_add_product(
      installed_sample_journal_reference_bytes, metadata, 1L,
    )
    is Some(base) else {
    return None
  }
  guard @publication.run_evidence_admission_construction_inventory(
      max_bytes,
      Int::min(max_nodes, max_bytes),
      max_depth,
    )
    is Some(codec) &&
    @execution.preparation_representation_cost({
      record_headers: codec.record_headers + 16L,
      reference_slots: codec.reference_slots + 28L,
      scalar_words: codec.scalar_words + 16L,
      owned_utf16_units: codec.owned_utf16_units,
      owned_wire_bytes: codec.owned_wire_bytes,
    })
    is Some(one) else {
    return None
  }
  @execution.checked_preparation_add_product(base, one, 4L)
}

///|
/// Re-admit exactly the canonical records supplied by the authorized Journal
/// Read. Plan/Map selection work still debits the original captured Run.
pub fn readmit_installed_relation_sample_profile_wires(
  owner : ClientInstalledManagedRun,
  request : @publication_host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  observation : ClientLogicalObservation,
  reference_wire : String,
  intent_wire : String,
  profile_wire : String,
  resolved_wire : String,
  admission_wire : String,
  resolved_cid : String,
  admission_cid : String,
  wire_bytes : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  ClientCheckedRelationSampleProfile,
  InstalledRelationSampleProfileIssue,
] {
  if wire_bytes < 1 || wire_bytes > max_bytes {
    return Err(SampleProfileLimits)
  }
  guard @publication_host.admit_client_submission_reference_record(
      reference_wire,
    )
    is Ok(original_reference) &&
    @publication_host.client_submission_reference_record_wire(
      original_reference,
    ) ==
    reference_wire &&
    @publication_host.client_submission_reference_matches_request(
      original_reference, request,
    ) else {
    return Err(ForeignSampleProfile)
  }
  fn admit(name : String, wire : String) {
    @publication.admit_run_evidence_value(
      name,
      wire,
      wire_bytes,
      Int::min(max_nodes, wire_bytes),
      max_depth,
    )
  }
  guard admit("control_request_intent", intent_wire) is Ok(intent) &&
    admit("control_profile", profile_wire) is Ok(profile) &&
    admit("resolved_control_profile", resolved_wire) is Ok(resolved) &&
    admit("control_admission", admission_wire) is Ok(admission) &&
    observation.original is Some(original) &&
    @publication.run_evidence_value_identity(resolved) == resolved_cid &&
    @publication.run_evidence_value_identity(admission) == admission_cid else {
    return Err(ForeignSampleProfile)
  }
  check_installed_relation_sample_profile_input(
    owner,
    request,
    definition,
    observation,
    reference_wire,
    {
      intent,
      requested: profile,
      effective: profile,
      resolved,
      map: original.sealed_map,
      admission,
    },
    max_bytes,
    max_nodes,
    max_depth,
    matches=true,
    decode_original=false,
    use_exact_map_nodes=true,
  )
}

///|
fn check_installed_relation_sample_profile_input(
  owner : ClientInstalledManagedRun,
  request : @publication_host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  observation : ClientLogicalObservation,
  reference_wire : String,
  records : InstalledRelationSampleProfileEvidence,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  matches~ : Bool,
  decode_original~ : Bool,
  use_exact_map_nodes? : Bool = false,
) -> Result[
  ClientCheckedRelationSampleProfile,
  InstalledRelationSampleProfileIssue,
] {
  if owner.source_free_opening || observation.reading {
    return Err(SampleProfileBusy)
  }
  guard matches &&
    observation.cleanup.original is Some((run, prepared, compiled)) &&
    physical_equal(run, owner) &&
    owner.source_free_captured is Some(captured) &&
    installed_relation_sample_start_matches(
      owner, prepared, request, compiled, definition, captured,
    ) &&
    installed_sample_profile_binding_current(
      observation,
      observation.cleanup.holder,
      prepared,
      compiled,
      captured,
    ) else {
    return Err(ForeignSampleProfile)
  }
  owner.source_free_opening = true
  observation.reading = true
  let result = check_installed_relation_sample_profile_original(
    request,
    definition,
    observation,
    prepared,
    compiled,
    captured,
    reference_wire,
    records,
    max_bytes,
    max_nodes,
    max_depth,
    decode_original~,
    use_exact_map_nodes~,
  )
  observation.reading = false
  owner.source_free_opening = false
  result
}

///|
fn check_installed_relation_sample_profile_original(
  request : @publication_host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  observation : ClientLogicalObservation,
  prepared : @publication_host.PreparedClientProgram,
  compiled : @publication_host.ClientCompiledRun,
  captured : @strategy.CapturedDAG,
  reference_wire : String,
  records : InstalledRelationSampleProfileEvidence,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  decode_original~ : Bool,
  use_exact_map_nodes? : Bool = false,
  measured_reference_bytes? : Int? = None,
) -> Result[
  ClientCheckedRelationSampleProfile,
  InstalledRelationSampleProfileIssue,
] {
  let holder = observation.cleanup.holder
  let journal_bytes = if decode_original {
    installed_sample_journal_reference_bytes
  } else {
    0L
  }
  guard explanation_logical_map_scanner_bytes() is Some(scanner) &&
    @execution.checked_preparation_add_product(
      installed_relation_sample_profile_controls, scanner, 1L,
    )
    is Some(entry) &&
    @execution.checked_preparation_add_product(
      entry,
      installed_sample_profile_reference_bytes + journal_bytes,
      1L,
    )
    is Some(entry) else {
    return Err(SampleProfileLimits)
  }
  match grow_installed_sample_profile_binding(holder, prepared, entry) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard installed_sample_profile_binding_current(
      observation, holder, prepared, compiled, captured,
    ) &&
    observation.original is Some(original) &&
    @publication_host.client_structural_explanation_map_matches(
      original,
      compiled,
      prepared,
      records.map,
    ) &&
    @publication.publication_contract_run_definition_scope(definition)
    is Some(namespace_id) else {
    return Err(ForeignSampleProfile)
  }
  for
    value in [
      records.intent,
      records.requested,
      records.effective,
      records.resolved,
      records.map,
      records.admission,
    ] {
    if !@publication.run_evidence_value_fits(
        value, max_bytes, max_nodes, max_depth,
      ) {
      return Err(SampleProfileLimits)
    }
  }
  let ledger = @strategy.captured_dag_ledger(captured)
  let (reference_bytes, reference_nodes, _) = @publication.interactive_submission_reference_limits()
  if decode_original {
    // A fresh issuer already measured this same immutable reference under
    // the original Ledger. Other callers fund the exact UTF-16 scan before
    // finding its UTF-8 extent. The parser still checks the retained wire.
    let extent = match measured_reference_bytes {
      Some(bytes) => bytes
      None => {
        let units = reference_wire.length()
        if units > reference_bytes {
          return Err(ForeignSampleProfile)
        }
        match @resources.charge_planning(ledger, units) {
          Err(issue) => return Err(SampleProfileWork(issue))
          Ok(_) => ()
        }
        guard @scalar.admit_utf8_length(reference_wire, reference_bytes)
          is Ok(bytes) else {
          return Err(ForeignSampleProfile)
        }
        bytes
      }
    }
    match
      @resources.charge_planning(ledger, 12 * extent + 16 * reference_nodes) {
      Err(issue) => return Err(SampleProfileWork(issue))
      Ok(_) => ()
    }
    guard @publication_host.admit_client_submission_reference_record(
        reference_wire,
      )
      is Ok(value) &&
      @publication_host.client_submission_reference_record_wire(value) ==
      reference_wire &&
      @publication_host.client_submission_reference_matches_request(
        value, request,
      ) else {
      return Err(ForeignSampleProfile)
    }
  }
  match @resources.charge_planning(ledger, reference_nodes) {
    Err(issue) => return Err(SampleProfileWork(issue))
    Ok(_) => ()
  }
  guard installed_sample_profile_binding_current(
      observation, holder, prepared, compiled, captured,
    ) &&
    @publication.check_interactive_admission_request_identity(
      records.intent,
      records.admission,
      @publication_host.client_request_intent_cid(request),
      @publication_host.client_request_authority_scope_cid(request),
      reference_wire,
    ) else {
    return Err(ForeignSampleProfile)
  }
  // For a freshly issued same-owner Map, its admitted canonical geometry
  // bounds both scans. An external evidence call retains its original bound.
  guard @publication.run_evidence_value_wire_usage(records.map)
    is Some((_, map_nodes, _)) else {
    return Err(SampleProfileLimits)
  }
  let map_visit_limit = if use_exact_map_nodes { map_nodes } else { max_nodes }
  match @resources.charge_planning(ledger, map_visit_limit) {
    Err(issue) => return Err(SampleProfileWork(issue))
    Ok(_) => ()
  }
  guard installed_sample_profile_binding_current(
    observation, holder, prepared, compiled, captured,
  ) else {
    return Err(ForeignSampleProfile)
  }
  let breakpoints = @publication.interactive_profile_breakpoint_count(
    records.effective,
  ).to_int64()
  let plan = @publication_host.client_compiled_run_plan(compiled)
  guard @publication.interactive_logical_map_binding_construction(
      records.map,
      plan,
      max_bytes,
      max_nodes,
      max_depth,
    )
    is Some(binding) &&
    explanation_logical_map_binding_bytes(binding) is Some(map_bytes) &&
    @shape.collection_construction_extent({
      // The second pass maps checked Step and selected output IDs. Keys
      // borrow the original strings. Fixed selector and Result wrappers are
      // in the entry prefix, and the first pass has its own inventory.
      // At most one retained original projection tuple per output. It
      // borrows the three identity strings already on the checked map.
      records: binding.outputs.to_int64() + breakpoints,
      record_references: 3L * (binding.outputs.to_int64() + breakpoints),
      record_words: 0L,
      reference_arrays: 0L,
      reference_items: 0L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: if breakpoints == 0L {
        3L
      } else {
        4L
      },
      map_entries: binding.steps.to_int64() +
      2L * binding.outputs.to_int64() +
      breakpoints,
    })
    is Some(inventory) &&
    @execution.preparation_representation_cost({
      record_headers: inventory.record_headers,
      reference_slots: inventory.reference_slots,
      scalar_words: inventory.scalar_words,
      owned_utf16_units: 3L * 71L * binding.outputs.to_int64(),
      owned_wire_bytes: 0L,
    })
    is Some(selected_bytes) &&
    @execution.checked_preparation_add_product(map_bytes, selected_bytes, 1L)
    is Some(bytes) &&
    @execution.checked_preparation_add_product(
      bytes,
      installed_sample_completion_receiver_bytes,
      binding.outputs.to_int64(),
    )
    is Some(bytes) else {
    return Err(SampleProfileLimits)
  }
  // A marked start can retain a later Step coordinate. Its tuple, Option,
  // Result and start-mode payload coexist with one resolved ID/output lookup
  // and the forward coordinate check. The marked owner also covers the
  // co-held start ticket and synchronous ACK receiver (H1/R8/W4).
  let bytes = if breakpoints == 0L {
    bytes
  } else {
    let coordinates = @execution.preparation_representation_cost({
      record_headers: 10L,
      reference_slots: 16L,
      scalar_words: 12L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    }).unwrap()
    let markers = @execution.preparation_representation_cost({
      record_headers: 3L,
      reference_slots: 2L * breakpoints + 9L,
      scalar_words: 8L,
      owned_utf16_units: 71L * breakpoints,
      owned_wire_bytes: 0L,
    }).unwrap()
    guard @execution.checked_preparation_add_product(bytes, coordinates, 1L)
      is Some(total) &&
      @execution.checked_preparation_add_product(total, markers, 1L)
      is Some(total) else {
      return Err(SampleProfileLimits)
    }
    total
  }
  match grow_installed_sample_profile_binding(holder, prepared, bytes) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard installed_sample_profile_binding_current(
      observation, holder, prepared, compiled, captured,
    ) &&
    @publication.run_evidence_value_wire_usage(records.resolved)
    is Some((_, resolved_nodes, _)) else {
    return Err(ForeignSampleProfile)
  }
  // The sealed Map node extent bounds visits to all Steps and names for
  // each selector. The verifier stops at its own max_nodes visit limit.
  let breakpoint_visits = Int64::min(
    max_nodes.to_int64(),
    (map_nodes.to_int64() + 2L) * breakpoints,
  )
  // Two admission passes, the bounded selector/name scan and both resolved
  // lists. A refused profile never opens the physical task index.
  let visits = 2L * (binding.steps.to_int64() + binding.ports.to_int64()) +
    map_visit_limit.to_int64() +
    resolved_nodes.to_int64() +
    breakpoint_visits
  if visits > 2147483647L {
    return Err(SampleProfileLimits)
  }
  match @resources.charge_planning(ledger, visits.to_int()) {
    Err(issue) => return Err(SampleProfileWork(issue))
    Ok(_) => ()
  }
  guard installed_sample_profile_binding_current(
    observation, holder, prepared, compiled, captured,
  ) else {
    return Err(ForeignSampleProfile)
  }
  let selection = match
    @publication.bind_interactive_relation_sample_selection(
      records.intent,
      records.requested,
      records.effective,
      records.resolved,
      records.map,
      records.admission,
      plan,
      namespace_id,
      @publication.publication_contract_identity(definition),
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Err(issue) => return Err(SampleProfileBinding(issue))
    Ok(None) => return Err(SampleProfileNotSelected)
    Ok(Some(selection)) => selection
  }
  let index_work = 2L * binding.steps.to_int64()
  if index_work > 2147483647L {
    return Err(SampleProfileLimits)
  }
  match @resources.charge_planning(ledger, index_work.to_int()) {
    Err(issue) => return Err(SampleProfileWork(issue))
    Ok(_) => ()
  }
  guard installed_sample_profile_binding_current(
      observation, holder, prepared, compiled, captured,
    ) &&
    observation.cleanup.original is Some((owner, _, _)) else {
    return Err(ForeignSampleProfile)
  }
  let driver_outputs = match
    @publication_host.index_client_logical_relation_sample_outputs(
      original, compiled, prepared, selection,
    ) {
    Ok(value) => value
    Err(_) => return Err(ForeignSampleProfile)
  }
  let start_mode = if @publication.interactive_profile_allows_unattended_terminal(
      records.effective,
    ) {
    UnattendedTerminal
  } else if @publication.interactive_profile_requires_entry_stop(
      records.effective,
    ) {
    PausedEntry
  } else if @publication.interactive_profile_requires_breakpoint_entry(
      records.effective,
    ) {
    let coordinate = match
      select_installed_entry_breakpoint(
        records.resolved,
        captured,
        driver_outputs,
        breakpoints,
      ) {
      Err(issue) => return Err(issue)
      Ok(value) => value
    }
    guard installed_sample_profile_binding_current(
      observation, holder, prepared, compiled, captured,
    ) else {
      return Err(ForeignSampleProfile)
    }
    match coordinate {
      Some((stage, operation, selected, marks)) =>
        PausedBeforeBreakpoint(stage, operation, selected, marks)
      None => PausedEntry
    }
  } else {
    UnsupportedControl
  }
  Ok({
    owner,
    prepared,
    request,
    compiled,
    definition,
    captured,
    selection,
    start_mode,
    driver_outputs,
    control_admission_cid: @publication.run_evidence_value_identity(
      records.admission,
    ),
    resolved_profile_cid: @publication.run_evidence_value_identity(
      records.resolved,
    ),
    logical_map_cid: @publication.run_evidence_value_identity(records.map),
  })
}

///|
// Resolve every selected Step through the existing checked task/output index.
// Keep the ordered original IDs and the first later coordinate. A mark on
// the entry is already held by the initial pause. A Step without a task refuses.
fn select_installed_entry_breakpoint(
  resolved : @publication.RunEvidenceValue,
  captured : @strategy.CapturedDAG,
  outputs : Map[Int, (String, String, String)],
  count : Int64,
) -> Result[
  (Int, Int, String, ReadOnlyArray[String])?,
  InstalledRelationSampleProfileIssue,
] {
  let graph = @strategy.captured_dag_graph(captured)
  let tasks = @strategy.graph_task_count(graph)
  let entry = @strategy.captured_compute_first_task(captured)
  guard count > 0L && count <= 64L && entry == 0 && tasks > 0 else {
    return Err(SampleProfileNotSelected)
  }
  let stages = @checked.unit_count(@strategy.graph_program(graph)).to_int64()
  // Each mark has one resolved lookup and at most a full task scan. The
  // selected coordinate needs one reverse traversal, a forward check and
  // one lookup of the already indexed original Step.
  let work = 5L +
    count * (3L + 2L * tasks.to_int64()) +
    stages +
    tasks.to_int64()
  guard work <= 2147483647L else { return Err(SampleProfileLimits) }
  match
    @resources.charge_planning(
      @strategy.captured_dag_ledger(captured),
      work.to_int(),
    ) {
    Err(issue) => return Err(SampleProfileWork(issue))
    Ok(_) => ()
  }
  let marks = Array(capacity=count.to_int())
  let mut earliest = tasks
  for index in 0..<count.to_int() {
    guard @publication.interactive_resolved_before_step(resolved, index)
      is Some(id) else {
      return Err(SampleProfileNotSelected)
    }
    let mut found = false
    for task in entry..<tasks {
      if outputs.get(task) is Some((original, _, _)) && original == id {
        found = true
        if task > entry && task < earliest {
          earliest = task
        }
        break
      }
    }
    if !found {
      return Err(SampleProfileNotSelected)
    }
    marks.push(id)
  }
  if earliest == tasks {
    return Ok(None)
  }
  let operation = @strategy.graph_task_selected_step(graph, earliest).unwrap_or(
    0,
  )
  guard outputs.get(earliest) is Some((selected, _, _)) &&
    @strategy.graph_task_unit_index(graph, earliest) is Some(stage) &&
    @strategy.checked_task_control_operation_task(graph, stage, operation) ==
    Some(earliest) else {
    return Err(SampleProfileNotSelected)
  }
  Ok(Some((stage, operation, selected, ReadOnlyArray::from_array(marks))))
}

///|
/// Match only the exact Map and ordered original marks while this issued
/// profile is still owned by the selected Run. The Journal checks its CAS.
pub fn installed_relation_sample_entry_breakpoint_matches(
  owner : ClientInstalledManagedRun,
  profile : ClientCheckedRelationSampleProfile,
  logical_map_cid : String,
  before_step_ids : ReadOnlyArray[String],
) -> Bool {
  guard installed_relation_sample_profile_current(owner, profile) &&
    profile.logical_map_cid == logical_map_cid &&
    profile.start_mode is PausedBeforeBreakpoint(_, _, _, marks) &&
    before_step_ids.length() == marks.length() else {
    return false
  }
  if @resources.charge_planning(
      @strategy.captured_dag_ledger(profile.captured),
      marks.length() + 1,
    )
    is Err(_) ||
    !installed_relation_sample_profile_current(owner, profile) {
    return false
  }
  for index in 0..<marks.length() {
    if marks[index] != before_step_ids[index] {
      return false
    }
  }
  true
}

///|
/// The initial Step is already parked. Only a later checked target needs
/// the marked physical start receipt.
pub fn installed_relation_sample_profile_requires_entry_breakpoint(
  profile : ClientCheckedRelationSampleProfile,
) -> Bool {
  profile.start_mode is PausedBeforeBreakpoint(_, _, _, _)
}

///|
/// Immutable identity evidence from the same admitted profile receipt.
pub fn installed_relation_sample_profile_start_original(
  profile : ClientCheckedRelationSampleProfile,
) -> (
  String,
  String,
  @publication_host.PreparedClientProgram,
  @publication_host.ClientCompiledRun,
  String,
) {
  (
    profile.control_admission_cid,
    profile.resolved_profile_cid,
    profile.prepared,
    profile.compiled,
    profile.logical_map_cid,
  )
}

///|
fn installed_relation_sample_profile_current(
  owner : ClientInstalledManagedRun,
  profile : ClientCheckedRelationSampleProfile,
) -> Bool {
  physical_equal(owner, profile.owner) &&
  !owner.source_free_opening &&
  installed_relation_sample_start_matches(
    owner,
    profile.prepared,
    profile.request,
    profile.compiled,
    profile.definition,
    profile.captured,
  ) &&
  managed_run_publication_body(owner, profile.prepared) is Ok(_)
}

///|
/// Match a write candidate against the policy and exact port already admitted
/// by this checked profile. The caller separately proves the live prefix.
pub fn installed_relation_sample_adoption_matches_profile(
  profile : ClientCheckedRelationSampleProfile,
  logical_map_cid : String,
  output_port_id : String,
  max_items : String,
  max_bytes : String,
  max_artifacts : String,
  ttl_seconds : String,
  required : Bool,
) -> Bool {
  guard profile.logical_map_cid == logical_map_cid &&
    @publication.interactive_relation_sample_output_limits(
      profile.selection,
      output_port_id,
    )
    is Some(limits) else {
    return false
  }
  limits.max_items.to_string() == max_items &&
  limits.max_bytes.to_string() == max_bytes &&
  limits.max_artifacts.to_string() == max_artifacts &&
  limits.ttl_seconds.to_string() == ttl_seconds &&
  limits.required == required
}

///|
/// Resolve the supplied original output identity against the checked policy.
/// An absent port has no retention selection. The capture owner still proves
/// the actual logical output, committed prefix and independent authority.
pub fn installed_relation_sample_retention_for_output(
  owner : ClientInstalledManagedRun,
  profile : ClientCheckedRelationSampleProfile,
  port_id : String,
) -> Result[
  InstalledRelationSampleRetention?,
  InstalledRelationSampleProfileIssue,
] {
  if !installed_relation_sample_profile_current(owner, profile) {
    return Err(ForeignSampleProfile)
  }
  match
    @resources.charge_planning(
      @strategy.captured_dag_ledger(profile.captured),
      1,
    ) {
    Err(issue) => return Err(SampleProfileWork(issue))
    Ok(_) => ()
  }
  if !installed_relation_sample_profile_current(owner, profile) {
    return Err(ForeignSampleProfile)
  }
  Ok(
    @publication.interactive_relation_sample_output_limits(
      profile.selection,
      port_id,
    ).map(limits => {
      limits,
      control_admission_cid: profile.control_admission_cid,
      resolved_profile_cid: profile.resolved_profile_cid,
    }),
  )
}

///|
pub(all) enum InstalledRelationSamplePrefixIssue {
  SamplePrefixProfile(InstalledRelationSampleProfileIssue)
  SamplePrefixLogical(@publication_host.ClientLogicalTaskBoundaryIssue)
  SamplePrefixAuthorityLost
  SamplePrefixLimits
  SamplePrefixPhysical(@strategy.CapturedRelationSamplePrefixIssue)
  SamplePrefixVisitorRefused
}

///|
struct InstalledRelationSamplePrefix {
  mut original : InstalledRelationSamplePrefixOriginal?
  cleanup : @strategy.CapturedRelationSamplePrefix
  mut adopting : Bool
  mut adoption_reservation : @resources.CapacityReservation?
}

///|
priv struct InstalledRelationSamplePrefixOriginal {
  profile : ClientCheckedRelationSampleProfile
  retention : InstalledRelationSampleRetention
  step_id : String
  port_id : String
  carrier_contract_cid : String
}

///|
/// Take the selected prefix from the committing driver’s live typed Relation.
/// The capture authority port is synchronous and independent of the policy
/// receipt. No bytes go to that port and no Journal adoption is implied.
pub fn[T] retain_installed_relation_sample_prefix(
  owner : ClientInstalledManagedRun,
  profile : ClientCheckedRelationSampleProfile,
  boundary : @publication_host.ClientLogicalTaskBoundary,
  completed : @execution.ManagedCompletedOutput[T],
  original : @execution.CompletedOutput,
  schema : @execution.RelationSchemaIdentityLimits,
  max_nodes : Int,
  max_depth : Int,
  require_capture_current : () -> Bool,
) -> Result[InstalledRelationSamplePrefix?, InstalledRelationSamplePrefixIssue] {
  if !installed_relation_sample_profile_current(owner, profile) {
    return Err(SamplePrefixProfile(ForeignSampleProfile))
  }
  let output = match
    @publication_host.client_logical_task_boundary_relation_output(
      boundary,
      profile.compiled,
      profile.prepared,
      profile.captured,
      profile.logical_map_cid,
    ) {
    Err(issue) => return Err(SamplePrefixLogical(issue))
    Ok(None) => return Ok(None)
    Ok(Some(value)) => value
  }
  retain_selected_installed_relation_sample_prefix(
    owner,
    profile,
    output,
    require_capture_current,
    (max_items, max_bytes, current) => {
      @publication_host.capture_client_logical_managed_relation_sample_prefix(
        boundary,
        profile.compiled,
        profile.prepared,
        profile.captured,
        completed,
        original,
        max_items,
        schema,
        max_bytes,
        max_nodes,
        max_depth,
        current,
      )
    },
  )
}

///|
fn retain_selected_installed_relation_sample_prefix(
  owner : ClientInstalledManagedRun,
  profile : ClientCheckedRelationSampleProfile,
  output : (String, String, String),
  require_capture_current : () -> Bool,
  capture : (Int, Int, () -> Bool) -> Result[
    @strategy.CapturedRelationSamplePrefix,
    @strategy.CapturedRelationSamplePrefixIssue,
  ],
) -> Result[InstalledRelationSamplePrefix?, InstalledRelationSamplePrefixIssue] {
  let (step_id, port_id, carrier_contract_cid) = output
  let retention = match
    installed_relation_sample_retention_for_output(owner, profile, port_id) {
    Err(issue) => return Err(SamplePrefixProfile(issue))
    Ok(None) => return Ok(None)
    Ok(Some(value)) => value
  }
  let limits = retention.limits
  if limits.max_bytes > 2147483647L || limits.max_items > 2147483647L {
    return Err(SamplePrefixLimits)
  }
  if !require_capture_current() {
    return Err(SamplePrefixAuthorityLost)
  }
  if !installed_relation_sample_profile_current(owner, profile) {
    return Err(SamplePrefixProfile(ForeignSampleProfile))
  }
  let prefix = match
    capture(limits.max_items.to_int(), limits.max_bytes.to_int(), () => {
      require_capture_current() &&
      installed_relation_sample_profile_current(owner, profile)
    }) {
    Err(@strategy.AuthorityLost) => return Err(SamplePrefixAuthorityLost)
    Err(issue) => return Err(SamplePrefixPhysical(issue))
    Ok(value) => value
  }
  let issue = if !require_capture_current() {
    Some(SamplePrefixAuthorityLost)
  } else if !installed_relation_sample_profile_current(owner, profile) {
    Some(SamplePrefixProfile(ForeignSampleProfile))
  } else if @strategy.captured_managed_relation_sample_prefix_current(
      profile.captured,
      prefix,
    )
    is None {
    Some(SamplePrefixPhysical(@strategy.StaleOriginal))
  } else {
    None
  }
  if issue is Some(primary) {
    // The lower owner retains a declined return. No higher receipt escapes.
    @strategy.return_captured_relation_sample_prefix(prefix) |> ignore
    return Err(primary)
  }
  Ok(
    Some({
      original: Some({
        profile,
        retention,
        step_id,
        port_id,
        carrier_contract_cid,
      }),
      cleanup: prefix,
      adopting: false,
      adoption_reservation: None,
    }),
  )
}

///|
/// The installed managed Driver calls this immediately after its successful
/// commit. Resolve the prebound output from the actual current task, then
/// borrow that original settled boundary for the existing typed prefix.
pub fn[T] retain_installed_committed_relation_sample(
  owner : ClientInstalledManagedRun,
  profile : ClientCheckedRelationSampleProfile,
  task : Int,
  completed : @execution.ManagedCompletedOutput[T],
  original : @execution.CompletedOutput?,
  schema : @execution.RelationSchemaIdentityLimits,
  max_nodes : Int,
  max_depth : Int,
  require_capture_current : () -> Bool,
) -> Result[InstalledRelationSamplePrefix?, InstalledRelationSamplePrefixIssue] {
  if !installed_relation_sample_profile_current(owner, profile) {
    return Err(SamplePrefixProfile(ForeignSampleProfile))
  }
  guard profile.driver_outputs.get(task) is Some(output) else {
    return Ok(None)
  }
  guard original is Some(relation) &&
    @strategy.captured_task_boundary_hooks(profile.captured) is Some(hooks) else {
    return Err(SamplePrefixPhysical(@strategy.StaleOriginal))
  }
  if !require_capture_current() {
    return Err(SamplePrefixAuthorityLost)
  }
  let boundary = match
    @strategy.read_captured_task_boundary(profile.captured, hooks, Settled) {
    Err(issue) => return Err(SamplePrefixPhysical(@strategy.Boundary(issue)))
    Ok(None) => return Err(SamplePrefixPhysical(@strategy.StaleOriginal))
    Ok(Some(value)) => value
  }
  let result = if @strategy.captured_task_boundary_task(boundary) != task {
    Err(SamplePrefixPhysical(@strategy.StaleOriginal))
  } else {
    retain_selected_installed_relation_sample_prefix(
      owner,
      profile,
      output,
      require_capture_current,
      (max_items, max_bytes, current) => {
        @strategy.capture_captured_managed_relation_sample_prefix(
          profile.captured,
          boundary,
          completed,
          relation,
          max_items,
          schema,
          max_bytes,
          max_nodes,
          max_depth,
          current,
        )
      },
    )
  }
  match @strategy.return_captured_task_boundary(boundary) {
    Ok(_) => result
    Err(issue) =>
      match result {
        Err(_) => result
        Ok(prefix) => {
          if prefix is Some(value) {
            return_installed_relation_sample_prefix(value) |> ignore
          }
          Err(SamplePrefixPhysical(@strategy.Boundary(issue)))
        }
      }
  }
}

///|
/// The Driver's selected commit observer takes no ownership of the prefix.
/// Its synchronous visitor may adopt through the original Journal scope.
/// On refusal to return, the same prefix transfers to the Driver's existing
/// additional cleanup owner before the first failure leaves this frame.
pub fn[T] with_installed_committed_relation_sample(
  owner : ClientInstalledManagedRun,
  profile : ClientCheckedRelationSampleProfile,
  task : Int,
  completed : @execution.ManagedCompletedOutput[T],
  original : @execution.CompletedOutput?,
  schema : @execution.RelationSchemaIdentityLimits,
  max_nodes : Int,
  max_depth : Int,
  require_capture_current : () -> Bool,
  visit : (InstalledRelationSamplePrefix) -> Bool,
  retain_pending : (InstalledRelationSamplePrefix) -> Unit,
) -> Result[Bool, InstalledRelationSamplePrefixIssue] {
  let sample = match
    retain_installed_committed_relation_sample(
      owner, profile, task, completed, original, schema, max_nodes, max_depth, require_capture_current,
    ) {
    Err(issue) => return Err(issue)
    Ok(None) => return Ok(false)
    Ok(Some(value)) => value
  }
  let accepted = visit(sample)
  let returned = return_installed_relation_sample_prefix(sample)
  if returned is Err(_) {
    retain_pending(sample)
  }
  if !accepted {
    return Err(SamplePrefixVisitorRefused)
  }
  returned
  .map(_ => true)
  .map_err(issue => SamplePrefixPhysical(@strategy.Boundary(issue)))
}

///|
/// Called before opening a managed task. Only the installed checked index
/// can select a receiver or decide whether this capture is required.
pub fn installed_relation_sample_driver_requirement(
  profile : ClientCheckedRelationSampleProfile,
  task : Int,
) -> Bool? {
  guard profile.driver_outputs.get(task) is Some((_, port, _)) else {
    return None
  }
  @publication.interactive_relation_sample_output_limits(
    profile.selection,
    port,
  ).map(limits => limits.required)
}

///|
/// A declined physical return stays on the original Run. The installed
/// Driver must stop before publication while that return is unresolved.
pub fn installed_relation_sample_driver_cleanup_pending(
  profile : ClientCheckedRelationSampleProfile,
) -> Bool {
  @strategy.captured_task_boundary_cleanup_pending(profile.captured)
}

///|
/// Borrow a selected prefix and its actual commit occurrence for sealing on
/// the same Run. The prefix owns its pin. The caller independently checks authority
/// and custody through Journal admission.
pub fn installed_relation_sample_prefix_original(
  owner : ClientInstalledManagedRun,
  prefix : InstalledRelationSamplePrefix,
) -> (
  InstalledRelationSampleRetention,
  String,
  String,
  String,
  @encode.EncodedDocument,
  Int,
  Int,
  Int,
  Int64,
  Int,
)? {
  guard prefix.original is Some(original) &&
    installed_relation_sample_profile_current(owner, original.profile) &&
    @strategy.captured_managed_relation_sample_prefix_current(
      original.profile.captured,
      prefix.cleanup,
    )
    is Some((document, items, total, generation, attempt, revision)) else {
    return None
  }
  Some(
    (
      original.retention,
      original.step_id,
      original.port_id,
      original.carrier_contract_cid,
      document,
      items,
      total,
      generation,
      attempt,
      revision,
    ),
  )
}

///|
pub fn return_installed_relation_sample_prefix(
  prefix : InstalledRelationSamplePrefix,
) -> Result[Unit, @strategy.CapturedTaskBoundaryIssue] {
  if prefix.adopting {
    return Err(@strategy.ReadInProgress)
  }
  prefix.adopting = true
  defer {
    prefix.adopting = false
  }
  if prefix.original is Some(original) {
    match
      settle_installed_sample_adoption(
        @strategy.captured_dag_ledger(original.profile.captured),
        prefix,
      ) {
      Err(issue) => return Err(@strategy.Resource(issue))
      Ok(_) => ()
    }
  }
  prefix.original = None
  match @strategy.return_captured_relation_sample_prefix(prefix.cleanup) {
    Err(@strategy.ReadReturned) | Ok(_) => Ok(())
    Err(issue) => Err(issue)
  }
}
