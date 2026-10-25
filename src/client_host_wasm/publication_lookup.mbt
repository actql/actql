///|
/// Retain the original physically read index and its Store reference. Scope
/// and lookup references come from the existing completed CommitPreparation;
/// no Python comparison or publisher permission is accepted as a commit fact.
pub fn prepare_publication_lookup(
  nonce : Int64,
  handle : Int,
  input : Int,
  publisher : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.publications.get(handle) is Some(record) &&
    value.copies.get(input) is Some((slot, physical)) &&
    value.run_configurations.get(current_configuration) is Some(current) else {
    return -2
  }
  let (commit, view) = match
    publication_commit_export_view(value, record, current.account) {
    Ok(original) => original
    Err(code) => return code
  }
  if record.lookup_closing {
    return -5
  }
  if record.pending ||
    record.lookup_failed ||
    record.observation_input is Some(_) {
    return -33
  }
  if record.lookup_input is Some(original) &&
    (original != input || record.lookup_publisher != Some(publisher)) {
    return -2
  }
  let auth = publication_observation_publisher(
    value,
    record,
    publisher,
    current_configuration,
    None,
  )
  if auth != 0 {
    return auth
  }
  if record.lookup_input is Some(_) {
    return if record.lookup_index is Some(_) { 0 } else { -33 }
  }
  record.lookup_input = Some(input)
  record.lookup_publisher = Some(publisher)
  let borrow = match
    @buffers.borrow_buffer(value.pool, slot, () => {
      physical_reader_stop(physical, handle) == 0
    }) {
    Ok(borrow) => borrow
    Err(issue) => {
      record.lookup_failed = true
      return issue_code(issue)
    }
  }
  record.lookup_borrow = Some(borrow)
  record.pending = true
  let result = match input_cursor(value, slot) {
    Some(cursor) =>
      match @decode.closed_object(cursor, ["identity", "index"]) {
        Ok(object) => {
          guard required_text(object, "identity") is Some(identity) &&
            required_text(object, "index") is Some(wire) &&
            @publication.admit_publication_contract(
              "public_index_entry", wire, 1048576, 100000, 64,
            )
            is Ok(index) &&
            commit.view_inspected_index_reference(view, identity, index, 0)
            is Ok(_) &&
            commit.view_inspected_index_reference(view, identity, index, 1)
            is Ok(_) else {
            record.pending = false
            record.lookup_failed = true
            return -32
          }
          record.lookup_identity = Some(identity)
          record.lookup_index = Some(index)
          0
        }
        Err(_) => -32
      }
    None => -32
  }
  record.pending = false
  if result != 0 {
    record.lookup_failed = true
    return result
  }
  publication_observation_publisher(
    value,
    record,
    publisher,
    current_configuration,
    None,
  )
}

///|
/// Return only this same original index borrow after observation and projected
/// reference loans finish cleanup. A stop failure keeps the handle/loan live.
/// The caller separately closes its original physical input; no Run is closed.
pub fn retire_publication_lookup(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.publications.get(handle) is Some(record) else {
    return -2
  }
  if record.pending {
    return -33
  }
  record.lookup_closing = true
  if record.observation_input is Some(_) ||
    value.commit_exports
    .values()
    .any(child => {
      child.publication == handle &&
      child.projection is Some(InspectedReference(_))
    }) {
    return -9
  }
  if record.lookup_borrow is Some(borrow) {
    let result = status(@buffers.return_buffer_borrow(value.pool, borrow))
    if result != 0 {
      return result
    }
    record.lookup_borrow = None
  }
  record.lookup_input = None
  record.lookup_publisher = None
  record.lookup_index = None
  record.lookup_identity = None
  record.lookup_failed = false
  record.lookup_closing = false
  0
}
