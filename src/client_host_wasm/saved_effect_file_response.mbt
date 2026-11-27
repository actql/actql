///|
const SAVED_EFFECT_FILE_RESPONSE_KIND : Int = 26

///|
const SAVED_EFFECT_FILE_RESPONSE_FIELD_KIND : Int = 27

///|
const SAVED_EFFECT_FILE_RESPONSE_HEADER : Int = 403

///|
priv struct StoredSavedEffectFileResponse {
  parent : Int
  dispatch : Int
  capacity : @resources.CapacityReservation
  original : @host.ClientEffectSavedFileResponse
  mut terminal_attempted : Bool
}

///|
fn saved_effect_file_response_kind(kind : Int) -> Bool {
  kind == SAVED_EFFECT_FILE_PUBLISHED_KIND ||
  kind == SAVED_EFFECT_FILE_COMPLETION_KIND ||
  kind == SAVED_EFFECT_FILE_TERMINAL_KIND ||
  kind == SAVED_EFFECT_FILE_RESPONSE_KIND ||
  kind == SAVED_EFFECT_FILE_RESPONSE_FIELD_KIND
}

///|
fn saved_file_journal_coordinate(
  physical : Int,
  current : () -> Result[Unit, Int],
  write : @host.ClientEffectFileJournalWrite,
) -> Result[Bool, Int] {
  let (generation, extent) = match write.before {
    Some(row) => (row.revision, row.body.length())
    None => (-1L, 0)
  }
  let row = match
    physical_journal_row(
      physical,
      current,
      1,
      write.table,
      write.key,
      expected_successor_lengths=Some(
        (generation, extent, write.successor.length()),
      ),
    ) {
    Ok(value) => value
    Err(code) => return Err(code)
  }
  match (row, write.before) {
    (None, None) => return Ok(false)
    (Some(actual), Some(before)) if actual.key == before.key &&
      actual.revision == before.revision &&
      actual.body == before.body => return Ok(false)
    _ => ()
  }
  match row {
    Some(actual) if actual.key == write.key &&
      actual.revision == generation + 1L &&
      actual.body == write.successor => Ok(true)
    _ => Err(-32)
  }
}

