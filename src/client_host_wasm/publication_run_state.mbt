///|
/// Export a read-only observation from the original complete stored chain.
/// The Host holds the same current File/Store frame; Core independently checks
/// the original current supplier, publisher and Account run/read permission.
/// The timestamp input loan is retained until this output finishes cleanup.
#export_name("actql_publication_commit_export_produce_run_state")
pub fn produce_publication_observed_run_state(
  nonce : Int64,
  handle : Int,
  input : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.commit_exports.get(handle) is Some(record) &&
    value.publications.get(record.publication) is Some(parent) &&
    value.run_configurations.get(current_configuration) is Some(current) &&
    value.copies.get(input) is Some((slot, physical)) else {
    return -2
  }
  if record.closing ||
    record.output_closed ||
    parent.observation_closing ||
    parent.lookup_closing {
    return -5
  }
  match run_configuration_current(value, current) {
    Err(code) => return code
    Ok(_) => ()
  }
  let (commit, view) = match
    publication_commit_export_view(value, parent, current.account) {
    Ok(original) => original
    Err(code) => return code
  }
  guard value.publication_preflights.get(parent.preflight)
    is Some({ closing: false, preflight: Some(preflight), .. }) &&
    parent.observation_checked &&
    !parent.observation_failed &&
    parent.observation_index is Some(index) &&
    parent.observation_publisher is Some(publisher) else {
    return -32
  }
  if @local_run.validate_local_preflight_run_read_current(
      preflight,
      current.account,
    )
    is Err(_) {
    return -35
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
  // The publisher callback may observe an Account/Host change. Recheck the
  // independent read permission before every cached return or fresh output.
  match run_configuration_current(value, current) {
    Err(code) => return code
    Ok(_) => ()
  }
  if @local_run.validate_local_preflight_run_read_current(
      preflight,
      current.account,
    )
    is Err(_) {
    return -35
  }
  let projection = PublicationCommitExportProjection::ObservedRunState(input)
  if record.projection is Some(original) && original != projection {
    return -33
  }
  if record.produced {
    return 0
  }
  if record.invoked || record.pending {
    return -33
  }
  record.projection = Some(projection)
  record.invoked = true
  let borrow = match
    @buffers.borrow_buffer(value.pool, slot, () => {
      physical_reader_stop(physical, handle) == 0
    }) {
    Ok(borrow) => borrow
    Err(issue) => return issue_code(issue)
  }
  record.state_borrow = Some(borrow)
  guard input_cursor(value, borrow.slot) is Some(cursor) &&
    @decode.closed_object(cursor, ["observed_at"]) is Ok(object) &&
    required_text(object, "observed_at") is Some(observed_at) else {
    return -30
  }
  let wire = match
    commit.observed_run_state_wire(view, observed_at, 65536, 4096, 32) {
    Ok(wire) => wire
    Err(_) => return -32
  }
  record.pending = true
  let result = status(
    @buffers.supply_buffer_output(value.pool, record.slot, @utf8.encode(wire)),
  )
  record.pending = false
  if result == 0 {
    record.produced = true
  }
  result
}
