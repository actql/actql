///|
// Replace the original optional plan payload slot, without another normal
// holder. Ready has the old Some(plan) shape; Decoding's extra payload is paid
// before construction and retains the same original debt and previous plan.
priv enum StoredSubmissionAppend {
  Idle
  Decoding(@resources.CapacityReservation, StoredSubmissionAppend)
  DecodedRows(@resources.CapacityReservation, StoredSubmissionAppend, Int64)
  Ready(@host.ClientSubmittedJournalAppendPlan)
  NamedSubmissionObservation(@resources.CapacityReservation)
  NamedSubmissionAppend(StoredNamedSubmissionAppend)
  EffectProof(StoredEffectResolutionProof)
  EffectAttestationUse(StoredSavedEffectAttestationUse)
  EffectDecision(StoredSavedEffectDecision)
  EffectResumeClaim(StoredSavedEffectResumeClaim)
  EffectApplication(StoredSavedEffectApplication)
  EffectFileDispatch(StoredSavedEffectFileDispatch)
  EffectFileOperation(StoredSavedEffectFileOperation)
  EffectFileReplacement(StoredSavedEffectFileReplacement)
  EffectFileResponse(StoredSavedEffectFileResponse)
  EffectFileTerminal(StoredSavedEffectFileTerminal)
  EffectFileCompletion(StoredSavedEffectFileCompletion)
  EffectFilePublished(StoredSavedEffectFilePublished)
  EffectDecisionField(Int)
}

///|
/// Invocation custody only. Epoch authentication and durable clock custody
/// belong to the physical Host; Run admission remains a separate Owner call.
priv struct StoredSubmissionProjection {
  configuration : Int
  kind : Int
  borrow : Result[@buffers.BufferBorrow, @buffers.BufferIssue]
  slot : @buffers.BufferSlot
  mut saved_result : StoredSavedResultRead?
  mut saved_snapshot : @host.ClientSavedSubmissionSnapshot?
  mut append_plan : StoredSubmissionAppend
  mut append_reader_serial : Int64
  mut failure_preparation : Int?
  mut failure_plan : (@host.ClientJournalPhysicalRow, Bytes)?
  mut cancellation_append : StoredCancellationAppend?
  mut unpublished_state : StoredSDKUnpublishedState?
  mut invoked : Bool
  mut produced : Bool
  mut output_closed : Bool
}

///|
// The Saved reader advances in finite quanta under the same retained output.
const INCREMENTAL_SAVED_RESULT_KIND : Int = 13

///|
const SAVED_RESULT_COORDINATES_BYTES : Int = 245

///|
// The saved admission writer admits at most 4096 UTF-8 bytes. Allow six
// bytes for each escaped input byte plus the fixed ready-envelope fields.
const SAVED_RUN_ATTACHMENT_WIRE_BYTES : Int = 32768

///|
fn saved_result_projection_kind(kind : Int) -> Bool {
  kind == INCREMENTAL_SAVED_RESULT_KIND
}

///|
fn required_number(object : @decode.ObjectView, name : String) -> Double? {
  match @decode.required(object, name) {
    Ok(cursor) => @decode.finite_number(cursor).to_option()
    Err(_) => None
  }
}

