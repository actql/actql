///|
/// Nominal parent selection before output reservation, without physical IO or
/// a currentness claim. A lookup/admission-only handle cannot issue this child.
fn saved_result_export_parent(
  value : Instance,
  handle : Int,
) -> (StoredSubmissionProjection, StoredSavedResultRead)? {
  guard value.submissions.get(handle) is Some(parent) &&
    parent.kind == 6 &&
    parent.produced &&
    !parent.output_closed &&
    parent.saved_result is Some(saved) &&
    saved.complete &&
    saved.source is Some(_) &&
    saved.finite is Some(_) &&
    saved.owner is Some(_) &&
    saved.view is Some(_) else {
    return None
  }
  Some((parent, saved))
}

///|
/// Use the restored read-only origin, never a fabricated preflight or _Run.
/// The shared read/grant/delivery/codec Owners retain their current/expiry and
/// original-attempt rules. Every callback rechecks the actual same Store rows
/// and this original parent; no Source, Compute or submission can start here.
fn saved_sdk_read_context(
  value : Instance,
  record : StoredPublicationCommitExport,
  run : Int,
  current_configuration : Int,
) -> Result[OriginalSDKReadContext, Int] {
  guard run == record.publication &&
    saved_result_export_parent(value, record.publication)
    is Some((parent, saved)) &&
    parent.configuration == current_configuration &&
    value.run_configurations.get(current_configuration) is Some(current) &&
    current.sdk is Some(sdk) &&
    saved.source is Some(source) &&
    saved.finite is Some(finite) &&
    saved.owner is Some(owner) &&
    saved.view is Some(view) else {
    return Err(-2)
  }
  let (principal, connection, _, result_name, format, _, _) = @publication.local_sdk_result_read_selection_parameters(
    sdk.read,
  )
  if result_name != saved.result_name ||
    principal != current.tuple.principal ||
    connection != current.tuple.connection {
    return Err(-32)
  }
  let check_current = () => {
    if value.closing || value.runtime_closing || record.closing {
      return Err(-5)
    }
    match saved_result_export_parent(value, record.publication) {
      Some((actual, original)) if physical_equal(actual, parent) &&
        physical_equal(original, saved) => ()
      _ => return Err(-32)
    }
    match validate_saved_result_read(value, parent, current) {
      Err(code) => return Err(code)
      Ok(_) => ()
    }
    match
      @local_run.validate_local_sdk_read_source_current(
        source,
        current.account,
        result_name,
      ) {
      Err(Preflight(_)) => return Err(-35)
      Err(_) => return Err(-32)
      Ok(_) => ()
    }
    // This is the actual same Host/Store current port, not the saved Allow.
    match run_configuration_current(value, current) {
      Err(code) => Err(code)
      Ok(_) =>
        if record.closing || parent.output_closed {
          Err(-5)
        } else {
          Ok(())
        }
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
        check_current,
      })
  }
}
