///|
/// Original input and one same-Store scoped query ticket, not Run or adoption state.
priv struct StoredHostCurrent {
  input : Int
  borrow : Result[@buffers.BufferBorrow, @buffers.BufferIssue]
  slot : @buffers.BufferSlot
  physical : Int
  limit : Int
  store : Ref[Int]
  mut invoked : Bool
  mut closing : Bool
  mut output_closed : Bool
  mut produced : Bool
  mut account : @authorization.AdmittedAccountConfiguration?
  mut account_original : Bytes?
  mut adoption_original : Bytes?
  mut generation : (UInt64, UInt64)?
  mut principal : String?
  mut connection : String?
  mut material : @host.ClientLocalAdoptedHostMaterial[Ref[Int], Int]?
  // Alias only the first genuine row also retained by the original Common
  // material. Later observations never retain another body or copied payload.
  mut original_adoption_row : @host.ClientJournalPhysicalRow?
  mut observed_operation : Int64
}

///|
fn host_current_physical(
  value : Instance,
  record : StoredHostCurrent,
) -> Result[Unit, Int] {
  if value.closing ||
    value.runtime_closing ||
    record.closing ||
    record.output_closed {
    return Err(-5)
  }
  if physical_journal_current(record.physical) != 0 {
    return Err(-41)
  }
  Ok(())
}

///|
// A fresh physical current/fence check plus DATA from this entered Host's
// existing operation. Zero deliberately keeps the complete raw/cleanup path.
fn host_current_checked_operation(
  value : Instance,
  record : StoredHostCurrent,
) -> Result[Int64, Int] {
  host_current_checked_operation_original(
    record,
    () => value.closing || value.runtime_closing,
    () => physical_journal_current_operation(record.physical),
  )
}

///|
// Existing controller with closed production fields exposed to independent
// component tests. These pure ports are not an author/Host permission API.
fn host_current_checked_operation_original(
  record : StoredHostCurrent,
  instance_closed : () -> Bool,
  physical : () -> Int64,
) -> Result[Int64, Int] {
  if instance_closed() ||
    record.closing ||
    record.output_closed {
    record.observed_operation = 0L
    return Err(-5)
  }
  let operation = physical()
  // A returned physical observation cannot revive an Instance/current that
  // retired through that callback. This is the same late-fence refusal code.
  if instance_closed() || record.closing || record.output_closed {
    record.observed_operation = 0L
    return Err(-41)
  }
  if operation < 0L {
    record.observed_operation = 0L
    Err(-41)
  } else {
    Ok(operation)
  }
}

///|
fn host_current_observation_reusable(
  record : StoredHostCurrent,
  operation : Int64,
) -> Bool {
  operation > 0L &&
  record.observed_operation == operation &&
  !record.closing &&
  !record.output_closed &&
  record.material is Some(_) &&
  record.original_adoption_row is Some(_)
}

///|
/// Core selects the singleton namespace/cursor. The trusted Host current port
/// retains original filesystem/settings/epoch/generation and same-Store fences.
/// It cannot return a caller permission boolean or authenticate a malicious Host.
fn host_current_observation(
  value : Instance,
  record : StoredHostCurrent,
) -> Result[@host.ClientLocalAdoptionCurrentObservation[Ref[Int]], Int] {
  // These closed physical functions belong to this SAME retained record and
  // original Instance. No external caller supplies observation reuse ports.
  let current = () => host_current_physical(value, record)
  host_current_observe_original(
    record,
    () => host_current_checked_operation(value, record),
    current,
    cursor => {
      physical_journal_row(
        record.physical,
        current,
        0,
        "client_local_adoption",
        cursor,
      )
    },
    post_original=Some(() => {
      if value.closing || value.runtime_closing {
        Err(-41)
      } else {
        Ok(())
      }
    }),
  )
}