///|
pub fn reserve_submission_projection(
  nonce : Int64,
  configuration : Int,
  input : Int,
  kind : Int,
  physical_ticket : Int,
  physical_copy_bytes : Int64,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.run_configurations.contains(configuration) &&
    value.copies.get(input) is Some((input_slot, physical)) else {
    return -2
  }
  if value.closing || value.runtime_closing {
    return -5
  }
  if (
      kind != 1 &&
      kind != 2 &&
      kind != 3 &&
      kind != 4 &&
      kind != 5 &&
      !saved_result_projection_kind(kind) &&
      kind != 7 &&
      kind != 8 &&
      kind != 9 &&
      kind != 10 &&
      kind != 11 &&
      kind != 12 &&
      kind != NAMED_SUBMISSION_KIND &&
      kind != NAMED_SUBMISSION_APPEND_KIND &&
      kind != SAVED_EFFECT_CHECKPOINT_PAGE_KIND &&
      kind != SAVED_EFFECT_CHECKPOINT_REVIEW_KIND &&
      kind != SAVED_EFFECT_RESOLUTION_PROOF_KIND &&
      kind != SAVED_EFFECT_ATTESTATION_USE_KIND &&
      kind != SAVED_EFFECT_DECISION_KIND &&
      kind != SAVED_EFFECT_DECISION_FIELD_KIND &&
      kind != SAVED_EFFECT_RESUME_KIND &&
      kind != SAVED_EFFECT_APPLICATION_KIND &&
      !saved_effect_file_dispatch_kind(kind) &&
      !saved_effect_file_operation_kind(kind) &&
      !saved_effect_file_response_kind(kind)
    ) ||
    physical_ticket <= 0 ||
    value.next_handle == 2147483647 ||
    value.copies.values().any(pair => pair.1 == physical_ticket) ||
    value.native_commands
    .values()
    .any(command => command.physical_ticket == physical_ticket) ||
    value.result_chunks
    .values()
    .any(chunk => chunk.physical_ticket == physical_ticket) ||
    value.workspaces.values().any(pair => pair.0 == physical_ticket) {
    return -3
  }
  let handle = value.next_handle
  let slot = match
    @buffers.reserve_output_buffer(
      value.pool,
      if kind == NAMED_SUBMISSION_KIND {
        NAMED_SUBMISSION_OUTPUT_LIMIT
      } else if kind == NAMED_SUBMISSION_APPEND_KIND {
        NAMED_SUBMISSION_APPEND_LIMIT
      } else if kind == SAVED_EFFECT_FILE_PUBLISHED_KIND {
        SAVED_EFFECT_FILE_PUBLISHED_HEADER
      } else if kind == SAVED_EFFECT_FILE_COMPLETION_KIND {
        SAVED_EFFECT_FILE_COMPLETION_HEADER
      } else if kind == SAVED_EFFECT_FILE_TERMINAL_KIND {
        SAVED_EFFECT_FILE_TERMINAL_HEADER
      } else if kind == SAVED_EFFECT_FILE_RESPONSE_KIND {
        SAVED_EFFECT_FILE_RESPONSE_HEADER
      } else if kind == SAVED_EFFECT_FILE_RESPONSE_FIELD_KIND {
        SAVED_EFFECT_DECISION_FIELD_MAX
      } else if kind == SAVED_EFFECT_FILE_OPERATION_KIND {
        SAVED_EFFECT_FILE_OPERATION_MAX
      } else if kind == SAVED_EFFECT_FILE_REPLACEMENT_KIND {
        4
      } else if kind == SAVED_EFFECT_FILE_DISPATCH_KIND {
        SAVED_EFFECT_FILE_DISPATCH_HEADER
      } else if kind == SAVED_EFFECT_FILE_DISPATCH_FIELD_KIND {
        SAVED_EFFECT_DECISION_FIELD_MAX
      } else if kind == SAVED_EFFECT_APPLICATION_KIND {
        8
      } else if kind == SAVED_EFFECT_DECISION_KIND ||
        kind == SAVED_EFFECT_RESUME_KIND {
        SAVED_EFFECT_DECISION_HEADER
      } else if kind == SAVED_EFFECT_DECISION_FIELD_KIND {
        SAVED_EFFECT_DECISION_FIELD_MAX
      } else if kind == SAVED_EFFECT_ATTESTATION_USE_KIND {
        SAVED_EFFECT_ATTESTATION_USE_MAX
      } else if kind == SAVED_EFFECT_RESOLUTION_PROOF_KIND {
        SAVED_EFFECT_RESOLUTION_PROOF_MAX
      } else if kind == SAVED_EFFECT_CHECKPOINT_REVIEW_KIND {
        SAVED_EFFECT_REVIEW_RESULT_MAX
      } else if kind == INCREMENTAL_SAVED_RESULT_KIND {
        SAVED_RESULT_COORDINATES_BYTES
      } else if kind == 7 {
        SAVED_SDK_RUN_STATE_MAX_BYTES
      } else if kind == 5 {
        SAVED_RUN_ATTACHMENT_WIRE_BYTES
      } else if kind >= 3 && kind <= SAVED_EFFECT_CHECKPOINT_PAGE_KIND {
        1048576
      } else {
        4096
      },
      physical_copy_bytes,
      () => physical_input_cleanup(physical_ticket) == 0,
    ) {
    Ok(slot) => slot
    Err(issue) => return issue_code(issue)
  }
  // Preserve output custody even when acquiring its input loan fails. The
  // producer returns that failure; only explicit close retires the output.
  let stopped = () => physical_reader_stop(physical, handle) == 0
  let borrow = if kind == SAVED_EFFECT_CHECKPOINT_REVIEW_KIND ||
    kind == SAVED_EFFECT_RESOLUTION_PROOF_KIND ||
    kind == SAVED_EFFECT_ATTESTATION_USE_KIND ||
    kind == SAVED_EFFECT_DECISION_KIND ||
    kind == SAVED_EFFECT_DECISION_FIELD_KIND ||
    kind == SAVED_EFFECT_RESUME_KIND ||
    kind == SAVED_EFFECT_APPLICATION_KIND ||
    saved_effect_file_dispatch_kind(kind) ||
    saved_effect_file_operation_kind(kind) ||
    saved_effect_file_response_kind(kind) {
    @buffers.borrow_filled_payload_input(value.pool, input_slot, stopped)
  } else {
    @buffers.borrow_buffer(value.pool, input_slot, stopped)
  }
  value.submissions[handle] = {
    configuration,
    kind,
    borrow,
    slot,
    saved_result: None,
    saved_snapshot: None,
    append_plan: Idle,
    append_reader_serial: 0L,
    failure_preparation: None,
    failure_plan: None,
    cancellation_append: None,
    unpublished_state: None,
    invoked: false,
    produced: false,
    output_closed: false,
  }
  value.copies[handle] = (slot, physical_ticket)
  value.next_handle += 1
  handle
}