///|
fn observe_saved_effect_file_response(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Result[Bool, Int] {
  guard record.append_plan is EffectFileResponse(response) &&
    configuration.host_current is Some(current_handle) &&
    value.host_currents.get(current_handle) is Some(current) else {
    return Err(-32)
  }
  let check = () => submission_lookup_current(value, record, configuration)
  observe_saved_file_journal_rows(current.physical, check, response.original.rows())
}

///|
fn observe_saved_file_journal_rows(
  physical : Int,
  check : () -> Result[Unit, Int],
  rows : Array[@host.ClientEffectFileJournalWrite],
) -> Result[Bool, Int] {
  let mut found : Bool? = None
  for write in rows {
    match saved_file_journal_coordinate(physical, check, write) {
      Ok(state) if found is None || found == Some(state) => found = Some(state)
      Ok(_) => return Err(-32)
      Err(code) => return Err(code)
    }
  }
  guard found is Some(state) else { return Err(-32) }
  check().map(_ => state)
}

///|
fn saved_file_journal_packet(
  rows : Array[@host.ClientEffectFileJournalWrite],
  identity : String,
) -> Bytes? {
  guard identity.length() == 71 &&
    rows.all(write => write.key.length() == 71 && write.successor.length() > 0) else {
    return None
  }
  Some(
    Bytes::makei(rows.length() * 83, index => {
      let row = rows[index / 83]
      let offset = index % 83
      if offset < 8 {
        let revision = row.before.map_or(-1L, original => original.revision)
        (revision >> (offset * 8)).to_byte()
      } else if offset < 12 {
        (row.successor.length() >> ((offset - 8) * 8)).to_byte()
      } else {
        row.key[offset - 12].to_int().to_byte()
      }
    }) +
    @utf8.encode(identity),
  )
}

///|
fn saved_physical_generation(bytes : Bytes, offset : Int) -> Int64 {
  let mut value = 0L
  for index in 0..<8 {
    value = value | (bytes[offset + index].to_int().to_int64() << (index * 8))
  }
  value
}

///|
fn produce_saved_effect_file_response(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Int {
  guard !record.invoked && !record.output_closed else { return -33 }
  record.invoked = true
  guard saved_effect_decision_parent(
      value,
      record,
      SAVED_EFFECT_FILE_REPLACEMENT_KIND,
    )
    is Some((parent, holder, input)) &&
    input.length() == 84 &&
    holder.append_plan is EffectFileReplacement(replacement) &&
    !replacement.response_attempted &&
    value.submissions.get(replacement.parent) is Some(operation_holder) &&
    operation_holder.append_plan is EffectFileOperation(operation) &&
    value.submissions.get(operation.parent) is Some(dispatch_holder) &&
    dispatch_holder.append_plan is EffectFileDispatch(dispatch) else {
    return -32
  }
  replacement.response_attempted = true
  match
    observe_saved_effect_file_dispatch(value, dispatch_holder, configuration) {
    Ok(true) => ()
    Ok(false) => return -32
    Err(code) => return code
  }
  let initial = 524288L
  let capacity = match @resources.reserve_capacity(value.root, 0L, initial) {
    Ok(value) => value
    Err(_) => return -4
  }
  record.append_plan = Decoding(capacity, Idle)
  let digest = @utf8.decode(input[20:]) catch { _ => return -31 }
  let peak = Ref(initial)
  let held = Ref(initial)
  let refused = Ref(false)
  let fund = (bytes : Int, nodes : Int, _) => {
    guard @host.client_protocol_metadata_construction_bytes(
        bytes,
        nodes.to_int64(),
      )
      is Some((scratch, retention)) &&
      @execution.checked_preparation_add_product(held.val, 1L, scratch)
      is Some(requested) &&
      @execution.checked_preparation_add_product(
        held.val,
        1L,
        retention + 4L * bytes.to_int64(),
      )
      is Some(next) else {
      refused.val = true
      return false
    }
    if requested > peak.val {
      if @resources.grow_capacity_reservation(
          value.root,
          capacity,
          0L,
          requested,
        )
        is Err(_) {
        refused.val = true
        return false
      }
      peak.val = requested
    }
    held.val = next
    true
  }
  let original = match
    dispatch.original.prepare_response(
      replacement.body,
      saved_physical_generation(input, 4),
      saved_physical_generation(input, 12),
      digest,
      262144,
      fund,
    ) {
    Ok(value) => value
    Err(_) => return if refused.val { -4 } else { -31 }
  }
  guard saved_file_journal_packet(original.rows(), original.response_cid())
    is Some(header) &&
    header.length() == SAVED_EFFECT_FILE_RESPONSE_HEADER else {
    return -32
  }
  let code = status(
    @buffers.supply_buffer_output(value.pool, record.slot, header),
  )
  if code == 0 {
    record.append_plan = EffectFileResponse({
      parent, dispatch: operation.parent, capacity, original, terminal_attempted: false,
    })
    record.produced = true
  }
  code
}

///|
fn produce_saved_effect_file_response_field(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Int {
  guard !record.invoked && !record.output_closed else { return -33 }
  record.invoked = true
  let borrow = match record.borrow {
    Ok(borrow) => borrow
    Err(issue) => return issue_code(issue)
  }
  guard @buffers.filled_payload_input_bytes(value.pool, borrow) is Some(input) &&
    input.length() == 16 else { return -31 }
  let parent = mock_effect_descriptor_field(input, 0)
  guard value.submissions.get(parent) is Some(holder) else {
    return -32
  }
  guard holder.configuration == record.configuration && holder.produced && !holder.output_closed else {
    return -32
  }
  let field = mock_effect_descriptor_field(input, 4)
  let bytes = match holder.append_plan {
    EffectFileResponse(response) => response.original.rows().get(field).map(row => row.successor)
    EffectFileTerminal(terminal) => terminal.original.rows().get(field).map(row => row.successor)
    EffectFilePublished(published) => published.rows.get(field).map(row => row.successor)
    EffectFileReplacement(replacement) if field == 0 => Some(replacement.body)
    _ => None
  }
  guard bytes is Some(body) else { return -32 }
  let offset = mock_effect_descriptor_field(input, 8)
  let count = mock_effect_descriptor_field(input, 12)
  guard offset >= 0 &&
    count > 0 &&
    count <= SAVED_EFFECT_DECISION_FIELD_MAX &&
    offset <= body.length() - count else {
    return -31
  }
  let validation = validate_saved_effect_file_field_parent(value, holder, configuration)
  if validation != 0 { return validation }
  let code = status(
    @buffers.supply_buffer_output(
      value.pool,
      record.slot,
      body[offset:offset + count].to_owned(),
    ),
  )
  if code == 0 {
    record.append_plan = EffectDecisionField(parent)
    record.produced = true
  }
  code
}

///|
fn observe_saved_effect_file_journal(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Result[Bool, Int] {
  match record.append_plan {
    EffectFileResponse(_) => observe_saved_effect_file_response(value, record, configuration)
    EffectFileTerminal(_) => observe_saved_effect_file_terminal(value, record, configuration)
    EffectFilePublished(_) => observe_saved_effect_file_published(value, record, configuration)
    _ => Err(-32)
  }
}

///|
fn validate_saved_effect_file_field_parent(
  value : Instance,
  holder : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Int {
  if holder.append_plan is EffectFileReplacement(_) {
    return validate_saved_effect_file_operation(value, holder, configuration)
  }
  match observe_saved_effect_file_journal(value, holder, configuration) {
    Ok(false) => 0
    Ok(true) => -32
    Err(code) => code
  }
}