///|
fn host_current_observe_original(
  record : StoredHostCurrent,
  checked_operation : () -> Result[Int64, Int],
  current : () -> Result[Unit, Int],
  select_row : (String) -> Result[@host.ClientJournalPhysicalRow?, Int],
  post_original? : (() -> Result[Unit, Int])? = None,
) -> Result[@host.ClientLocalAdoptionCurrentObservation[Ref[Int]], Int] {
  guard record.account is Some(account) &&
    record.account_original is Some(original) &&
    record.adoption_original is Some(expected) &&
    record.generation is Some(generation) else {
    return Err(-33)
  }
  // Keep the original fields across the physical callback. An equal operation
  // number cannot replace any retained original or revive a retired holder.
  let account_before = record.account
  let original_before = record.account_original
  let adoption_before = record.adoption_original
  let generation_before = record.generation
  let material_before = record.material
  let row_before = record.original_adoption_row
  let operation_before = record.observed_operation
  let store_before = record.store.val
  let principal_before = record.principal
  let connection_before = record.connection
  let invoked_before = record.invoked
  let produced_before = record.produced
  let operation = match checked_operation() {
    Ok(value) => value
    Err(code) => return Err(code)
  }
  if post_original is Some(post) {
    // Only the closed Guest supplies this same-Instance liveness check. There
    // is no physical query, callback or await between it and the DATA below.
    match post() {
      Err(code) => {
        record.observed_operation = 0L
        return Err(code)
      }
      Ok(_) => ()
    }
    if record.closing || record.output_closed ||
      !physical_equal(record.account, account_before) ||
      !physical_equal(record.account_original, original_before) ||
      !physical_equal(record.adoption_original, adoption_before) ||
      record.generation != generation_before ||
      !physical_equal(record.material, material_before) ||
      !physical_equal(record.original_adoption_row, row_before) ||
      record.observed_operation != operation_before ||
      record.store.val != store_before ||
      record.principal != principal_before ||
      record.connection != connection_before ||
      record.invoked != invoked_before || record.produced != produced_before {
      record.observed_operation = 0L
      return Err(-41)
    }
  }
  if host_current_observation_reusable(record, operation) &&
    record.original_adoption_row is Some(row) {
    // Common still compares full original row/account/generation and decides
    // each protected operation. Only immutable already-admitted DATA is reused.
    if post_original is Some(_) {
      return Ok(
        @host.Observed(record.store, account, original, row, generation),
      )
    }
    // Raw/test callbacks keep their independent second physical sample. They
    // may change only on that call and cannot supply the closed Guest proof.
    match checked_operation() {
      Ok(after) if after == operation =>
        return Ok(
          @host.Observed(record.store, account, original, row, generation),
        )
      _ => {
        record.observed_operation = 0L
        return Err(-41)
      }
    }
  }
  record.observed_operation = 0L
  let row = match select_row("") {
    Ok(None) => return Ok(@host.NotAdopted)
    Ok(Some(row)) => row
    Err(code) => return Err(code)
  }
  if row.key != "adoption" || row.revision != 0L || row.body != expected {
    return Err(-32)
  }
  match select_row("adoption") {
    Ok(None) => ()
    Ok(Some(_)) => return Err(-32)
    Err(code) => return Err(code)
  }
  match current() {
    Err(code) => return Err(code)
    Ok(_) => ()
  }
  let after = match checked_operation() {
    Ok(value) => value
    Err(code) => return Err(code)
  }
  if after != operation {
    return Err(-41)
  }
  // The initial constructor and its Common material share this SAME actual
  // immutable row. Keep only that alias under the original input/current
  // lifetime; repeated frames cannot add another retained payload.
  if record.original_adoption_row is None {
    record.original_adoption_row = Some(row)
  }
  record.observed_operation = operation
  Ok(@host.Observed(record.store, account, original, row, generation))
}

///|
fn host_current_issue(issue : @host.ClientLocalAdoptedCurrentIssue[Int]) -> Int {
  match issue {
    @host.Physical(code) => code
    @host.NotAdopted => -35
    @host.CommitUnknown => -41
    @host.InvalidOriginal | @host.ForeignStore | @host.ChangedCurrent => -32
    @host.Scope(_) => -31
  }
}

///|
pub fn reserve_host_current(
  nonce : Int64,
  input : Int,
  physical_ticket : Int,
  physical_copy_bytes : Int64,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.copies.get(input) is Some((input_slot, physical)) else {
    return -2
  }
  if value.closing || value.runtime_closing {
    return -5
  }
  if physical_ticket <= 0 ||
    value.next_handle == 2147483647 ||
    value.copies.values().any(pair => pair.1 == physical_ticket) ||
    value.workspaces.values().any(pair => pair.0 == physical_ticket) ||
    value.native_commands
    .values()
    .any(command => command.physical_ticket == physical_ticket) ||
    value.result_chunks
    .values()
    .any(chunk => chunk.physical_ticket == physical_ticket) {
    return -3
  }
  guard @buffers.buffer_length(value.pool, input_slot) is Some(input_length) &&
    input_length <= 1048576 - 256 else {
    return -31
  }
  // Output repeats the input's account string plus two fixed 71-byte CIDs.
  // The original serialized input plus 256 bytes bounds that output without
  // parsing/copying first. Separate physical holding covers both raw row copies.
  let limit = input_length + 256
  let slot = match
    @buffers.reserve_output_buffer(value.pool, limit, physical_copy_bytes, () => {
      physical_input_cleanup(physical_ticket) == 0
    }) {
    Ok(value) => value
    Err(issue) => return issue_code(issue)
  }
  let handle = value.next_handle
  let borrow = @buffers.borrow_buffer(value.pool, input_slot, () => {
    physical_reader_stop(physical, handle) == 0
  })
  value.host_currents[handle] = {
    input,
    borrow,
    slot,
    physical: physical_ticket,
    limit,
    store: Ref(handle),
    invoked: false,
    closing: false,
    output_closed: false,
    produced: false,
    account: None,
    account_original: None,
    adoption_original: None,
    generation: None,
    principal: None,
    connection: None,
    material: None,
    original_adoption_row: None,
    observed_operation: 0L,
  }
  value.copies[handle] = (slot, physical_ticket)
  value.next_handle += 1
  handle
}

