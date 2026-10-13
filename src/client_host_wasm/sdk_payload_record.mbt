///|
/// Couple existing Sealed payload validation with the existing selected read
/// binding. Neither a Python ordinal nor a different Result is read authority.
fn sdk_payload_record_binding_current(
  value : Instance,
  first : StoredPublicationCommitExport,
  context : OriginalSDKReadContext,
  payload_record : Int,
  result : Int,
  binding_index : Int,
  current_configuration : Int,
) -> Int {
  let code = validate_publication_commit_payload_binding(
    value.nonce,
    first.publication,
    payload_record,
    current_configuration,
    result,
    binding_index,
  )
  if code != 0 {
    return code
  }
  let binding = match context.owner.view_binding(context.view, binding_index) {
    Ok(binding) => binding
    Err(_) => return -32
  }
  let materials = match
    context.owner.observed_result_read_materials(
      context.view,
      context.result_name,
      8,
    ) {
    Ok(materials) => materials
    Err(_) => return -32
  }
  if @publication.publication_contract_identity(binding) !=
    materials.read.durable_result_binding_cid {
    return -32
  }
  0
}

///|
fn sdk_payload_record_current(
  value : Instance,
  first : StoredPublicationCommitExport,
  context : OriginalSDKReadContext,
  current_configuration : Int,
) -> Int {
  guard first.sdk_payload_record is Some((record, result, binding)) else {
    return -33
  }
  sdk_payload_record_binding_current(
    value, first, context, record, result, binding, current_configuration,
  )
}

///|
fn sdk_payload_finish_current(
  value : Instance,
  first : StoredPublicationCommitExport,
  context : OriginalSDKReadContext,
  current_configuration : Int,
) -> Int {
  match (context.check_current)() {
    Err(code) => return code
    Ok(_) => ()
  }
  sdk_payload_record_current(value, first, context, current_configuration)
}

///|
/// Retain the exact selected Sealed record until first-delivery full cleanup.
/// The physical Host keeps its matching original descriptor/generation facts.
/// Binding is not a new read grant or acknowledgement of any Store write.
#export_name("actql_publication_commit_export_bind_sdk_payload_record")
pub fn bind_publication_sdk_payload_record(
  nonce : Int64,
  first_handle : Int,
  payload_record : Int,
  current_configuration : Int,
  result : Int,
  binding_index : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.commit_exports.get(first_handle) is Some(first) &&
    first.sdk_payload_outcome is Some(Ok(_)) &&
    first.projection is Some(SDKReadDeliveryStorage(_, run)) else {
    return -2
  }
  if first.pending {
    return -5
  }
  let selected_record = (payload_record, result, binding_index)
  if first.sdk_payload_record is Some(original) && original != selected_record {
    return -33
  }
  let context = match
    original_sdk_read_context(value, first, run, current_configuration) {
    Ok(context) => context
    Err(code) => return code
  }
  let code = sdk_payload_record_binding_current(
    value, first, context, payload_record, result, binding_index, current_configuration,
  )
  if code != 0 {
    return code
  }
  // Register this borrow before an external current callback can close Source
  // custody. A denied callback retains it for explicit child-first cleanup.
  first.sdk_payload_record = Some(selected_record)
  first.pending = true
  let current = (context.check_current)()
  first.pending = false
  match current {
    Err(code) => return code
    Ok(_) => ()
  }
  sdk_payload_record_current(value, first, context, current_configuration)
}