///|
pub fn produce_submission_projection(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.submissions.get(handle) is Some(record) &&
    value.run_configurations.get(record.configuration) is Some(configuration) else {
    return -2
  }
  if record.kind == NAMED_SUBMISSION_KIND {
    return produce_named_submission_observation(value, record, configuration)
  }
  if record.kind == NAMED_SUBMISSION_APPEND_KIND {
    return prepare_named_submission_append(value, record, configuration)
  }
  if record.kind == SAVED_EFFECT_CHECKPOINT_PAGE_KIND {
    return produce_saved_effect_checkpoint_page(value, record, configuration)
  }
  if record.kind == SAVED_EFFECT_APPLICATION_KIND {
    return prepare_saved_effect_application(value, record, configuration)
  }
  if record.kind == SAVED_EFFECT_FILE_PUBLISHED_KIND {
    return produce_saved_effect_file_published(value, record, configuration)
  }
  if record.kind == SAVED_EFFECT_FILE_COMPLETION_KIND {
    return produce_saved_effect_file_completion(value, record, configuration)
  }
  if record.kind == SAVED_EFFECT_FILE_TERMINAL_KIND {
    return produce_saved_effect_file_terminal(value, record, configuration)
  }
  if record.kind == SAVED_EFFECT_FILE_RESPONSE_KIND {
    return produce_saved_effect_file_response(value, record, configuration)
  }
  if record.kind == SAVED_EFFECT_FILE_RESPONSE_FIELD_KIND {
    return produce_saved_effect_file_response_field(
      value, record, configuration,
    )
  }
  if record.kind == SAVED_EFFECT_FILE_OPERATION_KIND {
    return produce_saved_effect_file_operation(value, record, configuration)
  }
  if record.kind == SAVED_EFFECT_FILE_REPLACEMENT_KIND {
    return produce_saved_effect_file_replacement(value, record, configuration)
  }
  if record.kind == SAVED_EFFECT_FILE_DISPATCH_KIND {
    return produce_saved_effect_file_dispatch(value, record, configuration)
  }
  if record.kind == SAVED_EFFECT_FILE_DISPATCH_FIELD_KIND {
    return produce_saved_effect_file_dispatch_field(
      value, record, configuration,
    )
  }
  if record.kind == SAVED_EFFECT_RESUME_KIND {
    return produce_saved_effect_resume_claim(value, record, configuration)
  }
  if record.kind == SAVED_EFFECT_DECISION_KIND {
    return produce_saved_effect_decision(value, record, configuration)
  }
  if record.kind == SAVED_EFFECT_DECISION_FIELD_KIND {
    return produce_saved_effect_decision_field(value, record, configuration)
  }
  if record.kind == SAVED_EFFECT_ATTESTATION_USE_KIND {
    return produce_saved_effect_attestation_use(value, record, configuration)
  }
  if record.kind == SAVED_EFFECT_RESOLUTION_PROOF_KIND {
    return produce_saved_effect_resolution_proof(value, record, configuration)
  }
  if record.kind == SAVED_EFFECT_CHECKPOINT_REVIEW_KIND {
    return produce_saved_effect_checkpoint_review(value, record, configuration)
  }
  if record.kind == 10 {
    return produce_cancellation_append(value, record, configuration)
  }
  if record.kind == 12 {
    return produce_sdk_unpublished_run_state(value, record, configuration)
  }
  if record.kind == 9 {
    return produce_submission_preparation_failure(value, record, configuration)
  }
  if record.kind == 3 {
    return produce_submission_append(value, record, configuration)
  }
  if (record.kind >= 4 && record.kind <= 8) ||
    record.kind == 11 ||
    record.kind == INCREMENTAL_SAVED_RESULT_KIND {
    return produce_submission_lookup(value, record, configuration)
  }
  if record.produced {
    return 0
  }
  if record.invoked {
    return -33
  }
  if value.closing || value.runtime_closing || record.output_closed {
    return -5
  }
  match run_configuration_current(value, configuration) {
    Ok(_) => ()
    Err(code) => return code
  }
  record.invoked = true
  let borrow = match record.borrow {
    Ok(borrow) => borrow
    Err(issue) => return issue_code(issue)
  }
  guard @authorization.evaluate_account(
      configuration.account,
      configuration.tuple,
    )
    is @authorization.Allow(_) else {
    return -32
  }
  let fields = if record.kind == 1 {
    ["authority_scope_cid", "epoch_nonce", "not_before", "expires_at"]
  } else {
    [
      "authority_scope_cid", "epoch_nonce", "not_before", "expires_at", "caller_nonce",
      "now",
    ]
  }
  guard input_cursor(value, borrow.slot) is Some(cursor) &&
    @decode.closed_object(cursor, fields) is Ok(object) &&
    required_text(object, "authority_scope_cid") is Some(scope) &&
    required_text(object, "epoch_nonce") is Some(epoch_nonce) &&
    required_number(object, "not_before") is Some(not_before) &&
    required_number(object, "expires_at") is Some(expires_at) else {
    return -31
  }
  if scope != configuration.authority_scope_cid {
    return -32
  }
  let epoch = match
    @host.prepare_submission_epoch(scope, epoch_nonce, not_before, expires_at) {
    Ok(epoch) => epoch
    Err(_) => return -31
  }
  let identity = if record.kind == 2 {
    guard required_text(object, "caller_nonce") is Some(caller_nonce) &&
      required_number(object, "now") is Some(now) &&
      @host.submission_request_id(epoch, caller_nonce) is Ok(request_id) &&
      @host.submission_epoch_validity(epoch, now) is Ok(validity) else {
      return -31
    }
    Some(
      (
        request_id,
        match validity {
          @identity.Admissible => "admissible"
          @identity.NotYetValid => "not_yet_valid"
          @identity.Expired => "expired"
        },
      ),
    )
  } else {
    None
  }
  let writer = @encode.writer(4096, 8, 1) catch { _ => return -34 }
  let wire = try {
    @encode.begin_object(writer)
    @encode.key(writer, "epoch_cid")
    @encode.string_value(writer, @host.submission_epoch_cid(epoch))
    @encode.key(writer, "epoch_wire")
    @encode.string_value(writer, @host.submission_epoch_wire(epoch))
    if identity is Some((request_id, validity)) {
      @encode.key(writer, "request_id")
      @encode.string_value(writer, request_id)
      @encode.key(writer, "validity")
      @encode.string_value(writer, validity)
    }
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => return -34
  }
  let result = status(
    @buffers.supply_buffer_output(value.pool, record.slot, @utf8.encode(wire)),
  )
  if result == 0 {
    record.produced = true
  }
  result
}

