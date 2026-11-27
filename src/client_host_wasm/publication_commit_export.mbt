///|
priv enum PublicationCommitExportProjection {
  Candidate
  Material(Int, Int)
  IndexKey
  Schema(Int, Int)
  ObservedIndex(Int)
  ObservedRunState(Int)
  SDKMeasuredRunState(Int, Int, Int, Bool)
  SDKReadOriginal(Int, Int, Int, Int)
  SDKReadEvidence(Int, Int, Int)
  SDKReadGrant(Int, Int, Int)
  SDKReadEvidenceDecision(Int, Int)
  SDKReadDeliveryStorage(Int, Int)
  SDKReadDeliveryBody(Int)
  SDKReadDeliveryLookup(Int, Int)
  SDKLiveReturnControl(Int)
  SDKPayloadChunk(Int, Int, Int)
  SDKPayloadReceipt(Int)
  SDKTerminalStorage(Int, SDKTerminalPhase)
  InspectedReference(Int)
} derive(Eq)

///|
priv enum SDKTerminalPhase {
  Staged
  Validated
  Committed
} derive(Eq)

///|
/// Borrow the original validator's accepted candidate, never Store authority.
/// The parent retains the original commit input and completed Result custody.
priv struct StoredPublicationCommitExport {
  publication : Int
  slot : @buffers.BufferSlot
  mut projection : PublicationCommitExportProjection?
  mut invoked : Bool
  mut pending : Bool
  mut produced : Bool
  mut closing : Bool
  mut output_closed : Bool
  mut state_borrow : @buffers.BufferBorrow?
  mut sdk_delivery_prepared : (
    Int,
    @local_run.LocalSDKReadDeliveryPreparation,
    Bool,
  )?
  mut sdk_delivery_first : @local_run.LocalSDKReadDeliveryPreparation?
  mut sdk_payload_outcome : Result[@local_run.LocalSDKPayloadEncoding, Int]?
  mut sdk_payload_tick_borrow : @buffers.BufferBorrow?
  mut sdk_payload_clock_input : Int?
  mut sdk_payload_invoked : Bool
  mut sdk_payload_parent : Int?
  mut sdk_payload_confirmed : Int64?
  mut sdk_payload_record : (Int, Int, Int)?
  mut sdk_payload_terminal : @local_run.LocalSDKDeliveryTerminal?
  mut sdk_run_state_update : @host.ClientSavedRunStateUpdate?
  mut sdk_run_state_update_capacity : @resources.CapacityReservation?
  mut sdk_transport_capacity : @resources.CapacityReservation?
}

///|
pub fn reserve_publication_commit_export(
  nonce : Int64,
  publication : Int,
  physical_ticket : Int,
  physical_copy_bytes : Int64,
) -> Int {
  reserve_bounded_publication_commit_export(
    nonce, publication, physical_ticket, 1048576, physical_copy_bytes,
  )
}

///|
/// The same output Owner admits a smaller physical field bound. This is DATA,
/// not a read grant or a larger parent allowance; production still checks the
/// original view/current and refuses a wire larger than this reserved buffer.
pub fn reserve_bounded_publication_commit_export(
  nonce : Int64,
  publication : Int,
  physical_ticket : Int,
  max_wire_bytes : Int,
  physical_copy_bytes : Int64,
) -> Int {
  if max_wire_bytes < 1 || max_wire_bytes > 1048576 {
    return -3
  }
  guard selected(nonce) is Some(value) else { return -2 }
  let live = value.publications.get(publication)
    is Some(
      {
        closing: false,
        commit_finished: true,
        commit: Some(_),
        commit_view: Some(_),
        commit_index: Some(_),
        ..
      }
    )
  if !live && saved_result_export_parent(value, publication) is None {
    return -2
  }
  if value.closing || value.runtime_closing {
    return -5
  }
  if physical_ticket <= 0 ||
    value.next_handle == 2147483647 ||
    value.copies.values().any(pair => pair.1 == physical_ticket) ||
    value.native_commands
    .values()
    .any(command => command.physical_ticket == physical_ticket) ||
    value.result_chunks
    .values()
    .any(chunk => chunk.physical_ticket == physical_ticket) ||
    value.workspaces.values().any(pair => pair.0 == physical_ticket) {
    return -3
  }
  let slot = match
    @buffers.reserve_output_buffer(
      value.pool,
      max_wire_bytes,
      physical_copy_bytes,
      () => physical_input_cleanup(physical_ticket) == 0,
    ) {
    Ok(slot) => slot
    Err(issue) => return issue_code(issue)
  }
  let handle = value.next_handle
  value.commit_exports[handle] = {
    publication,
    slot,
    projection: None,
    invoked: false,
    pending: false,
    produced: false,
    closing: false,
    output_closed: false,
    state_borrow: None,
    sdk_delivery_prepared: None,
    sdk_delivery_first: None,
    sdk_payload_outcome: None,
    sdk_payload_tick_borrow: None,
    sdk_payload_clock_input: None,
    sdk_payload_invoked: false,
    sdk_payload_parent: None,
    sdk_payload_confirmed: None,
    sdk_payload_record: None,
    sdk_payload_terminal: None,
    sdk_run_state_update: None,
    sdk_run_state_update_capacity: None,
    sdk_transport_capacity: None,
  }
  value.copies[handle] = (slot, physical_ticket)
  value.next_handle += 1
  handle
}

