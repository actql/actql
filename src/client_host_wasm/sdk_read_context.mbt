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
  check_current : () -> Result[Unit, Int]
}

///|
fn original_sdk_read_context(
  value : Instance,
  record : StoredPublicationCommitExport,
  run : Int,
  current_configuration : Int,
) -> Result[OriginalSDKReadContext, Int] {
  if value.publications.get(record.publication) is None {
    return saved_sdk_read_context(value, record, run, current_configuration)
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
  let (principal, connection, _, result_name, format, _, _) = @publication.local_sdk_result_read_selection_parameters(
    sdk.read,
  )
  if principal != current.tuple.principal ||
    connection != current.tuple.connection {
    return Err(-32)
  }
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
    if @local_run.validate_local_preflight_result_read_current(
        preflight,
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
    if @local_run.validate_local_preflight_result_read_current(
        preflight,
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
        source: @local_run.local_sdk_read_source(preflight),
        finite,
        sdk,
        current,
        owner,
        view,
        result_name,
        format,
        check_current,
      })
  }
}
