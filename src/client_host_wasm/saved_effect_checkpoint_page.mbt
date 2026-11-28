///|
const SAVED_EFFECT_CHECKPOINT_PAGE_KIND : Int = 14

///|
fn validate_saved_effect_checkpoint_page(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Int {
  match select_saved_effect_checkpoint_page(value, record, configuration) {
    Ok(actual) if @buffers.buffer_wire(value.pool, record.slot) == Some(actual) =>
      0
    Ok(_) => -32
    Err(code) => code
  }
}

///|
fn produce_saved_effect_checkpoint_page(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Int {
  if record.produced {
    return validate_saved_effect_checkpoint_page(value, record, configuration)
  }
  if record.invoked || record.output_closed {
    return -33
  }
  record.invoked = true
  let bytes = match
    select_saved_effect_checkpoint_page(value, record, configuration) {
    Ok(bytes) => bytes
    Err(code) => return code
  }
  let supplied = status(
    @buffers.supply_buffer_output(value.pool, record.slot, bytes),
  )
  if supplied == 0 {
    record.produced = true
  }
  supplied
}

///|
fn select_saved_effect_checkpoint_page(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Result[Bytes, Int] {
  match submission_lookup_current(value, record, configuration) {
    Ok(_) => ()
    Err(code) => return Err(code)
  }
  guard configuration.mock_project is Some(_) &&
    configuration.sdk is Some(_) &&
    configuration.host_current is Some(handle) &&
    value.host_currents.get(handle) is Some(current) else {
    return Err(-32)
  }
  guard record.borrow is Ok(borrow) &&
    input_cursor(value, borrow.slot) is Some(cursor) &&
    @decode.closed_object(cursor, ["after", "limit", "checkpointId"])
    is Ok(fields) &&
    required_text(fields, "after") is Some(after) &&
    @decode.required(fields, "limit") is Ok(count) &&
    @decode.safe_integer(count) is Ok(count) &&
    count >= 1L &&
    count <= 100L else {
    return Err(-31)
  }
  let id = match @decode.lookup(fields, "checkpointId") {
    None => None
    Some(selected) =>
      match @decode.text(selected) {
        Ok(id) => Some(id)
        Err(_) => return Err(-31)
      }
  }
  if physical_journal_schema(current.physical) != 1 {
    return Err(-41)
  }
  let limit = count.to_int()
  let max_bytes = Int::min(1048576, limit * 16384 + 1024)
  let max_nodes = 16 + limit * 128
  guard sdk_journal_writer_capacity(max_bytes, max_nodes, 8)
    is Some(writer_scratch) &&
    sdk_journal_writer_capacity(4096, 8, 2) is Some(binding_scratch) else {
    return Err(-4)
  }
  // At most one selected row and its bounded join is live beside the page
  // writer. The existing Journal transport limits each original to 256 KiB.
  let fixed = writer_scratch +
    binding_scratch +
    max_bytes.to_int64() +
    8L * 262144L
  guard record.append_plan is Idle else { return Err(-9) }
  let capacity = match @resources.reserve_capacity(value.root, 0L, fixed) {
    Ok(value) => value
    Err(_) => return Err(-4)
  }
  // The same projection owns this synchronous workspace before entering the
  // physical reader. Its established cleanup retains a trap or refusal.
  record.append_plan = Decoding(capacity, Idle)
  let pending = project_saved_effect_checkpoint_page(
    value, record, configuration, current, after, limit, id, max_bytes, max_nodes,
    fixed, capacity,
  )
  let returned = close_submission_decode_prefix(value, record)
  pending.bind(bytes => {
    if returned != 0 {
      Err(returned)
    } else {
      submission_lookup_current(value, record, configuration).map(_ => bytes)
    }
  })
}

///|
fn project_saved_effect_checkpoint_page(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
  current : StoredHostCurrent,
  after : String,
  limit : Int,
  id : String?,
  max_bytes : Int,
  max_nodes : Int,
  fixed : Int64,
  capacity : @resources.CapacityReservation,
) -> Result[Bytes, Int] {
  guard configuration.sdk is Some(sdk) &&
    current.generation is Some((device, inode)) &&
    @host.client_publication_store_binding_body(
      configuration.run_namespace,
      sdk.store_authority_cid,
      device,
      inode,
    )
    is Ok(binding) else {
    return Err(-32)
  }
  let check = () => submission_lookup_current(value, record, configuration)
  let selected = Ref(0L)
  let peak = Ref(fixed)
  let grow = (total : Int64) => {
    if total <= peak.val {
      return true
    }
    if @resources.grow_capacity_reservation(value.root, capacity, 0L, total)
      is Err(_) {
      return false
    }
    peak.val = total
    true
  }
  let fund = (bytes : Int, nodes : Int, _ : Int) => {
    guard @host.client_protocol_metadata_construction_bytes(
        bytes,
        nodes.to_int64(),
      )
      is Some((codec, _)) &&
      @execution.checked_preparation_add_product(selected.val, codec, 1L)
      is Some(peak) &&
      @execution.checked_preparation_add_product(fixed, peak, 1L) is Some(total) &&
      grow(total) else {
      return Err(-4)
    }
    Ok(())
  }
  let decoding = (row : @host.ClientJournalPhysicalRow) => {
    let refused = Ref(false)
    let decoded = @host.decode_client_run_journal_row_with_observation_originals(
      row.body,
      before_construction=Some(stage => {
        guard @host.client_run_journal_decode_construction(stage)
          is Some((r, e)) &&
          @execution.checked_preparation_add_product(fixed, r, 1L) is Some(next) &&
          @execution.checked_preparation_add_product(next, e, 1L) is Some(peak) &&
          grow(peak) else {
          refused.val = true
          return Err(@host.ClientJournalDecodingIssue::CustodyLost)
        }
        selected.val = r
        Ok(())
      }),
    )
    match decoded {
      Ok((run, _, _)) => Ok(run)
      Err(_) => Err(if refused.val { -4 } else { -32 })
    }
  }
  let writer = @encode.writer(max_bytes, max_nodes, 8) catch {
    _ => return Err(-34)
  }
  @host.write_client_waiting_effect_checkpoint_page(
    writer,
    configuration.run_namespace,
    configuration.authority_scope_cid,
    binding,
    after,
    limit,
    id,
    (table, key) => physical_journal_row(current.physical, check, 1, table, key),
    (table, key) => {
      selected.val = 0L
      physical_journal_row(current.physical, check, 0, table, key)
    },
    decoding,
    -32,
    fund,
  ).bind(_ => Ok(@utf8.encode(@encode.finish(writer))) catch { _ => Err(-34) })
}
