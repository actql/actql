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
  if value.payload_records.get(payload_record) is Some(payload) {
    if payload.source is SavedResult(parent, saved) {
      guard saved_result_export_parent(value, first.publication)
        is Some((actual, original)) &&
        physical_equal(parent, actual) &&
        physical_equal(saved, original) &&
        first.sdk_payload_outcome is Some(Ok(encoding)) else {
        return -32
      }
      let ordinals = match
        encoding.stored_payload_ordinals(
          context.owner,
          context.view,
          context.result_name,
          8,
          256,
        ) {
        Ok(value) => value
        Err(_) => return -32
      }
      if ordinals != (result, binding_index) {
        return -32
      }
      match saved_payload_binding(value, payload, current_configuration) {
        Ok(binding) => {
          let selected = match
            context.owner.view_binding(context.view, binding_index) {
            Ok(value) => value
            Err(_) => return -32
          }
          if @publication.publication_contract_json(binding) !=
            @publication.publication_contract_json(selected) {
            return -32
          }
        }
        Err(code) => return code
      }
    } else {
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
    }
  } else {
    return -2
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

///|
/// Routing coordinates only, rechecked under the original Run/current Owner.
/// The physical Host must bind the exact original record and current six facts
/// before byte access. field=0 selects Result, field=1 its durable binding.
pub fn publication_sdk_payload_ordinal(
  nonce : Int64,
  first_handle : Int,
  current_configuration : Int,
  field : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.commit_exports.get(first_handle) is Some(first) &&
    first.sdk_payload_outcome is Some(Ok(encoding)) &&
    first.projection is Some(SDKReadDeliveryStorage(_, run)) else {
    return -2
  }
  if field != 0 && field != 1 {
    return -3
  }
  if first.pending {
    return -5
  }
  let context = match
    original_sdk_read_context(value, first, run, current_configuration) {
    Ok(context) => context
    Err(code) => return code
  }
  first.pending = true
  let before = (context.check_current)()
  first.pending = false
  match before {
    Err(code) => return code
    Ok(_) => ()
  }
  let selected = match value.publications.get(first.publication) {
    Some(parent) =>
      encoding.original_payload_ordinals(
        context.owner,
        context.view,
        parent.publications,
        context.result_name,
        8,
      )
    None =>
      encoding.stored_payload_ordinals(
        context.owner,
        context.view,
        context.result_name,
        8,
        256,
      )
  }
  let (result, binding) = match selected {
    Ok(value) => value
    Err(_) => return -32
  }
  first.pending = true
  let after = (context.check_current)()
  first.pending = false
  match after {
    Err(code) => return code
    Ok(_) => ()
  }
  if field == 0 {
    result
  } else {
    binding
  }
}
