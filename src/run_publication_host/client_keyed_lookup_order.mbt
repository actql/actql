///|
// Scalar indices point into the SAME append-only response/request history.
// Keys, typed Requests and physical children are neither copied nor reordered.
fn keyed_lookup_order_capacity(count : Int) -> Int64? {
  if count < 0 {
    return None
  }
  @shape.collection_construction_extent({
    records: 0L,
    record_references: 1L,
    record_words: 1L,
    reference_arrays: 0L,
    reference_items: 0L,
    scalar_arrays: 1L,
    scalar_items: count.to_int64(),
    maps: 0L,
    map_entries: 0L,
  }).bind(layout => {
    @execution.preparation_representation_cost({
      record_headers: layout.record_headers,
      reference_slots: layout.reference_slots,
      scalar_words: layout.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
  })
}

///|
// Match the pinned String.compare exactly: length first, then UTF-16 units.
// Charge each actual inspected pair before reading it. An unexamined suffix
// has neither been scanned nor compared; no key field, normalization or hash
// replaces the complete original canonical Request's equality/order.
fn keyed_lookup_order_compare(
  state : ClientKeyedLookupInput,
  left : String,
  right : String,
) -> Result[Int, ClientKeyedRequestIssue] {
  if !charge_keyed_lookup_input_work(state, 1) {
    return Err(LookupLimit("work"))
  }
  let order = left.length().compare(right.length())
  if order != 0 {
    return Ok(order)
  }
  for index in 0..<left.length() {
    if !charge_keyed_lookup_input_work(state, 2) {
      return Err(LookupLimit("work"))
    }
    let order = left[index].compare(right[index])
    if order != 0 {
      return Ok(order)
    }
  }
  Ok(0)
}

///|
fn keyed_lookup_order_find(
  state : ClientKeyedLookupInput,
  wire : String,
) -> Result[(Int, Int), ClientKeyedRequestIssue] {
  if state.key_order.length() != state.known.length() {
    return Err(Assembly("key_order_unavailable"))
  }
  let mut first = 0
  let mut last = state.key_order.length()
  while first < last {
    let middle = first + (last - first) / 2
    let slot = state.key_order[middle]
    guard state.known.get(slot) is Some((key, _, _)) else {
      return Err(Assembly("key_order_unavailable"))
    }
    let compared = match keyed_lookup_order_compare(state, key, wire) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if compared == 0 {
      return Ok((slot, middle))
    }
    if compared < 0 {
      first = middle + 1
    } else {
      last = middle
    }
  }
  Ok((-1, first))
}

///|
// Fund the actual scalar Array's old/new backing overlap before mutation.
// Insertion shifts the existing suffix; charge every moved slot and append.
fn keyed_lookup_order_insert_capacity(
  state : ClientKeyedLookupInput,
  position : Int,
) -> Result[Int64, ClientKeyedRequestIssue] {
  let count = state.key_order.length()
  if position < 0 ||
    position > count ||
    count != state.known.length() ||
    count == 2147483647 {
    return Err(Assembly("key_order_unavailable"))
  }
  guard keyed_lookup_order_capacity(count) is Some(before) &&
    keyed_lookup_order_capacity(count + 1) is Some(after) else {
    return Err(Assembly("capacity_overflow"))
  }
  if !charge_keyed_lookup_input_work(state, count - position + 1) {
    return Err(LookupLimit("work"))
  }
  Ok(after - before)
}