///|
/// Every projection retains the original nominal view and rechecks current
/// Run/Source access. These facts do not grant current publisher authority.
fn publication_commit_export_view(
  value : Instance,
  parent : StoredPublication,
  account : @authorization.AdmittedAccountConfiguration,
) -> Result[
  (
    @publication.PublicationCommitPreparation,
    @publication.PublicationCommitReadView,
  ),
  Int,
] {
  checked_publication_commit_view(value, parent, () => {
    if parent.file is Some(file) {
      // Each projected field reobserves the selected original Run, Task and
      // locator. The physical precommit still checks the complete journal
      // in this same writer before the Store can commit.
      let status = sdk_file_capture_publication_current(
        value,
        parent,
        file,
        account,
        selected_file_projection=true,
      )
      if status == 0 {
        Ok(())
      } else {
        Err(status)
      }
    } else if publication_current(value, parent, account) {
      Ok(())
    } else {
      Err(-32)
    }
  })
}

///|
/// Borrow the same completed view only inside a caller's original current
/// check. The check's selected purpose cannot change or advance the view.
fn checked_publication_commit_view(
  value : Instance,
  parent : StoredPublication,
  current : () -> Result[Unit, Int],
) -> Result[
  (
    @publication.PublicationCommitPreparation,
    @publication.PublicationCommitReadView,
  ),
  Int,
] {
  if value.closing || value.runtime_closing || parent.closing {
    return Err(-5)
  }
  guard parent.commit_finished &&
    !parent.commit_failed &&
    !parent.pending &&
    parent.commit is Some(commit) &&
    parent.commit_view is Some(view) &&
    parent.commit_index is Some(index_entry) else {
    return Err(-32)
  }
  current().bind(_ => {
    if commit.view_contract(view, 7) is Ok(original_index) &&
      physical_equal(original_index, index_entry) {
      Ok((commit, view))
    } else {
      Err(-32)
    }
  })
}

///|
/// Count original references, without copying contracts or observing a Store.
pub fn publication_commit_export_count(
  nonce : Int64,
  publication : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.publications.get(publication) is Some(parent) &&
    value.run_configurations.get(current_configuration) is Some(current) else {
    return -2
  }
  let (commit, view) = match
    publication_commit_export_view(value, parent, current.account) {
    Ok(original) => original
    Err(code) => return code
  }
  match commit.view_count(view) {
    Ok(count) => count
    Err(_) => -32
  }
}

///|
/// Count original completed Result occurrences after the same nominal Done
/// view/current-account check. This is not a durable Store or admitted Run count.
pub fn publication_commit_export_result_count(
  nonce : Int64,
  publication : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.publications.get(publication) is Some(parent) &&
    value.run_configurations.get(current_configuration) is Some(current) else {
    return -2
  }
  match publication_commit_export_view(value, parent, current.account) {
    Ok(_) => publication_result_count(parent)
    Err(code) => code
  }
}

///|
fn publication_storage_extent(
  identity : String,
  wire : String,
) -> Result[String, Int] {
  guard @scalar.utf8_length_within(wire, 1048576) is Some(bytes) && bytes > 0 else {
    return Err(-4)
  }
  Ok(identity + ":" + bytes.to_string())
}

