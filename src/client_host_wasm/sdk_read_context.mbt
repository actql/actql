///|
/// Ephemeral projection of the original Run/commit/current Owners. This is
/// neither a registry nor permission; every consumer must recheck the callback.
priv struct OriginalSDKReadContext {
  source : @local_run.LocalSDKReadSource
  finite : @host.ClientLocalRunPolicyOriginal
  sdk : StoredSDKRunConfiguration
  current : StoredRunConfiguration
  owner : @publication.PublicationCommitPreparation
  view : @publication.PublicationCommitReadView
  result_name : String
  format : String
  // Enables a fresh probe against the enclosing export's first census.
  // The physical reader still decides whether any repeated scan is needed.
  same_reader_census : Bool
  check_current : () -> Result[Unit, Int]
}

///|
fn sdk_read_request_fields(
  value : Instance,
  slot : @buffers.BufferSlot,
) -> @decode.ObjectView? {
  guard input_cursor(value, slot) is Some(cursor) else { return None }
  match
    @decode.closed_object(cursor, [
      "result_name", "format", "attempt_id", "observed_at",
    ]) {
    Ok(request) => Some(request)
    Err(_) => None
  }
}

///|
fn original_sdk_read_context(
  value : Instance,
  record : StoredPublicationCommitExport,
  run : Int,
  current_configuration : Int,
  same_reader_census? : Bool = false,
  request_input? : @buffers.BufferSlot? = None,
) -> Result[OriginalSDKReadContext, Int] {
  if value.publications.get(record.publication) is None {
    return saved_sdk_read_context(
      value,
      record,
      run,
      current_configuration,
      same_reader_census~,
    )
  }
  guard value.publications.get(record.publication) is Some(parent) &&
    value.runs.get(run) is Some(original_run) &&
    original_run.finite_policy is Some(finite) &&
    value.run_configurations.get(original_run.configuration)
    is Some(original_configuration) &&
    original_configuration.sdk is Some(sdk) &&
    value.run_configurations.get(current_configuration) is Some(current) &&
    current.sdk is Some(current_sdk) else {
    return Err(-2)
  }
  if value.closing ||
    value.runtime_closing ||
    record.closing ||
    parent.observation_closing ||
    parent.lookup_closing {
    return Err(-5)
  }
  if current_sdk.adoption_cid != sdk.adoption_cid ||
    current_sdk.store_authority_cid != sdk.store_authority_cid ||
    @publication.local_sdk_result_read_selection_cid(current_sdk.read) !=
    @publication.local_sdk_result_read_selection_cid(sdk.read) {
    return Err(-32)
  }
  let code = validate_publication_run(
    value.nonce,
    record.publication,
    run,
    current_configuration,
  )
  if code != 0 {
    return Err(code)
  }
  let (owner, view) = match
    publication_commit_export_view(value, parent, current.account) {
    Ok(original) => original
    Err(code) => return Err(code)
  }
  guard value.publication_preflights.get(parent.preflight)
    is Some({ closing: false, preflight: Some(preflight), .. }) &&
    parent.observation_checked &&
    !parent.observation_failed &&
    parent.observation_index is Some(index) &&
    parent.observation_publisher is Some(publisher) else {
    return Err(-32)
  }
  let (principal, connection, _, fixed_name, format, _, _) = @publication.local_sdk_result_read_selection_parameters(
    sdk.read,
  )
  if principal != current.tuple.principal ||
    connection != current.tuple.connection {
    return Err(-32)
  }
  let result_name = match fixed_name {
    Some(name) => name
    None => {
      // The initial call only selects a name from the sealed input. It still
      // validates the exact name after borrowing that same request. Later
      // exports use the retained borrow from the original delivery.
      let selected = match record.state_borrow {
        Some(original) => Some(original.slot)
        None => request_input
      }
      guard selected is Some(slot) &&
        sdk_read_request_fields(value, slot) is Some(request) &&
        required_text(request, "result_name") is Some(name) &&
        !name.is_empty() else {
        return Err(-30)
      }
      name
    }
  }
  let source = @local_run.local_sdk_read_source(preflight, selection=sdk.read)
  let check_current = () => {
    if value.closing ||
      value.runtime_closing ||
      record.closing ||
      parent.closing ||
      parent.observation_closing ||
      parent.lookup_closing {
      return Err(-5)
    }
    match run_configuration_current(value, current) {
      Err(code) => return Err(code)
      Ok(_) => ()
    }
    if @local_run.validate_local_sdk_read_source_current(
        source,
        current.account,
        result_name,
      )
      is Err(_) {
      return Err(-35)
    }
    let auth = publication_observation_publisher(
      value,
      parent,
      publisher,
      current_configuration,
      Some(index),
    )
    if auth != 0 {
      return Err(auth)
    }
    match run_configuration_current(value, current) {
      Err(code) => return Err(code)
      Ok(_) => ()
    }
    if value.closing ||
      value.runtime_closing ||
      record.closing ||
      parent.closing ||
      parent.observation_closing ||
      parent.lookup_closing {
      return Err(-5)
    }
    if @local_run.validate_local_sdk_read_source_current(
        source,
        current.account,
        result_name,
      )
      is Err(_) {
      return Err(-35)
    }
    match publication_commit_export_view(value, parent, current.account) {
      Err(code) => Err(code)
      Ok(_) => Ok(())
    }
  }
  match check_current() {
    Err(code) => Err(code)
    Ok(_) =>
      Ok({
        source,
        finite,
        sdk,
        current,
        owner,
        view,
        result_name,
        format,
        same_reader_census: false,
        check_current,
      })
  }
}
