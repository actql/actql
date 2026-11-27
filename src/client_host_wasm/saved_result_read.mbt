///|
/// One read operation's original metadata and input loans, never an executable
/// Run, grant or process cache. Partial validation remains attached to the same
/// output until explicit close; the physical Host owns its snapshot/FD duties.
priv struct StoredSavedResultRead {
  snapshot : @host.ClientSavedSubmissionSnapshot
  result_name : String
  fences : Array[(String, String, Int64, Bytes)]
  mut source : @local_run.LocalSDKReadSource?
  mut policy_capacity : @resources.CapacityReservation?
  mut selection_capacity : @resources.CapacityReservation?
  mut coordinates_capacity : @resources.CapacityReservation?
  mut selection : @publication.LocalSDKResultReadSelection?
  mut finite : @host.ClientLocalRunPolicyOriginal?
  mut owner : @publication.PublicationCommitPreparation?
  mut view : @publication.PublicationCommitReadView?
  mut commit_observation : Bool
  // Positive while a phase can advance, zero only after final encoding,
  // and negative once an entered advance can no longer continue.
  mut advances_remaining : Int
}

///|
// Lives only in a synchronous export after its first complete exact rebind.
priv struct SavedTaskMaterialProof {
  retained : StoredSavedResultRead
  configuration : StoredRunConfiguration
  physical : Int
}

///|
const SAVED_RESULT_ADVANCES_PER_PHASE : Int = 250000

///|
fn saved_result_read_current(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
  result_name : String,
) -> Result[Unit, Int] {
  match submission_lookup_current(value, record, configuration) {
    Err(code) => return Err(code)
    Ok(_) => ()
  }
  let tuple : @authorization.AccessTuple = {
    principal: configuration.tuple.principal,
    connection: configuration.tuple.connection,
    resource: "result/" + result_name,
    operation: "read",
  }
  guard configuration.sdk is Some(sdk) else { return Err(-32) }
  let installed_original_result = @publication.local_sdk_result_read_selection_uses_installed_result_authority(
    sdk.read,
  )
  if @authorization.local_result_read_authority_resource(
      configuration.account,
      tuple,
      installed_original_result,
    )
    is Some(_) {
    Ok(())
  } else {
    Err(-32)
  }
}