///|
/// Copy one original field into the existing accounted output.
/// Fields 0–3 return the exact UTF-8 wire, name, identity field and identity.
/// Field 4 returns the original 71-byte CID, a colon and its wire capacity as decimal
/// ASCII, measured from the same immutable canonical wire under its existing
/// limit. No contract is copied or re-encoded to obtain the byte count.
pub fn produce_publication_commit_material(
  nonce : Int64,
  handle : Int,
  current_configuration : Int,
  ordinal : Int,
  field : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.commit_exports.get(handle) is Some(record) &&
    value.publications.get(record.publication) is Some(parent) &&
    value.run_configurations.get(current_configuration) is Some(current) else {
    return -2
  }
  if record.closing {
    return -5
  }
  let (commit, view) = match
    publication_commit_export_view(value, parent, current.account) {
    Ok(original) => original
    Err(code) => return code
  }
  if ordinal < 0 || field < 0 || field > 4 {
    return -3
  }
  let projection = PublicationCommitExportProjection::Material(ordinal, field)
  if record.projection is Some(original) && original != projection {
    return -33
  }
  if record.produced {
    return 0
  }
  if record.invoked || record.pending {
    return -33
  }
  let contract = match commit.view_contract(view, ordinal) {
    Ok(contract) => contract
    Err(_) => return -32
  }
  let text = match field {
    0 => @publication.publication_contract_json(contract)
    1 => @publication.publication_contract_name(contract)
    2 => @publication.publication_contract_identity_field(contract)
    3 => @publication.publication_contract_identity(contract)
    _ =>
      match
        publication_storage_extent(
          @publication.publication_contract_identity(contract),
          @publication.publication_contract_json(contract),
        ) {
        Ok(text) => text
        Err(code) => return code
      }
  }
  record.projection = Some(projection)
  record.invoked = true
  record.pending = true
  let result = status(
    @buffers.supply_buffer_output(value.pool, record.slot, @utf8.encode(text)),
  )
  record.pending = false
  if result == 0 {
    record.produced = true
  }
  result
}

///|
/// Copy the actually inspected stored index, never the original candidate.
/// Current publisher is checked again; this projection is not Store ACK.
/// Field 4 describes the same admitted original used by the wire field.
pub fn produce_publication_observed_index(
  nonce : Int64,
  handle : Int,
  current_configuration : Int,
  field : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.commit_exports.get(handle) is Some(record) &&
    value.publications.get(record.publication) is Some(parent) &&
    value.run_configurations.get(current_configuration) is Some(current) else {
    return -2
  }
  if record.closing || parent.observation_closing || parent.lookup_closing {
    return -5
  }
  match publication_commit_export_view(value, parent, current.account) {
    Err(code) => return code
    Ok(_) => ()
  }
  guard parent.observation_checked &&
    !parent.observation_failed &&
    parent.observation_index is Some(index) &&
    parent.observation_publisher is Some(publisher) else {
    return -32
  }
  if field < 0 || field > 4 {
    return -3
  }
  let auth = publication_observation_publisher(
    value,
    parent,
    publisher,
    current_configuration,
    Some(index),
  )
  if auth != 0 {
    return auth
  }
  let projection = PublicationCommitExportProjection::ObservedIndex(field)
  if record.projection is Some(original) && original != projection {
    return -33
  }
  if record.produced {
    return 0
  }
  if record.invoked || record.pending {
    return -33
  }
  let text = match field {
    0 => @publication.publication_contract_json(index)
    1 => @publication.publication_contract_name(index)
    2 => @publication.publication_contract_identity_field(index)
    3 => @publication.publication_contract_identity(index)
    _ =>
      match
        publication_storage_extent(
          @publication.publication_contract_identity(index),
          @publication.publication_contract_json(index),
        ) {
        Ok(text) => text
        Err(code) => return code
      }
  }
  record.projection = Some(projection)
  record.invoked = true
  record.pending = true
  let result = status(
    @buffers.supply_buffer_output(value.pool, record.slot, @utf8.encode(text)),
  )
  record.pending = false
  if result == 0 {
    record.produced = true
  }
  result
}

