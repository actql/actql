///|
const NAMED_SUBMISSION_KIND : Int = 31

///|
const NAMED_SUBMISSION_OUTPUT_LIMIT : Int = 4096

///|
fn observe_named_submission_inventory(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
  current : StoredHostCurrent,
  key : @host.ClientSubmittedNameKey,
) -> Result[@host.ClientSubmittedNameInventory, Int] {
  let check = () => submission_append_current(value, record, configuration)
  if physical_journal_schema(current.physical) != 1 {
    return Err(-41)
  }
  @host.inspect_client_submitted_name_inventory(
    key,
    1024,
    (table, cursor) => {
      physical_journal_row(
        current.physical, check, 0, table, cursor, maximum_body_length=Some(16),
      )
    },
    cursor => {
      physical_journal_row(
        current.physical, check, 2, "client_submission_names", cursor,
        expected_body_length=Some(0),
      ).map(row => row.map(original => (original.key, original.revision)))
    },
    (table, key) => {
      physical_journal_row(
        current.physical, check, 1, table, key,
        maximum_body_length=Some(if table == "client_submission_names" { 16384 } else { 16 }),
      )
    },
    -32,
  )
}

///|
fn named_submission_authenticator(
  current : StoredHostCurrent,
  check : () -> Result[Unit, Int],
  preimage : Bytes,
) -> Result[Bytes, Int] {
  if preimage.length() <= 0 || preimage.length() > 4096 {
    return Err(-31)
  }
  let text = @utf8.decode(preimage) catch { _ => return Err(-31) }
  match
    physical_journal_row(
      current.physical, check, 3, "client_submission_names", text,
      expected_body_length=Some(32),
    ) {
    Ok(Some(row)) if row.key == "authenticator" && row.revision == 0L =>
      Ok(row.body)
    Err(code) => Err(code)
    _ => Err(-32)
  }
}

