///|
// Back the candidate that will outlive the journal callbacks. The Read still
// owns its physical copies and point-read fences. These bounds are the existing
// legacy limits of the submitted row, RunState original and admission codecs.
fn sdk_run_state_update_construction_capacity() -> (Int64, Int64)? {
  let snapshot = @host.client_submitted_journal_retained_inventory(
    262144,
    3L * 262144L + 4096L,
  )
  guard @publication.run_state_observation_construction_inventory(
      65536, 8192, 64,
    )
    is Some((state, codec)) &&
    @encode.text_writer_construction_inventory(131072, 8, 1)
    is Some(original_writer) &&
    @encode.text_writer_construction_inventory(262144, 16, 2)
    is Some(row_writer) &&
    @encode.text_writer_construction_inventory(8192, 8, 2)
    is Some(admission_writer) &&
    @encode.text_writer_construction_inventory(4096, 32, 2)
    is Some(request_writer) else {
    return None
  }
  guard sdk_run_state_update_retention(262144L, 262144L, 4096L, 65536L)
    is Some(retained) else {
    return None
  }
  let working = @execution.preparation_representation_cost({
    // The saved snapshot, the live state/projection and original state
    // validation can coexist with the candidate. Quote the nested writers
    // and their returned text until the update constructor returns.
    record_headers: snapshot.record_headers +
    state.record_headers +
    codec.record_headers +
    original_writer.record_headers +
    row_writer.record_headers +
    admission_writer.record_headers +
    request_writer.record_headers +
    32L,
    reference_slots: snapshot.reference_slots +
    state.reference_slots +
    codec.reference_slots +
    original_writer.reference_slots +
    row_writer.reference_slots +
    admission_writer.reference_slots +
    request_writer.reference_slots +
    64L,
    scalar_words: snapshot.scalar_words +
    state.scalar_words +
    codec.scalar_words +
    original_writer.scalar_words +
    row_writer.scalar_words +
    admission_writer.scalar_words +
    request_writer.scalar_words +
    32L,
    owned_utf16_units: snapshot.owned_utf16_units +
    state.owned_utf16_units +
    codec.owned_utf16_units +
    original_writer.owned_utf16_units +
    row_writer.owned_utf16_units +
    admission_writer.owned_utf16_units +
    request_writer.owned_utf16_units,
    // Temporary UTF-8 for the wrapped State limit check. The actual immutable
    // submitted Row and its predecessor are in the retained charge below.
    owned_wire_bytes: state.owned_wire_bytes + codec.owned_wire_bytes + 131072L,
  })
  working.bind(amount => {
    @execution.checked_preparation_add_product(amount, retained, 1L).map(execution => {
      (retained, execution)
    })
  })
}

///|
fn sdk_run_state_update_retention(
  prior_bytes : Int64,
  new_bytes : Int64,
  key_units : Int64,
  state_units : Int64,
) -> Int64? {
  @execution.preparation_representation_cost({
    // Update, its optional reference and the two byte/text pairs, with the
    // projection's original control and success carriers. The request and
    // Definition CID are borrowed from the already retained Plan.
    record_headers: 8L,
    reference_slots: 12L,
    scalar_words: 12L,
    owned_utf16_units: key_units + state_units,
    owned_wire_bytes: prior_bytes + new_bytes,
  })
}

///|
fn reconcile_sdk_run_state_update_capacity(
  value : Instance,
  output : StoredPublicationCommitExport,
  prior_bytes : Int,
  update : @host.ClientSavedRunStateUpdate,
) -> Result[Unit, Int] {
  guard output.sdk_run_state_update_capacity is Some(capacity) else {
    return Err(-4)
  }
  let (key, prior, revision, body) = @host.client_saved_run_state_update_row(
    update,
  )
  // The retained case returns the exact original Bytes for both fields. A
  // replacement has independent wire backing even for an equal-length row.
  let new_bytes = if revision == prior { 0 } else { body.length() }
  let state = @host.client_saved_run_state_update_candidate_wire(update)
  guard sdk_run_state_update_retention(
      prior_bytes.to_int64(),
      new_bytes.to_int64(),
      key.length().to_int64(),
      state.length().to_int64(),
    )
    is Some(retained) else {
    return Err(-4)
  }
  @resources.shrink_capacity_reservation(
    value.root,
    capacity,
    retained,
    retained,
  ).map_err(_ => -4)
}