///|
/// Borrow one original stored request/attempt reference. This does not perform
/// full-chain validation or grant authority to read a different Store/scope.
pub fn produce_publication_lookup_reference(
  nonce : Int64,
  handle : Int,
  current_configuration : Int,
  field : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.commit_exports.get(handle) is Some(record) &&
    value.publications.get(record.publication) is Some(parent) &&
    value.run_configurations.get(current_configuration) is Some(current) else {
    return -2
  }
  if record.closing || parent.lookup_closing {
    return -5
  }
  if field < 0 || field > 1 {
    return -3
  }
  let (commit, view) = match
    publication_commit_export_view(value, parent, current.account) {
    Ok(original) => original
    Err(code) => return code
  }
  guard !parent.lookup_failed &&
    parent.lookup_input is Some(_) &&
    parent.lookup_borrow is Some(_) &&
    parent.lookup_index is Some(index) &&
    parent.lookup_identity is Some(identity) &&
    parent.lookup_publisher is Some(publisher) else {
    return -32
  }
  let auth = publication_observation_publisher(
    value,
    parent,
    publisher,
    current_configuration,
    None,
  )
  if auth != 0 {
    return auth
  }
  let projection = PublicationCommitExportProjection::InspectedReference(field)
  if record.projection is Some(original) && original != projection {
    return -33
  }
  if record.produced {
    return 0
  }
  if record.invoked || record.pending {
    return -33
  }
  let text = match
    commit.view_inspected_index_reference(view, identity, index, field) {
    Ok(text) => text
    Err(_) => return -32
  }
  record.projection = Some(projection)
  record.invoked = true
  record.pending = true
  let result = status(
    @buffers.supply_buffer_output(value.pool, record.slot, @utf8.encode(text)),
  )
  record.pending = false
  if result == 0 {
    record.produced = true
  }
  result
}

///|
/// Project the existing Owner's scoped key from the original validated index.
/// This is a physical address, not publisher permission or a durable ACK.
pub fn produce_publication_commit_index_key(
  nonce : Int64,
  handle : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.commit_exports.get(handle) is Some(record) &&
    value.publications.get(record.publication) is Some(parent) &&
    value.run_configurations.get(current_configuration) is Some(current) else {
    return -2
  }
  if record.closing {
    return -5
  }
  let (commit, view) = match
    publication_commit_export_view(value, parent, current.account) {
    Ok(original) => original
    Err(code) => return code
  }
  if record.projection is Some(original) && original != IndexKey {
    return -33
  }
  if record.produced {
    return 0
  }
  if record.invoked || record.pending {
    return -33
  }
  let index_entry = match commit.view_contract(view, 7) {
    Ok(contract) => contract
    Err(_) => return -32
  }
  let key = match
    @publication.publication_index_storage_key(index_entry, 32768, 256, 16) {
    Ok(key) => key
    Err(_) => return -32
  }
  record.projection = Some(IndexKey)
  record.invoked = true
  record.pending = true
  let result = status(
    @buffers.supply_buffer_output(value.pool, record.slot, @utf8.encode(key)),
  )
  record.pending = false
  if result == 0 {
    record.produced = true
  }
  result
}

///|
/// Copy one schema field from the same original completed Result receipt.
/// Schema index follows the original preflight inventory, not contract ordinal.
/// Field 2 measures the original schema wire and returns its CID and size.
/// The existing buffer owns allocation/cleanup; no schema is reconstructed.
pub fn produce_publication_commit_schema(
  nonce : Int64,
  handle : Int,
  current_configuration : Int,
  result : Int,
  field : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.commit_exports.get(handle) is Some(record) &&
    value.publications.get(record.publication) is Some(parent) &&
    value.run_configurations.get(current_configuration) is Some(current) else {
    return -2
  }
  if record.closing {
    return -5
  }
  match publication_commit_export_view(value, parent, current.account) {
    Err(code) => return code
    Ok(_) => ()
  }
  if result < 0 ||
    result >= publication_result_count(parent) ||
    field < 0 ||
    field > 2 {
    return -3
  }
  guard value.publication_preflights.get(parent.preflight)
    is Some({ closing: false, .. } as preflight) else {
    return -32
  }
  let projection = PublicationCommitExportProjection::Schema(result, field)
  if record.projection is Some(original) && original != projection {
    return -33
  }
  // Recheck the original receipt even when this output was produced earlier.
  fn schema(
    selected : @local_run.LocalResultSchemaField,
  ) -> Result[String, Int] {
    match preflight.origin {
      ComputePublicationPreflight({ prepared: Some(original), .. }) =>
        @local_run.local_preflight_result_schema_field(
          original,
          result,
          parent.publications[result],
          current.account,
          selected,
        ).map_err(_ => -32)
      FilePublicationPreflight(file) =>
        with_sdk_file_payload_result(
          value,
          parent,
          file,
          result,
          current.account,
          (original, row, recheck) => {
            @local_run.local_captured_task_result_schema_field(
              original, result, row, selected, recheck,
            )
          },
        )
      SavedEffectPublicationPreflight({ prepared: Some(original), .. }) =>
        match original.result_schema(result, selected is Wire) {
          Some(wire) => Ok(wire)
          None => Err(-32)
        }
      _ => Err(-32)
    }
  }
  let text = match schema(if field == 1 { Wire } else { Identity }) {
    Ok(text) => text
    Err(code) => return code
  }
  if record.produced {
    return 0
  }
  if record.invoked || record.pending {
    return -33
  }
  let text = if field == 2 {
    let wire = match schema(Wire) {
      Ok(wire) => wire
      Err(code) => return code
    }
    match publication_storage_extent(text, wire) {
      Ok(descriptor) => descriptor
      Err(code) => return code
    }
  } else {
    text
  }
  record.projection = Some(projection)
  record.invoked = true
  record.pending = true
  let result = status(
    @buffers.supply_buffer_output(value.pool, record.slot, @utf8.encode(text)),
  )
  record.pending = false
  if result == 0 {
    record.produced = true
  }
  result
}