///|
fn begin_saved_result_read(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Result[Unit, Int] {
  guard saved_result_projection_kind(record.kind) &&
    record.saved_result is None &&
    configuration.sdk is Some(sdk) &&
    configuration.host_current is Some(current_handle) &&
    value.host_currents.get(current_handle) is Some(current) &&
    record.borrow is Ok(borrow) &&
    input_cursor(value, borrow.slot) is Some(cursor) &&
    @decode.closed_object(cursor, [
      "namespaceId", "authorityScopeCid", "runDefinitionCid", "resultName",
    ])
    is Ok(object) &&
    required_text(object, "resultName") is Some(result_name) &&
    !result_name.is_empty() else {
    return Err(-31)
  }
  let check = () => {
    saved_result_read_current(value, record, configuration, result_name)
  }
  match check() {
    Err(code) => return Err(code)
    Ok(_) => ()
  }
  let catalog_checked = if record.kind == INCREMENTAL_SAVED_RESULT_KIND {
    match submission_lookup_current(value, record, configuration) {
      Err(code) => return Err(code)
      Ok(_) => ()
    }
    if physical_journal_schema(current.physical) != 1 {
      return Err(-41)
    }
    true
  } else {
    false
  }
  let read_task_slots = if record.kind == INCREMENTAL_SAVED_RESULT_KIND {
    Some((run_key, ordinal) => {
      physical_journal_task_material_row(
        current.physical,
        check,
        run_key,
        ordinal,
      )
    })
  } else {
    None
  }
  let effect_fences = []
  let snapshot = match
    observe_submission_lookup(
      value,
      record,
      configuration,
      catalog_checked~,
      read_task_slots~,
      effect_read_fences=Some(effect_fences),
    ) {
    Ok(Some(value)) => value
    Ok(None) => return Err(-42)
    Err(code) => return Err(code)
  }
  guard @host.client_saved_submission_run_row(snapshot) is Some(row) &&
    @host.decode_client_run_journal_row_with_observation_originals(row.body)
    is Ok((run, Some(policy_wire), Some(observation_wire))) else {
    return Err(-42)
  }
  let submitted = @host.client_saved_submission_record(snapshot)
  if @host.restore_client_run_observation_originals_wire(
      run.definition,
      observation_wire,
      131072,
      8192,
      64,
    )
    is Err(_) {
    return Err(-32)
  }
  guard current.generation is Some((device, inode)) &&
    @host.client_publication_store_binding_body(
      configuration.run_namespace,
      sdk.store_authority_cid,
      device,
      inode,
    )
    is Ok(publication_binding) &&
    run.publication_binding == Some(publication_binding) else {
    return Err(-32)
  }
  let effect = if run.effect_material_originals is Some(_) {
    // No generic proof-less path for an Effectful Run.
    guard !effect_fences.is_empty() &&
      @host.client_completed_effect_file_preview(row, run) is Some(preview) else {
      return Err(-32)
    }
    Some(preview)
  } else {
    None
  }
  let retained : StoredSavedResultRead = {
    snapshot,
    result_name,
    fences: effect_fences,
    source: None,
    policy_capacity: None,
    selection_capacity: None,
    coordinates_capacity: None,
    selection: None,
    finite: None,
    owner: None,
    view: None,
    commit_observation: false,
    advances_remaining: -1,
  }
  // Retain the original holder before quoting or constructing the selector.
  record.saved_result = Some(retained)
  let is_task = run.task_materials_cid is Some(_) &&
    @host.client_saved_submission_task_materials_original(snapshot) is Some(_) &&
    run.effect_material_originals is None
  let can_select_file_policy = run.publication_policy_originals is Some(_) &&
    (
      (
        (is_task || effect is Some(_)) &&
        sdk_mock_file_read_selection_needed(configuration, sdk)
      ) ||
      (
        is_task &&
        sdk_local_model_file_read_selection_needed(configuration, sdk)
      )
    )
  fn select_alternate(read_cid : String) -> Result[Unit, Int] {
    guard sdk_accepted_file_read_selection_capacity(sdk)
      is Some((held, scratch)) &&
      @execution.checked_preparation_add_product(held, scratch, 1L)
      is Some(peak) else {
      return Err(-4)
    }
    let capacity = match @resources.reserve_capacity(value.root, held, peak) {
      Ok(capacity) => capacity
      Err(_) => return Err(-4)
    }
    retained.selection_capacity = Some(capacity)
    let selected = match
      check().bind(_ => {
        issue_sdk_accepted_file_read_selection(configuration, sdk)
      }) {
      Ok(selected) => selected
      Err(code) => return Err(code)
    }
    if @resources.shrink_capacity_reservation(value.root, capacity, held, 0L)
      is Err(_) {
      return Err(-4)
    }
    guard @publication.local_sdk_result_read_selection_cid(selected) == read_cid else {
      return Err(-32)
    }
    retained.selection = Some(selected)
    Ok(())
  }
  let alternate_issue : Ref[Int?] = Ref(None)
  let admit_alternate = if can_select_file_policy {
    Some(read_cid => {
      match select_alternate(read_cid) {
        Ok(_) => true
        Err(code) => {
          alternate_issue.val = Some(code)
          false
        }
      }
    })
  } else {
    None
  }
  // Match the retained finite body against the allowed selections in one
  // admission. Its exact CID chooses the mode, never the outcome of a read.
  let finite = match
    @host.admit_client_local_run_policy_original(
      @utf8.encode(policy_wire),
      sdk.profile,
      submitted.reference,
      run.request,
      run.definition,
      sdk.adoption_cid,
      @publication.local_sdk_result_read_selection_cid(sdk.read),
      admit_alternate_read_selection=admit_alternate,
    ) {
    Ok(value) => value
    Err(_) => return Err(alternate_issue.val.unwrap_or(-32))
  }
  match check() {
    Err(code) => return Err(code)
    Ok(_) => ()
  }
  retained.finite = Some(finite)
  retained.selection = Some(retained.selection.unwrap_or(sdk.read))
  let read = (table, key) => {
    physical_journal_row(current.physical, check, 1, table, key).bind(row => {
      match row {
        None => Ok(None)
        Some(row) => {
          if row.key != key {
            return Err(-41)
          }
          if retained.fences
            .iter()
            .find_first(item => item.0 == table && item.1 == key)
            is Some(held) {
            if held.2 != row.revision || held.3 != row.body {
              return Err(-32)
            }
          } else {
            retained.fences.push((table, key, row.revision, row.body))
          }
          Ok(Some(row.body))
        }
      }
    })
  }
  let definition = @publication.publication_contract_identity(run.definition)
  let loaded = match effect {
    Some(preview) =>
      @publication.read_stored_effect_publication(
        configuration.run_namespace,
        configuration.authority_scope_cid,
        definition,
        read,
        check,
        256,
        8388608,
        262144,
        65536,
        64,
        131072,
        preview,
      )
    None =>
      @publication.read_stored_effect_free_publication(
        configuration.run_namespace,
        configuration.authority_scope_cid,
        definition,
        read,
        check,
        256,
        8388608,
        262144,
        65536,
        64,
        131072,
      )
  }
  let owner = match loaded {
    Ok(Some(value)) => value
    Ok(None) => return Err(-42)
    Err(Read(code)) => return Err(code)
    Err(_) => return Err(-31)
  }
  retained.owner = Some(owner)
  retained.advances_remaining = SAVED_RESULT_ADVANCES_PER_PHASE
  Ok(())
}

///|
fn begin_saved_result_commit_observation(
  retained : StoredSavedResultRead,
  owner : @publication.PublicationCommitPreparation,
) -> Result[Unit, Int] {
  let view = match owner.finish_view() {
    Ok(value) => value
    Err(_) => return Err(-31)
  }
  retained.view = Some(view)
  let request = match owner.view_contract(view, 5) {
    Ok(value) => value
    Err(_) => return Err(-31)
  }
  let attempt = match owner.view_contract(view, 6) {
    Ok(value) => value
    Err(_) => return Err(-31)
  }
  let index = match owner.view_contract(view, 7) {
    Ok(value) => value
    Err(_) => return Err(-31)
  }
  if owner.begin_observed_commit(view, request, attempt, index) is Err(_) {
    return Err(-31)
  }
  retained.commit_observation = true
  Ok(())
}

///|
// The retained material belongs to this read. A new bounded turn observes
// only its original Run header in the fresh physical Read before using it.
fn observe_saved_result_run_control(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
  retained : StoredSavedResultRead,
) -> Result[Unit, Int] {
  guard configuration.host_current is Some(current_handle) &&
    value.host_currents.get(current_handle) is Some(current) &&
    @host.client_saved_submission_run_row(retained.snapshot) is Some(original) else {
    return Err(-32)
  }
  let check = () => {
    saved_result_read_current(
      value,
      record,
      configuration,
      retained.result_name,
    )
  }
  let header = match
    physical_journal_row(
      current.physical,
      check,
      1,
      "client_sqlite_saved_run_current",
      original.key,
      expected_body_length=Some(4),
    ) {
    Ok(Some(row)) if row.key == original.key => row
    Ok(_) => return Err(-32)
    Err(code) => return Err(code)
  }
  let mut extent = 0
  for index in 0..<4 {
    extent = extent | (header.body[index].to_int() << (index * 8))
  }
  if extent <= 0 || extent > 262144 {
    return Err(-41)
  }
  if header.revision == original.revision {
    return if extent == original.body.length() { Ok(()) } else { Err(-32) }
  }
  // A different physical generation cannot replace this read's selection.
  // Observe only the changed original Run inside the same fresh Read, with
  // the known exact extent and its existing typed journal-row validator.
  match
    physical_journal_row(
      current.physical,
      check,
      1,
      "client_runs",
      original.key,
      expected_body_length=Some(extent),
    ) {
    Ok(Some(row)) if row.key == original.key && row.revision == header.revision =>
      submission_run_row_original_with_identity(row, None).bind(_ => Err(-32))
    Ok(_) => Err(-32)
    Err(code) => Err(code)
  }
}

///|
// Reobserve the original Run control before one bounded owner quantum.
fn advance_saved_result_read(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Result[Bool, Int] {
  guard record.saved_result is Some(retained) &&
    retained.owner is Some(owner) &&
    retained.advances_remaining > 0 else {
    return Err(-33)
  }
  let remaining = retained.advances_remaining
  retained.advances_remaining = -1
  match
    observe_saved_result_run_control(value, record, configuration, retained) {
    Err(code) => return Err(code)
    Ok(_) => ()
  }
  let result = if retained.commit_observation {
    guard retained.view is Some(view) else { return Err(-33) }
    owner.advance_observed_commit(view, 256)
  } else {
    owner.advance(256)
  }
  let (done, _) = match result {
    Ok(progress) => progress
    Err(_) => return Err(-31)
  }
  let mut next = remaining - 1
  if done {
    if retained.commit_observation {
      return Ok(true)
    }
    match begin_saved_result_commit_observation(retained, owner) {
      Err(code) => return Err(code)
      Ok(_) => ()
    }
    next = SAVED_RESULT_ADVANCES_PER_PHASE
  } else if next == 0 {
    return Err(-34)
  }
  match
    saved_result_read_current(
      value,
      record,
      configuration,
      retained.result_name,
    ) {
    Err(code) => return Err(code)
    Ok(_) => ()
  }
  retained.advances_remaining = next
  Ok(false)
}

///|
fn finish_saved_result_read(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Result[Bytes, Int] {
  guard record.saved_result is Some(retained) &&
    retained.owner is Some(owner) &&
    retained.view is Some(view) &&
    retained.finite is Some(finite) &&
    retained.selection is Some(selection) &&
    configuration.sdk is Some(sdk) else {
    return Err(-33)
  }
  let snapshot = retained.snapshot
  let result_name = retained.result_name
  guard configuration.source_free_result_policy is Some(source_policy) else {
    return Err(-32)
  }
  // Reserve quote controls before constructing the accepted-Run policy
  // callback. Its same Saved projection retains the ticket on any refusal.
  let accepted_policy = @publication.local_sdk_result_read_selection_uses_accepted_run_policy(
    selection,
  )
  let mut held = 0L
  let mut high = 0L
  if accepted_policy {
    guard retained.policy_capacity is None else { return Err(-33) }
    guard @host.client_task_policy_construction_capacity(@host.Collection)
      is Some((control_retained, control_scratch)) &&
      @execution.checked_preparation_add_product(
        control_retained, control_scratch, 1L,
      )
      is Some(control_total) else {
      return Err(-4)
    }
    match
      @resources.reserve_capacity(value.root, control_retained, control_total) {
      Ok(capacity) => {
        held = control_retained
        high = control_total
        retained.policy_capacity = Some(capacity)
      }
      Err(_) => return Err(-4)
    }
  }
  let policy_issue : Ref[Int?]? = if accepted_policy {
    Some(Ref(None))
  } else {
    None
  }
  let fund : ((@host.ClientTaskPolicyConstructionStage) -> Bool)? = if policy_issue
    is Some(first_issue) {
    Some(stage => {
      guard first_issue.val is None &&
        retained.policy_capacity is Some(capacity) &&
        @host.client_task_policy_construction_capacity(stage)
        is Some((next_held, scratch)) &&
        @execution.checked_preparation_add_product(held, next_held, 1L)
        is Some(total) &&
        @execution.checked_preparation_add_product(total, scratch, 1L)
        is Some(peak) else {
        if first_issue.val is None {
          first_issue.val = Some(-4)
        }
        return false
      }
      let peak = Int64::max(high, peak)
      if @resources.grow_capacity_reservation(value.root, capacity, total, peak)
        is Err(_) {
        first_issue.val = Some(-4)
        return false
      }
      held = total
      high = peak
      match
        saved_result_read_current(value, record, configuration, result_name) {
        Err(code) => {
          first_issue.val = Some(code)
          false
        }
        Ok(_) => true
      }
    })
  } else {
    None
  }
  let source = match
    @local_run.prepare_local_saved_sdk_read_source(
      snapshot,
      finite,
      source_policy,
      configuration.account,
      configuration.tuple.principal,
      configuration.tuple.connection,
      sdk.adoption_cid,
      owner,
      view,
      selection~,
      fund_accepted_policy=fund,
    ) {
    Ok(value) => value
    Err(_) => return Err(policy_issue.bind(issue => issue.val).unwrap_or(-32))
  }
  retained.source = Some(source)
  if retained.policy_capacity is Some(capacity) &&
    @resources.shrink_capacity_reservation(value.root, capacity, held, 0L)
    is Err(_) {
    return Err(-4)
  }
  let (_, definition) = @local_run.local_sdk_read_source_run_identity(source)
  let materials = match
    owner.observed_result_read_materials(view, result_name, 16) {
    Ok(value) => value
    Err(_) => return Err(-31)
  }
  if materials.read.store_authority_cid != sdk.store_authority_cid {
    return Err(-32)
  }
  let mut binding = None
  for ordinal in 0..<16 {
    match owner.view_binding(view, ordinal) {
      Ok(value) if @publication.publication_contract_identity(value) ==
        materials.read.durable_result_binding_cid => {
        binding = Some(value)
        break
      }
      Ok(_) => ()
      Err(_) => break
    }
  }
  guard binding is Some(_) else { return Err(-31) }
  let (result_ordinal, binding_ordinal) = match
    @local_run.local_sdk_saved_result_coordinates(
      source,
      configuration.account,
      owner,
      view,
      result_name,
    ) {
    Ok(value) => value
    Err(_) => return Err(-32)
  }
  // Only the two coordinates cross the transport. Their original checked
  // view and contract bodies stay owned by this Saved operation in Common.
  guard retained.coordinates_capacity is None else { return Err(-33) }
  let coordinates_capacity = match @resources.reserve_capacity(value.root, 0L, 4096L) {
    Ok(capacity) => capacity
    Err(_) => return Err(-4)
  }
  retained.coordinates_capacity = Some(coordinates_capacity)
  guard @host.client_saved_submission_run_row(snapshot) is Some(run) else {
    return Err(-32)
  }
  let wire = match saved_result_coordinates_header(
    @publication.publication_contract_identity(definition),
    result_name, result_ordinal, binding_ordinal, run,
    @host.client_local_run_policy_original_read_expires_at(finite),
  ) {
    Ok(wire) => wire
    Err(code) => return Err(code)
  }
  if @resources.settle_capacity(value.root, coordinates_capacity) is Err(_) {
    return Err(-4)
  }
  retained.coordinates_capacity = None
  match saved_result_read_current(value, record, configuration, result_name) {
    Err(code) => return Err(code)
    Ok(_) => ()
  }
  retained.advances_remaining = 0
  Ok(wire)
}

///|
fn saved_result_coordinates_header(
  definition_cid : String,
  result_name : String,
  result_ordinal : Int,
  binding_ordinal : Int,
  run : @host.ClientJournalPhysicalRow,
  expires_at : String,
) -> Result[Bytes, Int] {
  guard definition_cid.length() == 71 &&
    run.key.length() == 71 && run.revision >= 0L &&
    run.body.length() > 0 && run.body.length() <= 262144 &&
    expires_at.length() == 24 &&
    result_ordinal >= 0 && result_ordinal <= 7 &&
    binding_ordinal >= 0 && binding_ordinal <= 7 &&
    @sha.text_hex(result_name) is Ok(name_digest) else {
    return Err(-34)
  }
  let identity = @utf8.encode(definition_cid + name_digest + run.key)
  let deadline = @utf8.encode(expires_at)
  guard identity.length() == 206 && deadline.length() == 24 else {
    return Err(-34)
  }
  let header : FixedArray[Byte] = FixedArray::make(SAVED_RESULT_COORDINATES_BYTES, 0)
  header[0] = 2
  header[1] = result_ordinal.to_byte()
  header[2] = binding_ordinal.to_byte()
  for index in 0..<identity.length() {
    header[index + 3] = identity[index]
  }
  for index in 0..<8 {
    header[209 + index] = (run.revision >> (index * 8)).to_byte()
  }
  for index in 0..<4 {
    header[217 + index] = (run.body.length() >> (index * 8)).to_byte()
  }
  for index in 0..<deadline.length() {
    header[221 + index] = deadline[index]
  }
  Ok(header.unsafe_reinterpret_as_bytes())
}

///|
fn supply_saved_result_read(
  value : Instance,
  record : StoredSubmissionProjection,
  wire : Bytes,
) -> Int {
  let result = status(
    @buffers.supply_buffer_output(value.pool, record.slot, wire),
  )
  if result == 0 {
    record.produced = true
  }
  result
}

///|
// Only the matched private selector can return 1 for an unfinished read.
// No part of the result wire becomes readable until the existing supply succeeds.
fn produce_incremental_saved_result(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Int {
  if !record.invoked {
    record.invoked = true
    return match begin_saved_result_read(value, record, configuration) {
      Err(code) => code
      Ok(_) => 1
    }
  }
  match advance_saved_result_read(value, record, configuration) {
    Err(code) => code
    Ok(false) => 1
    Ok(true) =>
      match finish_saved_result_read(value, record, configuration) {
        Err(code) => code
        Ok(wire) => supply_saved_result_read(value, record, wire)
      }
  }
}

///|
fn reobserve_saved_result_read(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
  retained : StoredSavedResultRead,
  targeted_task_material? : Bool = false,
  targeted_identity_rows? : Bool = false,
  task_material_proof? : SavedTaskMaterialProof? = None,
  same_reader_census? : Bool = false,
  reuse_proven_fence_rows? : Bool = false,
) -> Result[Unit, Int] {
  guard configuration.host_current is Some(current_handle) &&
    value.host_currents.get(current_handle) is Some(current) else {
    return Err(-32)
  }
  let check = () => {
    saved_result_read_current(
      value,
      record,
      configuration,
      retained.result_name,
    )
  }
  match check() {
    Err(code) => return Err(code)
    Ok(_) => ()
  }
  if task_material_proof is Some(proof) &&
    (
      !physical_equal(proof.retained, retained) ||
      !physical_equal(proof.configuration, configuration) ||
      proof.physical != current.physical
    ) {
    return Err(-32)
  }
  let catalog_status = physical_journal_schema(current.physical)
  let read = (table, key) => {
    physical_journal_row(current.physical, check, 1, table, key)
  }
  let scan = (table, cursor) => {
    physical_journal_row(current.physical, check, 0, table, cursor)
  }
  let read_task_slots = if targeted_task_material {
    Some(
      (
        (run_key, ordinal) => {
          physical_journal_task_material_row(
            current.physical,
            check,
            run_key,
            ordinal,
          )
        },
        -32,
      ),
    )
  } else {
    None
  }
  let read_identity = if targeted_identity_rows {
    let submission = @host.client_saved_submission_row(retained.snapshot)
    guard @host.client_saved_submission_run_row(retained.snapshot) is Some(run) &&
      submission.key.length() == 71 && run.key.length() == 71 else {
      return Err(-32)
    }
    let keys = @utf8.encode(submission.key + run.key)
    Some((table, key) => {
      if table == "client_submitted_intents" && key == submission.key {
        physical_journal_saved_identity_row(
          current.physical, check, keys, 0, submission.body.length(), run.body.length(),
        )
      } else if table == "client_runs" && key == run.key {
        physical_journal_saved_identity_row(
          current.physical, check, keys, 1, submission.body.length(), run.body.length(),
        )
      } else {
        Err(-32)
      }
    })
  } else {
    None
  }
  rebind_saved_result_originals(
    retained,
    catalog_status,
    scan,
    read,
    read_identity~,
    read_task_slots~,
    census_ticket=if same_reader_census { current.physical } else { 0 },
    census_current=physical_journal_saved_reader,
    target_cancellation=configuration.sdk is Some(_),
    reuse_proven_task_material=task_material_proof is Some(_),
    reuse_proven_fence_rows~,
  )
}

///|
fn rebind_saved_result_originals(
  retained : StoredSavedResultRead,
  catalog_status : Int,
  scan : (String, String) -> Result[@host.ClientJournalPhysicalRow?, Int],
  read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, Int],
  read_identity? : ((String, String) -> Result[@host.ClientJournalPhysicalRow?, Int])? = None,
  read_task_slots? : (
    (String, Int) -> Result[@host.ClientJournalPhysicalRow?, Int],
    Int,
  )? = None,
  census_ticket? : Int = 0,
  census_current? : (Int) -> Int64 = _ => -41L,
  target_cancellation? : Bool = false,
  reuse_proven_task_material? : Bool = false,
  reuse_proven_fence_rows? : Bool = false,
) -> Result[Unit, Int] {
  if catalog_status != 1 {
    return Err(-41)
  }
  // The same initial admission proved the selected Run, policy and binding.
  // Rebind that exact snapshot before any original work is allowed to extend.
  let prove_reader = () => {
    if census_ticket <= 0 {
      return Ok(false)
    }
    match census_current(census_ticket) {
      0L => Ok(false)
      1L => Ok(true)
      _ => Err(-41)
    }
  }
  let mut same_material_reader = false
  let prove_task_material = if reuse_proven_task_material && census_ticket > 0 {
    Some(() => {
      match prove_reader() {
        Ok(same) => {
          same_material_reader = same
          Ok(same)
        }
        Err(code) => Err(code)
      }
    })
  } else {
    None
  }
  match
    @host.reobserve_client_saved_submission_original(
      retained.snapshot,
      read_identity.unwrap_or(read),
      read_task_slots~,
      prove_task_material~,
    ) {
    Err(code) => return Err(code)
    Ok(None) => return Err(-32)
    Ok(Some(_)) => ()
  }
  // The caller has already checked cancellation in this exact export.
  // Only the original physical Owner can prove uninterrupted readership.
  // A positive material proof is followed only by the return of the same
  // original from Common, with no physical callback between the checks.
  let same = if same_material_reader {
    true
  } else {
    match prove_reader() {
      Ok(same) => same
      Err(code) => return Err(code)
    }
  }
  if !same {
    let audit = () => @host.inspect_client_cancellation_journal_inventory_with_run_identity(
        1024,
        scan,
        read,
        (row, identity) => {
          submission_run_row_original_with_identity(row, identity).map(record => {
            request: record.request,
            definition: record.definition,
            cancellation_head: record.cancellation_head,
          })
        },
        -31,
      ).map(_ => ())
    match confirm_submission_cancellation(
      Some(retained.snapshot), read, audit, target_cancellation,
    ) {
      Err(code) => return Err(code)
      Ok(_) => ()
    }
  }
  // This use is limited to callbacks of an export that already checked the
  // exact fence rows above its first borrow. An effect ends the proof.
  if same && reuse_proven_fence_rows {
    return Ok(())
  }
  for (table, key, revision, body) in retained.fences {
    match read(table, key) {
      Ok(Some(row)) if row.key == key &&
        row.revision == revision &&
        row.body == body => ()
      Err(code) => return Err(code)
      _ => return Err(-32)
    }
  }
  Ok(())
}

///|
fn validate_saved_result_read(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
  targeted_task_material? : Bool = false,
  task_material_proof? : SavedTaskMaterialProof? = None,
  same_reader_census? : Bool = false,
  reuse_proven_fence_rows? : Bool = false,
  read_only_saved_control? : Bool = false,
) -> Result[Unit, Int] {
  guard record.saved_result is Some(retained) &&
    retained.advances_remaining == 0 &&
    retained.owner is Some(owner) &&
    retained.view is Some(view) else {
    return Err(-32)
  }
  if read_only_saved_control {
    guard record.kind == INCREMENTAL_SAVED_RESULT_KIND else { return Err(-32) }
    return observe_saved_result_run_control(
      value, record, configuration, retained,
    )
  }
  match
    reobserve_saved_result_read(
      value,
      record,
      configuration,
      retained,
      targeted_task_material~,
      task_material_proof~,
      same_reader_census~,
      reuse_proven_fence_rows~,
    ) {
    Err(code) => return Err(code)
    Ok(_) => ()
  }
  if owner.observed_result_read_materials(view, retained.result_name, 16)
    is Err(_) {
    return Err(-32)
  }
  saved_result_read_current(value, record, configuration, retained.result_name)
}

///|
fn close_saved_result_read(
  value : Instance,
  record : StoredSubmissionProjection,
) -> Int {
  guard record.saved_result is Some(retained) else { return 0 }
  if retained.owner is Some(owner) {
    owner.cancel()
    if retained.view is Some(view) {
      if retained.commit_observation {
        if owner.release_observed_commit(view) is Err(_) {
          return -9
        }
        retained.commit_observation = false
      }
      if owner.release_view(view) is Err(_) {
        return -9
      }
      retained.view = None
    }
    retained.owner = None
  }
  retained.source = None
  if retained.policy_capacity is Some(capacity) {
    if @resources.settle_capacity(value.root, capacity) is Err(_) {
      return -4
    }
    retained.policy_capacity = None
  }
  retained.selection = None
  if retained.selection_capacity is Some(capacity) {
    if @resources.settle_capacity(value.root, capacity) is Err(_) {
      return -4
    }
    retained.selection_capacity = None
  }
  if retained.coordinates_capacity is Some(capacity) {
    if @resources.settle_capacity(value.root, capacity) is Err(_) {
      return -4
    }
    retained.coordinates_capacity = None
  }
  record.saved_result = None
  0
}

///|
/// Spend the incremental Saved packet, not its live projection. Pause ready
/// entry across the fallible accounting callbacks. Only successful byte
/// retirement restores readiness, with the same current and Store checks.
fn retire_saved_result_transport(
  value : Instance,
  handle : Int,
  record : StoredSubmissionProjection,
) -> Int {
  guard saved_result_export_parent(value, handle) is Some((actual, saved)) &&
    physical_equal(record, actual) &&
    @buffers.buffer_length(value.pool, record.slot) is Some(_) else {
    return -2
  }
  saved.advances_remaining = -1
  value.copies.remove(handle) |> ignore
  let code = status(
    @buffers.retire_consumed_output_transport(value.pool, record.slot),
  )
  if code == 0 {
    saved.advances_remaining = 0
  }
  code
}
