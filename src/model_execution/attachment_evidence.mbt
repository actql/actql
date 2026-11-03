///|
// The additive evidence envelope is reserved before physical preparation,
// using the checked input contract rather than observed non-NULL rows.
fn model_attachment_evidence_bytes(
  task : @environment.ModelTaskContract,
) -> Int64 {
  guard @environment.model_task_input(task).shape is @contract.Object(fields) else {
    return 0L
  }
  for index in 0..<@contract.field_count(fields) {
    let field = @contract.field_at(fields, index).unwrap()
    if field.contract.shape is @contract.ContentRef(_) {
      return 16384L
    }
    if field.contract.shape is @contract.Array(item, ..) &&
      item.shape is @contract.ContentRef(_) {
      return 16384L
    }
  }
  0L
}

///|
// Retain only the original inventory already authenticated by Store custody.
// Its immutable body fits the same checked ContentRef evidence envelope; this
// does not construct another physical plan or grant an attachment acquisition.
fn restore_model_attachment_admission(
  capture : @publication.RunEvidenceValue,
  authority : @publication.RunEvidenceValue,
  admission : @publication.RunEvidenceValue?,
) -> Result[@publication.RunEvidenceValue?, ModelExecutionIssue] {
  @publication.verify_model_slot_attachment_admission(
    capture, authority, admission,
  )
  .map(_ => admission)
  .map_err(issue => InvocationEvidence(issue))
}

///|
/// Issue the ordered attachment inventory only from this physical owner's
/// validated plans and actual dispatch authority. This record is observation
/// evidence, not permission to dispatch again or a byte-custody lease.
pub fn model_execution_issued_attachment_admission(
  execution : ModelExecution,
  slot : Int,
) -> Result[@publication.RunEvidenceValue?, ModelExecutionIssue] {
  let state = execution.state
  if state.reclaimed {
    return Err(OutputIdentity)
  }
  guard state.attempts.get(slot) is Some(trace) else {
    return Err(OutputIdentity)
  }
  if state.restored_calls.get(slot) is Some(saved) {
    guard trace.evidence is Some(proof) &&
      physical_equal(proof, saved.proof) &&
      physical_equal(trace.authority, saved.proof.authority) &&
      physical_equal(
        @publication.bound_model_slot_capture_value(saved.binding),
        saved.record,
      ) else {
      return Err(OutputIdentity)
    }
    return restore_model_attachment_admission(
      saved.record,
      saved.proof.authority,
      saved.attachment_admission,
    )
  }
  guard state.physical_plans.get(slot) is Some(plan) else { return Ok(None) }
  if plan.attachments.is_empty() {
    return Ok(None)
  }
  try {
    let writer = @encode.writer(16384, 1024, 8)
    @encode.begin_object(writer)
    for
      (name, value) in [
        ("version", "actql-model-attachment-admission/0.1"),
        ("slot_cid", plan.request.slot_cid),
        ("model_task_cid", @environment.model_task_identity(state.task).2),
        ("fixed_request_cid", state.fixed_request_cid),
        (
          "authority_evidence_cid",
          @publication.run_evidence_value_identity(trace.authority),
        ),
      ] {
      @encode.key(writer, name)
      @encode.string_value(writer, value)
    }
    @encode.key(writer, "attachments")
    @encode.begin_array(writer)
    for admission in plan.attachments {
      let input = admission.input
      @encode.begin_object(writer)
      for
        (name, value) in [
          ("role", input.role),
          ("content_ref_cid", @admitted.reference_identity_cid(input.reference)),
          ("content_cid", input.content_cid),
          (
            "media_input_cid",
            @environment.model_dependency_identity(input.dependency),
          ),
          ("policy_cid", input.policy_cid),
          ("media_type", input.media_type),
          ("classification", input.classification),
          ("region", admission.region),
          ("egress_scope_cid", admission.egress_scope_cid),
          ("transfer_method", "inline_bytes"),
        ] {
        @encode.key(writer, name)
        @encode.string_value(writer, value)
      }
      @encode.key(writer, "item")
      @encode.number_value(writer, input.item.to_double())
      @encode.key(writer, "size_bytes")
      @encode.number_value(writer, input.size_bytes.to_double())
      @encode.key(writer, "complete")
      @encode.bool_value(writer, true)
      for
        (name, value) in [
          ("pages", admission.pages),
          ("frames", admission.frames),
        ] {
        @encode.key(writer, name)
        match value {
          Some(count) => @encode.number_value(writer, count.to_double())
          None => @encode.null_value(writer)
        }
      }
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    @encode.end_object(writer)
    @publication.seal_run_evidence_value(
      "model_attachment_admission",
      @encode.finish(writer),
      16384,
      1024,
      8,
    )
    .map(value => Some(value))
    .map_err(issue => InvocationEvidence(issue))
  } catch {
    _ => Err(OutputIdentity)
  }
}