///|
/// Return exact Core contract bytes after full-chain validation and current
/// Run/Source access. A Client still needs separate current publisher authority
/// and actual physical Store acceptance before reporting a durable commit.
pub fn produce_publication_commit_export(
  nonce : Int64,
  handle : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.commit_exports.get(handle) is Some(record) &&
    value.publications.get(record.publication) is Some(parent) &&
    value.run_configurations.get(current_configuration) is Some(current) else {
    return -2
  }
  if record.closing {
    return -5
  }
  let (commit, view) = match
    publication_commit_export_view(value, parent, current.account) {
    Ok(original) => original
    Err(code) => return code
  }
  if record.projection is Some(original) && original != Candidate {
    return -33
  }
  if record.produced {
    return 0
  }
  if record.invoked || record.pending {
    return -33
  }
  record.projection = Some(Candidate)
  record.invoked = true
  record.pending = true
  // Read the original completed validation chain, never recreate equivalent
  // contracts from the preflight or caller JSON. The parent retains this view
  // until every output child and original physical borrow has stopped.
  let request = match commit.view_contract(view, 5) {
    Ok(contract) => contract
    Err(_) => {
      record.pending = false
      return -32
    }
  }
  let attempt = match commit.view_contract(view, 6) {
    Ok(contract) => contract
    Err(_) => {
      record.pending = false
      return -32
    }
  }
  let index_entry = match commit.view_contract(view, 7) {
    Ok(contract) => contract
    Err(_) => {
      record.pending = false
      return -32
    }
  }
  let writer = @encode.writer(1048576, 8, 1) catch {
    _ => {
      record.pending = false
      return -34
    }
  }
  let wire = try {
    @encode.begin_object(writer)
    for
      (name, contract) in [
        ("request", request),
        ("attempt", attempt),
        ("index_entry", index_entry),
      ] {
      @encode.key(writer, name)
      @encode.string_value(
        writer,
        @publication.publication_contract_json(contract),
      )
    }
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => {
      record.pending = false
      return -34
    }
  }
  let result = status(
    @buffers.supply_buffer_output(value.pool, record.slot, @utf8.encode(wire)),
  )
  record.pending = false
  if result == 0 {
    record.produced = true
  }
  result
}

///|
pub fn publication_commit_export_length(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.commit_exports.get(handle) is Some(record) else {
    return -2
  }
  if !record.produced || record.closing || record.output_closed {
    return -33
  }
  match @buffers.buffer_length(value.pool, record.slot) {
    Some(length) => length
    None => -33
  }
}

///|
pub fn retire_publication_sdk_delivery_output(
  nonce : Int64,
  handle : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.commit_exports.get(handle) is Some(record) else {
    return -2
  }
  if record.pending ||
    record.closing ||
    !record.produced ||
    record.sdk_delivery_first is None ||
    !(record.projection is Some(SDKReadDeliveryStorage(_, _))) {
    return -33
  }
  if record.output_closed {
    return 0
  }
  // The same Buffer Owner retires only the transport. The actual first
  // preparation and original request loan survive until full export close.
  let code = status(@buffers.close_buffer(value.pool, record.slot))
  if code == 0 {
    record.output_closed = true
    value.copies.remove(handle) |> ignore
  }
  code
}