///|
fn produce_named_submission_observation(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Int {
  guard !record.invoked && !record.output_closed else { return -33 }
  record.invoked = true
  match submission_append_current(value, record, configuration) {
    Ok(_) => ()
    Err(code) => return code
  }
  guard configuration.sdk is Some(_) &&
    configuration.host_current is Some(host_current) &&
    value.host_currents.get(host_current) is Some(current) &&
    record.borrow is Ok(borrow) &&
    @buffers.buffer_length(value.pool, borrow.slot) is Some(bytes) &&
    bytes > 0 &&
    bytes <= 136192 &&
    @host.client_protocol_metadata_construction_bytes(
      bytes, bytes.min(8192).to_int64(),
      copies=2, extra_controls=8192L,
    ) is Some((packet, _)) else {
    return -31
  }
  // The copied input, the complete name row and the small encoder may
  // coexist. The selected submitted row grows this same loan before decode.
  guard @host.client_protocol_metadata_construction_bytes(
      16384 + NAMED_SUBMISSION_OUTPUT_LIMIT, 32L, copies=3,
    ) is Some((name, _)) &&
    @execution.checked_preparation_add_product(packet, name, 1L) is Some(fixed)
  else { return -4 }
  let capacity = match @resources.reserve_capacity(value.root, 0L, fixed) {
    Ok(token) => token
    Err(_) => return -4
  }
  record.append_plan = NamedSubmissionObservation(capacity)
  guard input_cursor(value, borrow.slot) is Some(cursor) &&
    @decode.closed_object(cursor, ["name", "intent"]) is Ok(fields) &&
    required_text(fields, "name") is Some(name) &&
    required_text(fields, "intent") is Some(intent_wire) &&
    @host.prepare_client_submitted_name_key(
      configuration.run_namespace, configuration.tuple.principal, name,
      configuration.authority_scope_cid,
    ) is Ok(key) &&
    @host.prepare_client_submitted_intent(intent_wire, 65536, 8192, 64)
    is Ok(intent) else { return -31 }
  let check = () => submission_append_current(value, record, configuration)
  let inventory = match observe_named_submission_inventory(value, record, configuration, current, key) {
    Ok(inventory) => inventory
    Err(code) => return code
  }
  let named = match @host.inspect_client_submitted_name_selection(
    key,
    inventory,
    configuration.authority_scope_cid,
    intent,
    preimage => named_submission_authenticator(current, check, preimage),
    (table, key) => {
      physical_journal_row(current.physical, check, 1, table, key)
    },
    body => {
      guard @host.client_protocol_metadata_construction_bytes(
          body.length(),
          body.length().min(8192).to_int64(),
          copies=3,
        ) is Some((retained, _)) &&
        @execution.checked_preparation_add_product(fixed, retained, 1L) is Some(peak) &&
        @resources.grow_capacity_reservation(value.root, capacity, 0L, peak) is Ok(_)
      else { return Err(-4) }
      @host.decode_client_submitted_journal_row(body).map_err(_ => -32)
    },
    -32,
  ) {
    Ok(result) => result
    Err(code) => return code
  }
  let wire = match named_submission_observation_wire(named) {
    Ok(wire) => wire
    Err(code) => return code
  }
  match check() {
    Err(code) => return code
    Ok(_) => ()
  }
  let code = status(@buffers.supply_buffer_output(value.pool, record.slot, wire))
  if code == 0 {
    record.produced = true
  }
  code
}

///|
fn named_submission_observation_wire(
  named : @host.ClientSubmittedNameSelection,
) -> Result[Bytes, Int] {
  try {
    let writer = @encode.writer(NAMED_SUBMISSION_OUTPUT_LIMIT, 8, 1)
    @encode.begin_object(writer)
    @encode.key(writer, "kind")
    @encode.string_value(writer, match named {
      @host.NameMissing => "missing"
      @host.NameConflict => "conflict"
      @host.NameHistoryUnavailable => "history_unavailable"
      @host.NameRetained(_) => "retained"
    })
    if named is @host.NameRetained(reference) {
      @encode.key(writer, "reference")
      @encode.string_value(writer, @host.client_submission_reference_record_wire(reference))
    }
    @encode.end_object(writer)
    Ok(@utf8.encode(@encode.finish(writer)))
  } catch {
    _ => Err(-34)
  }
}

///|
const NAMED_SUBMISSION_APPEND_KIND : Int = 32

///|
const NAMED_SUBMISSION_APPEND_LIMIT : Int = 32768

///|
priv struct StoredNamedSubmissionAppend {
  capacity : @resources.CapacityReservation
  mut original : (Int, @host.ClientSubmittedNameKey, String, Int, Int64)?
}

///|
fn prepare_named_submission_append(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Int {
  guard !record.invoked && !record.output_closed else { return -33 }
  record.invoked = true
  match submission_append_current(value, record, configuration) {
    Ok(_) => ()
    Err(code) => return code
  }
  guard configuration.sdk is Some(_) &&
    configuration.host_current is Some(host_current) &&
    value.host_currents.get(host_current) is Some(current) &&
    record.borrow is Ok(loan) &&
    @buffers.buffer_length(value.pool, loan.slot) is Some(size) &&
    size > 0 && size <= 4096 &&
    @host.client_protocol_metadata_construction_bytes(
      size + NAMED_SUBMISSION_APPEND_LIMIT, 16L, copies=2,
      extra_controls=8192L,
    ) is Some((fixed, _)) else { return -31 }
  let capacity = match @resources.reserve_capacity(value.root, 0L, fixed) {
    Ok(token) => token
    Err(_) => return -4
  }
  let held : StoredNamedSubmissionAppend = { capacity, original: None }
  record.append_plan = NamedSubmissionAppend(held)
  guard input_cursor(value, loan.slot) is Some(cursor) &&
    @decode.closed_object(cursor, ["name", "append", "intent_cid"])
    is Ok(fields) &&
    required_text(fields, "name") is Some(name) &&
    required_text(fields, "intent_cid") is Some(intent_cid) &&
    required_int32(fields, "append") is Some(parent) &&
    value.submissions.get(parent) is Some(submission) &&
    submission.configuration == record.configuration &&
    submission.kind == 3 &&
    submission.produced &&
    submission.append_plan is Ready(@host.Append(append)) &&
    @host.prepare_client_submitted_name_key(
      configuration.run_namespace, configuration.tuple.principal, name,
      configuration.authority_scope_cid,
    ) is Ok(key) else { return -31 }
  let (request_id, body, _, _) = @host.client_submitted_journal_append_rows(append)
  guard @host.client_protocol_metadata_construction_bytes(
      body.length(), body.length().min(8192).to_int64(), copies=3,
    ) is Some((decode, _)) &&
    @execution.checked_preparation_add_product(fixed, decode, 1L) is Some(peak) &&
    @resources.grow_capacity_reservation(value.root, capacity, 0L, peak) is Ok(_)
  else { return -4 }
  guard @host.decode_client_submitted_journal_row(body) is Ok(preparing) &&
    preparing.run_admission is None &&
    preparing.preparation_problem is None &&
    @host.client_submission_reference_record_request_id(preparing.reference) == request_id &&
    @host.client_submitted_intent_cid(preparing.intent) == intent_cid &&
    @host.prepare_client_submitted_name_binding(
      key, configuration.authority_scope_cid, request_id, intent_cid,
    ) is Ok(name_binding) &&
    @host.client_submitted_name_authentication_input(name_binding, 4096)
    is Ok(preimage) else { return -32 }
  let inventory = match observe_named_submission_inventory(value, record, configuration, current, key) {
    Ok(value) => value
    Err(code) => return code
  }
  if inventory.original is Some(_) {
    return -45
  }
  if inventory.issued >= 1024 {
    return -4
  }
  let check = () => submission_append_current(value, record, configuration)
  let authenticator = match named_submission_authenticator(current, check, @utf8.encode(preimage)) {
    Ok(value) => value
    Err(code) => return code
  }
  guard @host.client_submitted_name_row_body({
      binding: name_binding, authenticator,
    }) is Ok(body) else { return -34 }
  let body = @utf8.decode(body) catch { _ => return -34 }
  let projected = try {
    let writer = @encode.writer(NAMED_SUBMISSION_APPEND_LIMIT, 9, 1)
    @encode.begin_object(writer)
    @encode.key(writer, "index")
    @encode.string_value(writer, inventory.index)
    @encode.key(writer, "issued_revision")
    @encode.string_value(writer, inventory.issued_revision.to_string())
    @encode.key(writer, "issued_body")
    @encode.string_value(writer, (inventory.issued + 1).to_string())
    @encode.key(writer, "body")
    @encode.string_value(writer, body)
    @encode.end_object(writer)
    @utf8.encode(@encode.finish(writer))
  } catch { _ => return -34 }
  match check() {
    Err(code) => return code
    Ok(_) => ()
  }
  let code = status(@buffers.supply_buffer_output(value.pool, record.slot, projected))
  if code == 0 {
    held.original = Some((parent, key, inventory.index, inventory.issued, inventory.issued_revision))
    record.produced = true
  }
  code
}

///|
fn validate_named_submission_append(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Int {
  guard record.produced && !record.output_closed &&
    record.append_plan is NamedSubmissionAppend(held) &&
    held.original is Some((parent, key, index, issued, revision)) &&
    value.submissions.get(parent) is Some(original) &&
    original.configuration == record.configuration &&
    original.produced &&
    original.append_plan is Ready(@host.Append(_)) &&
    configuration.host_current is Some(host_current) &&
    value.host_currents.get(host_current) is Some(current) else { return -32 }
  match observe_named_submission_inventory(value, record, configuration, current, key) {
    Ok(inventory) if inventory.original is None &&
      inventory.index == index &&
      inventory.issued == issued &&
      inventory.issued_revision == revision => 0
    Ok(_) => -45
    Err(code) => code
  }
}
