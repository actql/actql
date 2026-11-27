///|
const SAVED_EFFECT_FILE_PUBLISHED_KIND : Int = 30

///|
const SAVED_EFFECT_FILE_PUBLISHED_HEADER : Int = 237

///|
priv struct StoredSavedEffectFilePublished {
  parent : Int
  capacity : @resources.CapacityReservation
  rows : Array[@host.ClientEffectFileJournalWrite]
  index_key : String
  index_cid : String
}

///|
fn produce_saved_effect_file_published(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Int {
  guard !record.invoked && !record.output_closed else { return -33 }
  record.invoked = true
  guard record.borrow is Ok(borrow) &&
    @buffers.filled_payload_input_bytes(value.pool, borrow) is Some(input) &&
    input.length() == 28 &&
    value.publications.get(mock_effect_descriptor_field(input, 0))
    is Some(publication) &&
    publication.saved_effect is Some(origin) &&
    origin.prepared is Some(prepared) &&
    value.submissions.get(origin.source) is Some(source) &&
    value.run_configurations.get(source.configuration) is Some(selected) &&
    physical_equal(selected, configuration) &&
    source.append_plan is EffectFileCompletion(completion) &&
    value.submissions.get(completion.parent) is Some(holder) &&
    holder.append_plan is EffectFileTerminal(terminal) &&
    publication.observation_checked &&
    !publication.observation_failed &&
    publication.observation_index is Some(index) &&
    publication.observation_publisher is Some(publisher) &&
    publication.commit is Some(commit) &&
    publication.commit_view is Some(view) &&
    !publication.saved_effect_state_attempted else {
    return -32
  }
  publication.saved_effect_state_attempted = true
  let at = @utf8.decode(input[4:28].to_owned()) catch { _ => return -31 }
  guard @values.timestamp_epoch_milliseconds(at) is Some(now) else {
    return -31
  }
  let checked = publication_observation_publisher(
    value,
    publication,
    publisher,
    record.configuration,
    Some(index),
  )
  if checked != 0 {
    return checked
  }
  let initial = 131072L
  let capacity = match @resources.reserve_capacity(value.root, 0L, initial) {
    Ok(value) => value
    Err(_) => return -53001
  }
  record.append_plan = Decoding(capacity, Idle)
  let peak = Ref(initial)
  let refused = Ref(false)
  fn fund_amount(amount : Int64) -> Bool {
    guard @execution.checked_preparation_add_product(initial, 1L, amount)
      is Some(next) else {
      refused.val = true
      return false
    }
    if next > peak.val {
      if @resources.grow_capacity_reservation(value.root, capacity, 0L, next)
        is Err(_) {
        refused.val = true
        return false
      }
      peak.val = next
    }
    true
  }
  let state = match commit.observed_run_state_wire(view, at, 65536, 4096, 64) {
    Ok(value) => value
    Err(_) => return -31
  }
  let row = prepared.prepare_completed_state(
    terminal.original,
    state,
    at,
    now,
    (bytes, nodes, _) => {
      guard @host.client_protocol_metadata_construction_bytes(
          bytes,
          nodes.to_int64(),
          copies=1,
        )
        is Some((scratch, _)) &&
        fund_amount(scratch) else {
        return Err(@host.ClientJournalEncodingIssue::CapacityExceeded)
      }
      Ok(())
    },
  )
  guard row is Ok(row) else { return if refused.val { -53002 } else { -31 } }
  let check = publication_observation_publisher(
    value,
    publication,
    publisher,
    record.configuration,
    Some(index),
  )
  if check != 0 {
    return check
  }
  let index_cid = @publication.publication_contract_identity(index)
  let anchor = prepared.prepare_completion_anchor(index_cid)
  if anchor.key != row.key { return -32 }
  let rows = [row, anchor]
  guard @publication.publication_index_storage_key(index, 1048576, 100000, 64)
    is Ok(index_key) &&
    saved_file_journal_packet(rows, index_cid) is Some(packet) else {
    return -31
  }
  let code = status(
    @buffers.supply_buffer_output(value.pool, record.slot, packet),
  )
  if code == 0 {
    record.append_plan = EffectFilePublished({
      parent: origin.source,
      capacity,
      rows,
      index_key,
      index_cid,
    })
    record.produced = true
  }
  code
}

///|
fn observe_saved_effect_file_published(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
) -> Result[Bool, Int] {
  guard record.append_plan is EffectFilePublished(published) &&
    configuration.host_current is Some(handle) &&
    value.host_currents.get(handle) is Some(current) else {
    return Err(-32)
  }
  let check = () => submission_lookup_current(value, record, configuration)
  match
    physical_journal_row(
      current.physical,
      check,
      1,
      "public_index",
      published.index_key,
    ) {
    Ok(Some(index)) if index.revision == 0L &&
      index.body == @utf8.encode(published.index_cid) =>
      observe_saved_file_journal_rows(current.physical, check, published.rows)
        .map_err(code => if code == -32 { -53104 } else { code })
    Ok(None) => Err(-53102)
    Ok(Some(_)) => Err(-53103)
    Err(code) => Err(code)
  }
}
