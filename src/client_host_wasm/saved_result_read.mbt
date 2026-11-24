///|
/// One read operation's original metadata and input loans, never an executable
/// Run, grant or process cache. Partial validation remains attached to the same
/// output until explicit close; the physical Host owns its snapshot/FD duties.
priv struct StoredSavedResultRead {
  snapshot : @host.ClientSavedSubmissionSnapshot
  result_name : String
  fences : Array[(String, String, Int64, Bytes)]
  mut source : @local_run.LocalSDKReadSource?
  finite : @host.ClientLocalRunPolicyOriginal?
  mut owner : @publication.PublicationCommitPreparation?
  mut view : @publication.PublicationCommitReadView?
  // Absolute value is the original schema plus two. Kind 6 uses 1. A
  // negative sign records the existing observed-commit child.
  mut schema_phase : Int
  // Positive while a phase can advance, zero only after final encoding,
  // and negative once an entered advance can no longer continue.
  mut advances_remaining : Int
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
  let admitted_schema = if record.kind == INCREMENTAL_SAVED_RESULT_KIND {
    match submission_lookup_current(value, record, configuration) {
      Err(code) => return Err(code)
      Ok(_) => ()
    }
    let schema = physical_journal_schema(current.physical)
    if schema != 0 && schema != 1 {
      return Err(-41)
    }
    schema
  } else {
    -1
  }
  let snapshot = match
    observe_submission_lookup(value, record, configuration, admitted_schema~) {
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
  // Durable originals are admitted through their own Owner. Current SDK
  // selections must match them; a later equivalent CID cannot reissue them.
  let finite = match
    @host.admit_client_local_run_policy_original(
      @utf8.encode(policy_wire),
      sdk.profile,
      submitted.reference,
      run.request,
      run.definition,
      sdk.adoption_cid,
      @publication.local_sdk_result_read_selection_cid(sdk.read),
    ) {
    Ok(value) => value
    Err(_) => return Err(-32)
  }
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
  let retained : StoredSavedResultRead = {
    snapshot,
    result_name,
    fences: [],
    source: None,
    finite: Some(finite),
    owner: None,
    view: None,
    schema_phase: admitted_schema + 2,
    advances_remaining: -1,
  }
  // Retain this carrier before the first publication query or fallible advance.
  record.saved_result = Some(retained)
  let read = (table, key) => {
    physical_journal_row(current.physical, check, 1, table, key).bind(row => {
      match row {
        None => Ok(None)
        Some(row) => {
          if row.key != key {
            return Err(-41)
          }
          retained.fences.push((table, key, row.revision, row.body))
          Ok(Some(row.body))
        }
      }
    })
  }
  let owner = match
    @publication.read_stored_effect_free_publication(
      configuration.run_namespace,
      configuration.authority_scope_cid,
      @publication.publication_contract_identity(run.definition),
      read,
      check,
      256,
      8388608,
      262144,
      65536,
      64,
      131072,
    ) {
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
  retained.schema_phase = -retained.schema_phase
  Ok(())
}

///|
// The synchronous adapter can drive the same stages inside its original
// reader. The incremental adapter revalidates every captured original in
// its fresh reader before submitting one finite quantum.
fn advance_saved_result_read(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
  rebind : Bool,
) -> Result[Bool, Int] {
  guard record.saved_result is Some(retained) &&
    retained.owner is Some(owner) &&
    retained.advances_remaining > 0 else {
    return Err(-33)
  }
  let remaining = retained.advances_remaining
  retained.advances_remaining = -1
  if rebind {
    match
      reobserve_saved_result_read(
        value,
        record,
        configuration,
        retained,
        incremental=true,
      ) {
      Err(code) => return Err(code)
      Ok(_) => ()
    }
  }
  let result = if retained.schema_phase < 0 {
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
    if retained.schema_phase < 0 {
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
  if rebind {
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
    configuration.sdk is Some(sdk) else {
    return Err(-33)
  }
  let snapshot = retained.snapshot
  let result_name = retained.result_name
  guard configuration.source_free_result_policy is Some(source_policy) else {
    return Err(-32)
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
      selection=sdk.read,
    ) {
    Ok(value) => value
    Err(_) => return Err(-32)
  }
  retained.source = Some(source)
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
  guard binding is Some(binding) else { return Err(-31) }
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
  let wire = try {
    let writer = @encode.writer(1048576, 32, 1)
    @encode.begin_object(writer)
    for
      (key, text) in [
        ("kind", "result-originals"),
        ("resultOrdinal", result_ordinal.to_string()),
        ("bindingOrdinal", binding_ordinal.to_string()),
        ("resultName", result_name),
        (
          "runDefinitionCid",
          @publication.publication_contract_identity(definition),
        ),
        ("index", @publication.publication_contract_json(materials.index)),
        ("manifest", @publication.publication_contract_json(materials.manifest)),
        (
          "definition",
          @publication.publication_contract_json(materials.definition),
        ),
        ("artifact", @publication.publication_contract_json(materials.artifact)),
        (
          "retention",
          @publication.publication_contract_json(materials.retention),
        ),
        ("binding", @publication.publication_contract_json(binding)),
      ] {
      @encode.key(writer, key)
      @encode.string_value(writer, text)
    }
    @encode.end_object(writer)
    @utf8.encode(@encode.finish(writer))
  } catch {
    _ => return Err(-34)
  }
  match saved_result_read_current(value, record, configuration, result_name) {
    Err(code) => return Err(code)
    Ok(_) => ()
  }
  retained.advances_remaining = 0
  Ok(wire)
}

///|
fn prepare_saved_result_read(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Result[Bytes, Int] {
  match begin_saved_result_read(value, record, configuration) {
    Err(code) => return Err(code)
    Ok(_) => ()
  }
  for _ in 0..<(2 * SAVED_RESULT_ADVANCES_PER_PHASE) {
    match advance_saved_result_read(value, record, configuration, false) {
      Ok(true) => return finish_saved_result_read(value, record, configuration)
      Ok(false) => ()
      Err(code) => return Err(code)
    }
  }
  Err(-34)
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
  match advance_saved_result_read(value, record, configuration, true) {
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
  incremental? : Bool = false,
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
  if incremental {
    let schema = physical_journal_schema(current.physical)
    let read = (table, key) => {
      physical_journal_row(current.physical, check, 1, table, key)
    }
    let scan = (table, cursor) => {
      physical_journal_row(current.physical, check, 0, table, cursor)
    }
    return rebind_saved_result_originals(
      retained,
      schema,
      scan,
      read,
      census_ticket=if same_reader_census { current.physical } else { 0 },
      census_current=physical_journal_current_operation,
      reuse_proven_fence_rows~,
    )
  }
  match
    observe_submission_lookup(
      value,
      record,
      configuration,
      original=Some(retained.snapshot),
    ) {
    Ok(Some(_)) => ()
    Ok(None) => return Err(-42)
    Err(code) => return Err(code)
  }
  for (table, key, revision, body) in retained.fences {
    match physical_journal_row(current.physical, check, 1, table, key) {
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
fn rebind_saved_result_originals(
  retained : StoredSavedResultRead,
  schema : Int,
  scan : (String, String) -> Result[@host.ClientJournalPhysicalRow?, Int],
  read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, Int],
  census_ticket? : Int = 0,
  census_current? : (Int) -> Int64 = _ => -41L,
  reuse_proven_fence_rows? : Bool = false,
) -> Result[Unit, Int] {
  if schema != 0 && schema != 1 {
    return Err(-41)
  }
  if schema != retained.schema_phase.abs() - 2 {
    return Err(-32)
  }
  // The same initial admission proved the selected Run, policy and binding.
  // Rebind that exact snapshot before any original work is allowed to extend.
  match
    @host.reobserve_client_saved_submission_original(retained.snapshot, read) {
    Err(code) => return Err(code)
    Ok(None) => return Err(-32)
    Ok(Some(_)) => ()
  }
  // The caller has already completed the full census in this exact export.
  // Only the original physical Owner can prove uninterrupted readership.
  let same = if census_ticket > 0 {
    match census_current(-census_ticket) {
      0L => false
      1L => true
      _ => return Err(-41)
    }
  } else {
    false
  }
  if !same {
    match
      @host.inspect_client_cancellation_journal_inventory_with_run_identity(
        1024,
        scan,
        read,
        (row, request, definition) => {
          submission_run_row_original_with_identity(
            row,
            Some((request, definition)),
          ).map(record => {
            request: record.request,
            definition: record.definition,
            cancellation_requested: record.cancellation_requested,
          })
        },
        -31,
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
  same_reader_census? : Bool = false,
  reuse_proven_fence_rows? : Bool = false,
) -> Result[Unit, Int] {
  guard record.saved_result is Some(retained) &&
    retained.advances_remaining == 0 &&
    retained.owner is Some(owner) &&
    retained.view is Some(view) else {
    return Err(-32)
  }
  match
    reobserve_saved_result_read(
      value,
      record,
      configuration,
      retained,
      incremental=record.kind == INCREMENTAL_SAVED_RESULT_KIND,
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
fn close_saved_result_read(record : StoredSubmissionProjection) -> Int {
  guard record.saved_result is Some(retained) else { return 0 }
  if retained.owner is Some(owner) {
    owner.cancel()
    if retained.view is Some(view) {
      if retained.schema_phase < 0 &&
        owner.release_observed_commit(view) is Err(_) {
        return -9
      }
      if owner.release_view(view) is Err(_) {
        return -9
      }
    }
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