///|
pub fn submission_projection_length(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.submissions.get(handle) is Some(record) else {
    return -2
  }
  if record.output_closed {
    return -5
  }
  if record.kind == 3 ||
    record.kind == NAMED_SUBMISSION_KIND ||
    record.kind == NAMED_SUBMISSION_APPEND_KIND ||
    record.kind == 4 ||
    record.kind == 5 ||
    saved_result_projection_kind(record.kind) ||
    record.kind == 7 ||
    record.kind == 8 ||
    record.kind == 10 ||
    record.kind == 11 ||
    record.kind == 12 ||
    record.kind == SAVED_EFFECT_CHECKPOINT_PAGE_KIND ||
    record.kind == SAVED_EFFECT_CHECKPOINT_REVIEW_KIND ||
    record.kind == SAVED_EFFECT_RESOLUTION_PROOF_KIND ||
    record.kind == SAVED_EFFECT_ATTESTATION_USE_KIND ||
    record.kind == SAVED_EFFECT_DECISION_KIND ||
    record.kind == SAVED_EFFECT_DECISION_FIELD_KIND ||
    record.kind == SAVED_EFFECT_RESUME_KIND ||
    record.kind == SAVED_EFFECT_APPLICATION_KIND ||
    saved_effect_file_dispatch_kind(record.kind) ||
    saved_effect_file_operation_kind(record.kind) ||
    saved_effect_file_response_kind(record.kind) {
    guard value.run_configurations.get(record.configuration)
      is Some(configuration) else {
      return -2
    }
    let current = if record.kind == 4 ||
      record.kind == 5 ||
      saved_result_projection_kind(record.kind) ||
      record.kind == 7 ||
      record.kind == 8 ||
      record.kind == 10 ||
      record.kind == 11 ||
      record.kind == 12 ||
      record.kind == SAVED_EFFECT_CHECKPOINT_PAGE_KIND ||
      record.kind == SAVED_EFFECT_CHECKPOINT_REVIEW_KIND ||
      record.kind == SAVED_EFFECT_RESOLUTION_PROOF_KIND ||
      record.kind == SAVED_EFFECT_ATTESTATION_USE_KIND ||
      record.kind == SAVED_EFFECT_DECISION_KIND ||
      record.kind == SAVED_EFFECT_DECISION_FIELD_KIND ||
      record.kind == SAVED_EFFECT_RESUME_KIND ||
      record.kind == SAVED_EFFECT_APPLICATION_KIND ||
      saved_effect_file_dispatch_kind(record.kind) ||
      saved_effect_file_operation_kind(record.kind) ||
      saved_effect_file_response_kind(record.kind) {
      submission_lookup_current(value, record, configuration)
    } else {
      submission_append_current(value, record, configuration)
    }
    match current {
      Ok(_) => ()
      Err(code) => return code
    }
  }
  match @buffers.buffer_length(value.pool, record.slot) {
    Some(length) => length
    None => -33
  }
}