///|
/// Bind actual already-committed adoption, never initialize or repair it.
pub fn bind_host_current(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.host_currents.get(handle) is Some(record) else {
    return -2
  }
  if record.material is Some(_) {
    return validate_host_current(nonce, handle)
  }
  if record.invoked {
    return -33
  }
  match host_current_physical(value, record) {
    Ok(_) => ()
    Err(code) => return code
  }
  record.invoked = true
  let borrow = match record.borrow {
    Ok(value) => value
    Err(issue) => return issue_code(issue)
  }
  guard input_cursor(value, borrow.slot) is Some(cursor) &&
    @decode.closed_object(cursor, [
      "account", "adoption", "device", "inode", "principal", "connection",
    ])
    is Ok(object) &&
    required_text(object, "account") is Some(account_wire) &&
    required_text(object, "adoption") is Some(adoption_wire) &&
    required_text(object, "device") is Some(device_wire) &&
    required_text(object, "inode") is Some(inode_wire) &&
    required_text(object, "principal") is Some(principal) &&
    required_text(object, "connection") is Some(connection) &&
    payload_physical_uint64(device_wire) is Some(device) &&
    payload_physical_uint64(inode_wire) is Some(inode) &&
    @authorization.admit_account_configuration_json(account_wire) is Ok(account) else {
    return -31
  }
  record.account = Some(account)
  record.account_original = Some(@utf8.encode(account_wire))
  record.adoption_original = Some(@utf8.encode(adoption_wire))
  record.generation = Some((device, inode))
  record.principal = Some(principal)
  record.connection = Some(connection)
  match
    @host.bind_client_local_adopted_host_material(record.store, () => {
      host_current_observation(value, record)
    }) {
    Ok(material) => {
      record.material = Some(material)
      0
    }
    Err(issue) => host_current_issue(issue)
  }
}

///|
pub fn validate_host_current(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.host_currents.get(handle) is Some(record) &&
    record.material is Some(material) else {
    return -33
  }
  match @host.client_local_adopted_current_account(material, record.store) {
    Ok(_) => 0
    Err(issue) => host_current_issue(issue)
  }
}

///|
/// Project original current scope metadata. It is neither Account Allow,
/// execution/read permission, Host adoption nor durable acknowledgement.
pub fn produce_host_current(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.host_currents.get(handle) is Some(record) &&
    record.material is Some(material) &&
    record.account_original is Some(original) &&
    record.principal is Some(principal) &&
    record.connection is Some(connection) else {
    return -33
  }
  let account = match
    @host.client_local_adopted_current_account(material, record.store) {
    Ok(value) => value
    Err(issue) => return host_current_issue(issue)
  }
  let scope = match
    @host.client_local_adopted_authority_scope_body(
      material,
      record.store,
      principal,
      connection,
    ) {
    Ok(value) => value
    Err(issue) => return host_current_issue(issue)
  }
  if record.produced {
    return 0
  }
  let wire = try {
    let writer = @encode.writer(record.limit, 16, 2)
    @encode.begin_object(writer)
    @encode.key(writer, "account")
    @encode.string_value(writer, @utf8.decode(original))
    @encode.key(writer, "account_configuration_cid")
    @encode.string_value(writer, account.configuration_cid())
    @encode.key(writer, "authority_scope_cid")
    @encode.string_value(writer, "sha256:" + @sha.hex(scope))
    @encode.end_object(writer)
    @utf8.encode(@encode.finish(writer))
  } catch {
    _ => return -34
  }
  let result = status(
    @buffers.supply_buffer_output(value.pool, record.slot, wire),
  )
  if result == 0 {
    record.produced = true
  }
  result
}

///|
pub fn host_current_length(nonce : Int64, handle : Int) -> Int {
  let checked = validate_host_current(nonce, handle)
  if checked != 0 {
    return checked
  }
  guard selected(nonce) is Some(value) &&
    value.host_currents.get(handle)
    is Some({ produced: true, output_closed: false, slot, .. }) else {
    return -33
  }
  match @buffers.buffer_length(value.pool, slot) {
    Some(length) => length
    None => -33
  }
}

///|
pub fn close_host_current(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.host_currents.get(handle) is Some(record) else {
    return -2
  }
  record.closing = true
  record.observed_operation = 0L
  if value.run_configurations
    .values()
    .any(configuration => configuration.host_current == Some(handle)) {
    return -9
  }
  if !record.output_closed {
    let result = status(@buffers.close_buffer(value.pool, record.slot))
    if result != 0 {
      return result
    }
    record.output_closed = true
  }
  let result = match record.borrow {
    Ok(borrow) => status(@buffers.return_buffer_borrow(value.pool, borrow))
    Err(_) => 0
  }
  if result == 0 {
    value.host_currents.remove(handle) |> ignore
    value.copies.remove(handle) |> ignore
  }
  result
}