///|
/// This terminal entrance is called by the trusted serialized Host only
/// after synchronous unwind. Each original child still needs its physical
/// close and reservation settlement.
pub fn begin_publication_sdk_delivery_preparation_cleanup(
  nonce : Int64,
  publication : Int,
  first_handle : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.publications.contains(publication) else {
    return -2
  }
  retire_interrupted_sdk_delivery_preparation(value, publication, first_handle)
}

///|
fn retire_interrupted_sdk_delivery_preparation(
  value : Instance,
  publication : Int,
  first_handle : Int,
) -> Int {
  guard value.commit_exports.get(first_handle) is Some(first) &&
    first.publication == publication else {
    return -2
  }
  match first.projection {
    None if !first.pending => return 0
    Some(SDKReadDeliveryStorage(_, _)) => ()
    _ => return -2
  }
  // The emitted holder can own later payload/clock calls. Their pending
  // latch is outside this interrupted-construction entrance.
  if first.produced || first.sdk_delivery_first is Some(_) {
    return if first.pending { -33 } else { 0 }
  }
  value.closing = true
  first.closing = true
  first.pending = false
  for child in value.commit_exports.values() {
    if child.publication == publication &&
      child.sdk_payload_parent == Some(first_handle) &&
      child.projection == Some(SDKReadDeliveryBody(first_handle)) {
      child.closing = true
      child.pending = false
    }
  }
  0
}

///|
pub fn close_publication_commit_export(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.commit_exports.get(handle) is Some(record) else {
    return -2
  }
  record.closing = true
  if record.pending {
    return -33
  }
  if value.commit_exports
    .values()
    .any(child => child.sdk_payload_parent == Some(handle)) {
    return -33
  }
  if !record.output_closed {
    let result = status(@buffers.close_buffer(value.pool, record.slot))
    if result != 0 {
      return result
    }
    record.output_closed = true
  }
  if record.sdk_payload_tick_borrow is Some(borrow) {
    let result = status(@buffers.return_buffer_borrow(value.pool, borrow))
    if result != 0 {
      return result
    }
    record.sdk_payload_tick_borrow = None
  }
  if record.sdk_payload_outcome is Some(Ok(encoding)) {
    encoding.cancel_frames()
  }
  record.sdk_payload_outcome = None
  if record.state_borrow is Some(borrow) {
    let result = status(@buffers.return_buffer_borrow(value.pool, borrow))
    if result != 0 {
      return result
    }
    record.state_borrow = None
  }
  if record.sdk_transport_capacity is Some(capacity) {
    match @resources.settle_capacity(value.root, capacity) {
      Err(_) => return -4
      Ok(_) => record.sdk_transport_capacity = None
    }
  }
  record.sdk_run_state_update = None
  if record.sdk_run_state_update_capacity is Some(capacity) {
    match @resources.settle_capacity(value.root, capacity) {
      Err(_) => return -4
      Ok(_) => record.sdk_run_state_update_capacity = None
    }
  }
  if value.publications.get(record.publication)
    is Some({ file: Some(file), .. }) &&
    file.state_export == Some(handle) {
    file.state_export = None
  }
  value.commit_exports.remove(handle) |> ignore
  value.copies.remove(handle) |> ignore
  0
}

///|
// The exact original output retains this synchronous construction on failure.
fn[T] with_sdk_export_transport_capacity(
  value : Instance,
  output : StoredPublicationCommitExport,
  working : Int64,
  encode : () -> Result[T, Int],
) -> Result[T, Int] {
  guard output.sdk_transport_capacity is None else { return Err(-4) }
  let capacity = match @resources.reserve_capacity(value.root, 0L, working) {
    Ok(capacity) => capacity
    Err(_) => return Err(-4)
  }
  output.sdk_transport_capacity = Some(capacity)
  let result = encode()
  match @resources.settle_capacity(value.root, capacity) {
    Ok(_) => output.sdk_transport_capacity = None
    Err(_) => if result is Ok(_) { return Err(-4) }
  }
  result
}
