///|
// The same lookup owns an occurrence -> exact original Request/key-slot map.
// Its existing distinct-key slots retain the first request and eventual
// response history. No second acquisition, Ledger or authority is created.
fn keyed_lookup_plan_storage(occurrences : Int, keys : Int) -> Int64? {
  guard @shape.collection_construction_extent({
      // Per occurrence: Request1H3R4W/accounting Some1H1R1W/map tuple1H1R1W.
      // Per key: cache tuple1H3R/history1H2R/history Some1H1R1W.
      records: 3L * occurrences.to_int64() + 3L * keys.to_int64(),
      record_references: 5L * occurrences.to_int64() + 6L * keys.to_int64(),
      record_words: 6L * occurrences.to_int64() + keys.to_int64(),
      reference_arrays: 2L,
      reference_items: occurrences.to_int64() + keys.to_int64(),
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(layout) else {
    return None
  }
  @execution.preparation_representation_cost({
    record_headers: layout.record_headers,
    reference_slots: layout.reference_slots,
    scalar_words: layout.scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
}

///|
fn keyed_lookup_plan_grow(
  state : ClientKeyedLookupInput,
  extra : Int64,
) -> Result[Unit, ClientKeyedRequestIssue] {
  if extra < 0L || state.retained_bytes > 9223372036854775807L - extra {
    return Err(Assembly("capacity_overflow"))
  }
  state.growing = true
  let result = @resources.grow_execution_reservation_capacity(
    state.ledger,
    state.reservation,
    state.retained_bytes + extra,
    state.execution_bytes,
  )
  state.growing = false
  match result {
    Err(issue) => return keyed_lookup_fail(state.left, Physical(issue))
    Ok(_) => state.retained_bytes += extra
  }
  if state.closed ||
    state.left.lookup_issue is Some(_) ||
    !client_keyed_left_available(state.left) ||
    state.closed {
    return keyed_lookup_fail(state.left, Assembly("retired_request_plan"))
  }
  Ok(())
}

///|
/// Opt in before any request/response has escaped. The fixed empty controls
/// are constructed only after their same-lookup backing is admitted.
pub fn start_client_keyed_lookup_request_plan(
  state : ClientKeyedLookupInput,
  native_read_profile? : @publication.PublicationContract? = None,
) -> Result[Unit, ClientKeyedRequestIssue] {
  guard !state.closed &&
    !state.growing &&
    !state.identifying &&
    state.accepted == 0 &&
    state.known.is_empty() &&
    state.preparation is None &&
    state.selected_request is None &&
    state.completed is None &&
    state.planned_requests is None &&
    state.publication_identity is None &&
    state.left.lookup_issue is None else {
    return Err(Assembly("unavailable_request_plan"))
  }
  if native_read_profile is Some(profile) {
    match check_client_keyed_native_read_profile(state, profile) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  // One additional empty grow-only reference Array (3H13R2W) and its
  // original Some (1H1R1W). The existing known array is already backed.
  let initial = @execution.preparation_representation_cost({
    record_headers: 4L + (if native_read_profile is Some(_) { 1L } else { 0L }),
    reference_slots: 14L +
    (if native_read_profile is Some(_) { 1L } else { 0L }),
    scalar_words: 3L + (if native_read_profile is Some(_) { 1L } else { 0L }),
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
  match keyed_lookup_plan_grow(state, initial) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  state.native_read_profile = native_read_profile
  state.planned_requests = Some([])
  Ok(())
}

///|
/// Retain the original request just completed by the same assembly cursor.
/// Each occurrence is prepared once; repeated exact keys share its old cache
/// slot, not its left occurrence or a newly issued Request/attempt allowance.
pub fn retain_client_keyed_lookup_planned_request(
  state : ClientKeyedLookupInput,
  request : ClientKeyedRequest,
) -> Result[Unit, ClientKeyedRequestIssue] {
  guard !state.closed &&
    !state.growing &&
    !state.identifying &&
    state.planned_requests is Some(requests) &&
    state.planned_order is None &&
    state.accepted == 0 &&
    state.preparation is None &&
    state.selected_request is Some(selected) &&
    physical_equal(selected, request) &&
    request.row == requests.length() &&
    request.attempts == 0L &&
    !request.io_complete &&
    request.assembly_accounting is Some(owner) &&
    physical_equal(owner, state) &&
    state.left.lookup_issue is None else {
    return Err(Assembly("foreign_or_unavailable_planned_request"))
  }
  // A Ref encoder may reenter retirement. Keep the same originals/backing
  // until the synchronous wire borrow ends; owning stop remains observable.
  state.identifying = true
  let encoded = keyed_lookup_request_wire(state, request)
  state.identifying = false
  let wire = match encoded {
    Ok(wire) => wire
    Err(issue) => return Err(issue)
  }
  if state.closed || state.left.lookup_issue is Some(_) {
    return Err(Assembly("retired_request_plan"))
  }
  if !charge_keyed_lookup_input_work(state, wire.length()) {
    return Err(LookupLimit("work"))
  }
  let mut slot = -1
  for index, (key, _, _) in state.known {
    let work = key.length().to_int64() + wire.length().to_int64() + 1L
    if work > 2147483647L ||
      !charge_keyed_lookup_input_work(state, work.to_int()) {
      return Err(LookupLimit("work"))
    }
    if key == wire {
      slot = index
      break
    }
  }
  let distinct = slot < 0
  guard @acquisition.keyed_row_request_retained_inventory(request.request)
    is Some(payload) &&
    keyed_lookup_plan_storage(requests.length(), state.known.length())
    is Some(previous) &&
    keyed_lookup_plan_storage(
      requests.length() + 1,
      state.known.length() + (if distinct { 1 } else { 0 }),
    )
    is Some(next) &&
    @execution.preparation_representation_cost({
      record_headers: payload.record_headers,
      reference_slots: payload.reference_slots,
      scalar_words: payload.scalar_words,
      owned_utf16_units: if distinct {
        wire.length().to_int64()
      } else {
        0L
      },
      owned_wire_bytes: 0L,
    })
    is Some(body) &&
    @execution.checked_preparation_add_product(next - previous, body, 1L)
    is Some(extra) else {
    return Err(Assembly("capacity_overflow"))
  }
  match keyed_lookup_plan_grow(state, extra) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !(state.selected_request is Some(original) &&
    physical_equal(original, request)) {
    return Err(Assembly("retired_request_plan"))
  }
  if distinct {
    slot = state.known.length()
    state.known.push((wire, None, Some({ request, _retained_capture: None, })))
  }
  requests.push((request, slot))
  state.selected_request = None
  Ok(())
}

///|
/// Select the SAME stored occurrence for ordinary capture after the entire
/// key set/static request/scope has been closed before dispatch.
pub fn client_keyed_lookup_planned_request(
  state : ClientKeyedLookupInput,
  row : Int,
) -> Result[ClientKeyedRequest, ClientKeyedRequestIssue] {
  guard !state.closed &&
    !state.growing &&
    !state.identifying &&
    state.left.lookup_issue is None &&
    state.planned_order is Some(_) &&
    state.copying is None &&
    state.preparation is None &&
    state.completed is None &&
    row == state.accepted &&
    client_keyed_left_available(state.left) &&
    !state.closed &&
    state.planned_requests is Some(requests) &&
    requests.get(row) is Some((request, slot)) &&
    state.known.get(slot) is Some((key, read, _)) else {
    return Err(Assembly("unavailable_planned_request"))
  }
  if state.selected_request is Some(original) &&
    !physical_equal(original, request) {
    return Err(Assembly("unfinished_request"))
  }
  state.selected_request = Some(request)
  state.selected_key = Some(key)
  state.selected_index = Some(if read is Some(_) { slot } else { -1 })
  Ok(request)
}

///|
// Callback-free phase/original check used after the actual current callback.
// It cannot grant a read or create an attempt and leaves legacy callers intact.
fn keyed_lookup_request_dispatch_available(
  request : ClientKeyedRequest,
) -> Bool {
  match request.assembly_accounting {
    None => true
    Some(state) =>
      if state.closed {
        false
      } else {
        match state.planned_requests {
          None => true
          Some(requests) =>
            !state.closed &&
            state.planned_order is Some(_) &&
            (
              state.native_read_profile is None ||
              state.native_transport is Some(_)
            ) &&
            state.selected_index == Some(-1) &&
            state.selected_request is Some(selected) &&
            physical_equal(selected, request) &&
            requests.get(state.accepted) is Some((original, _)) &&
            physical_equal(original, request)
        }
      }
  }
}