///|
/// Retire the consumed transport; the original reference/intent input borrow
/// remains available to internal same-Store observation until full close.
pub fn retire_submission_output(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.submissions.get(handle) is Some(record) else {
    return -2
  }
  if record.kind == INCREMENTAL_SAVED_RESULT_KIND {
    return retire_saved_result_transport(value, handle, record)
  }
  guard record.kind == 3 && record.produced && record.append_plan is Ready(_) else {
    return -2
  }
  if value.publication_preflights
    .values()
    .any(child => {
      child.origin is SavedEffectPublicationPreflight(original) &&
      original.source == handle
    }) ||
    value.commit_exports.values().any(child => child.publication == handle) ||
    value.payload_records.values().any(child => child.request == handle) {
    return -9
  }
  if record.output_closed {
    return 0
  }
  let code = status(@buffers.close_buffer(value.pool, record.slot))
  if code != 0 {
    return code
  }
  record.output_closed = true
  value.copies.remove(handle) |> ignore
  0
}

///|
pub fn close_submission_projection(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.submissions.get(handle) is Some(record) else {
    return -2
  }
  if value.commit_exports.values().any(child => child.publication == handle) ||
    value.payload_records.values().any(child => child.request == handle) ||
    value.preparations
    .values()
    .any(preparation => {
      preparation.project_request is Some(request) &&
      request.submission is Some((original, _)) &&
      original == handle
    }) {
    return -9
  }
  if value.runs.values().any(run => run.sdk_submission == Some(handle)) ||
    value.restorations
    .values()
    .any(restoration => restoration.sdk_submission == Some(handle)) {
    return -9
  }
  if value.submissions
    .values()
    .any(child => {
      match child.append_plan {
        EffectAttestationUse(use_entry) => use_entry.parent == handle
        EffectDecision(decision) => decision.parent == handle
        EffectResumeClaim(claim) => claim.parent == handle
        EffectApplication(plan) => plan.parent == handle
        EffectFileDispatch(plan) => plan.parent == handle
        EffectFileOperation(plan) => plan.parent == handle
        EffectFileReplacement(plan) => plan.parent == handle
        EffectFileResponse(plan) => plan.parent == handle
        EffectFileTerminal(plan) => plan.parent == handle
        EffectFileCompletion(plan) => plan.parent == handle
        EffectFilePublished(plan) => plan.parent == handle
        EffectDecisionField(parent) => parent == handle
        _ => false
      }
    }) {
    return -9
  }
  let decoded = close_submission_decode_prefix(value, record)
  if decoded != 0 {
    return decoded
  }
  if !record.output_closed {
    let result = status(@buffers.close_buffer(value.pool, record.slot))
    if result != 0 {
      return result
    }
    record.output_closed = true
  }
  let closed = close_saved_result_read(value, record)
  if closed != 0 {
    return closed
  }
  let closed = close_cancellation_append(record)
  if closed != 0 {
    return closed
  }
  let closed = close_sdk_unpublished_run_state(record)
  if closed != 0 {
    return closed
  }
  let result = match record.borrow {
    Ok(borrow) => status(@buffers.return_buffer_borrow(value.pool, borrow))
    Err(_) => 0
  }
  if result == 0 {
    value.submissions.remove(handle) |> ignore
    value.copies.remove(handle) |> ignore
  }
  result
}

///|
/// The trusted serialized Host calls this only after the original synchronous
/// Wasm invocation has unwound, before terminal child-first cleanup. A trap
/// cannot run the pending=false continuation. These flags exclude a live call;
/// they are not physical stop, transaction, buffer, or parent acknowledgments.
/// Spend normal entry first, then retire only this saved parent's call latches.
pub fn begin_submission_cleanup(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.submissions.get(handle) is Some(parent) &&
    saved_result_projection_kind(parent.kind) else {
    return -2
  }
  value.closing = true
  for record in value.payload_records.values() {
    if record.source is SavedResult(actual, _) && physical_equal(actual, parent) {
      record.closing = true
      record.pending = false
    }
  }
  for record in value.commit_exports.values() {
    if record.publication == handle {
      record.closing = true
      record.pending = false
    }
  }
  0
}
