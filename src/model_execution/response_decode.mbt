///|
// These are child cursors of the original Model execution, not another request
// or execution owner. The full encoded text, trees and checked output overlap
// until retirement and must be included in original Run funding.
priv enum ModelResponseDecodePhase {
  ReadChat(ChatEnvelopeDecode)
  ReadNative(NativeEnvelopeDecode, ModelPhysicalNativeResponse)
  ParseNativeAnswer(
    @source.JsonParse,
    NativeDecisionRequest,
    @environment.DecisionProbabilityProfile
  )
  AdmitNativeAnswer(
    @decode.Admission,
    NativeDecisionRequest,
    @environment.DecisionProbabilityProfile
  )
  ParseAnswer(@source.JsonParse)
  AdmitAnswer(@decode.Admission)
  TypeAnswer(@admitted.TypedAdmission)
  DecodeReclaimed
}

///|
priv struct ModelResponseDecode {
  mut phase : ModelResponseDecodePhase
  limits : @environment.ModelResponseProfileLimits
  mut remaining : Int
  mut raw_chat : ModelPhysicalChatResponse?
  mut observation : @publication.ModelCaptureObservation?
}

///|
fn cancel_model_response_decode(
  cursor : ModelResponseDecode,
  preserve_observation? : Bool = false,
) -> Unit {
  match cursor.phase {
    ReadChat(chat) => cancel_chat_envelope_decode(chat)
    ReadNative(child, _) => cancel_native_envelope_decode(child)
    ParseNativeAnswer(parse, _, _) => @source.cancel_json_parse(parse)
    AdmitNativeAnswer(admit, _, _) => @decode.cancel_admission(admit)
    ParseAnswer(parse) => @source.cancel_json_parse(parse)
    AdmitAnswer(admission) => @decode.cancel_admission(admission)
    TypeAnswer(admission) => @admitted.cancel_typed_admission(admission)
    DecodeReclaimed => ()
  }
  cursor.phase = DecodeReclaimed
  if !preserve_observation {
    cursor.raw_chat = None
    cursor.observation = None
  }
}

///|
fn begin_encoded_model_response(
  state : ModelState,
  prepared : PreparedModelRequest,
  physical : ModelPhysicalEncodedResponse,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[ModelCaptureBundle, ModelExecutionIssue] {
  if @bounded.stop_requested(reader) is Some(reason) {
    return @bounded.Stopped(reason, 1, 1)
  }
  guard state.physical_plans.get(prepared.request.slot) is Some(plan) &&
    plan.response_profile is Some(profile) &&
    valid_reported_model_observation(
      profile,
      physical.observation,
      physical.transport_eof,
      physical.endpoint_complete,
      physical.answer_complete,
    ) else {
    return @bounded.Failed(OutputIdentity, 1, 1)
  }
  let limits = @environment.model_response_profile_limits(profile)
  let parse = match
    @source.start_json_parse(
      physical.body,
      {
        max_input_bytes: limits.response_bytes,
        max_nodes: limits.parse_nodes,
        max_depth: limits.parse_depth,
      },
      data_keys=true,
    ) {
    Ok(parse) => parse
    Err(issue) =>
      return @bounded.Failed(model_response_source_issue(issue.issue), 1, 1)
  }
  state.progress.phase = DecodePhysicalResponse(prepared, physical, {
    phase: ParseAnswer(parse),
    limits,
    remaining: limits.parse_work,
    raw_chat: None,
    observation: None,
  })
  @bounded.Continue(1, 1)
}

///|
fn advance_encoded_model_response(
  state : ModelState,
  prepared : PreparedModelRequest,
  physical : ModelPhysicalEncodedResponse,
  cursor : ModelResponseDecode,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[ModelCaptureBundle, ModelExecutionIssue] {
  if cursor.phase is ReadChat(chat) {
    return advance_chat_model_response(state, cursor, chat)
  }
  if cursor.phase is ReadNative(child, native) {
    return advance_native_model_response(state, cursor, child, native)
  }
  // Recheck the same original tuple at every native child boundary. A retired
  // request or foreign terminal cannot acquire completion via a parsed answer.
  match cursor.phase {
    ParseNativeAnswer(_, original, probability)
    | AdmitNativeAnswer(_, original, probability) => {
      guard state.progress.call is Some(call) &&
        call.terminal is Some(PhysicalNativeResponse(native)) &&
        physical_equal(original, native.original) &&
        physical_equal(probability, native.probability) &&
        model_native_response_original(native, call) else {
        return @bounded.Failed(RequestIdentity, 1, 1)
      }
    }
    _ => ()
  }
  match
    advance_model_response_decode(
      cursor,
      @environment.model_task_output(state.task),
      state.limits.value_limits,
    ) {
    Err(Provider(SchemaInvalid)) =>
      adopt_invalid_saved_model_answer(state, cursor)
    Err(issue) => @bounded.Failed(issue, 1, 1)
    Ok(None) => @bounded.Continue(1, 1)
    Ok(Some(checked)) => {
      guard state.progress.call is Some(call) else {
        return @bounded.Failed(RequestIdentity, 1, 1)
      }
      let observation = match (call.terminal, cursor.raw_chat) {
        (Some(PhysicalEncodedResponse(original)), None) if physical_equal(
            original, physical,
          ) => physical.observation
        (Some(PhysicalSavedStructuredResponse(saved)), None) if saved.result
          is Ok(encoded) &&
          physical_equal(encoded, physical) &&
          model_saved_structured_response_original(saved, call) =>
          physical.observation
        (Some(PhysicalChatResponse(original)), Some(raw)) if physical_equal(
            original, raw,
          ) => {
          guard cursor.observation is Some(observation) else {
            return @bounded.Failed(RequestIdentity, 1, 1)
          }
          { ..observation, response_complete: Some(true), }
        }
        (Some(PhysicalNativeResponse(native)), Some(raw)) if physical_equal(
            native.raw,
            raw,
          ) &&
          model_native_response_original(native, call) => {
          guard cursor.observation is Some(observation) else {
            return @bounded.Failed(RequestIdentity, 1, 1)
          }
          { ..observation, response_complete: Some(true), }
        }
        _ => return @bounded.Failed(RequestIdentity, 1, 1)
      }
      let decoded : ModelPhysicalResponse = {
        value: checked.value,
        observation,
        transport_eof: physical.transport_eof,
        endpoint_complete: cursor.raw_chat is Some(_) ||
        physical.endpoint_complete,
        answer_complete: true,
      }
      // Transfer the selected observation before retiring the child aliases.
      // The original physical terminal still owns its separate raw custody.
      cancel_model_response_decode(cursor)
      call.decoded_response = Some(decoded)
      // Only initialize metadata/value admission here. Its first transition
      // belongs to the next original Model advance.
      begin_reported_model_response(state, prepared, decoded, reader)
    }
  }
}

///|
fn advance_model_response_decode(
  cursor : ModelResponseDecode,
  output : @contract.Contract,
  value_limits : @admitted.Limits,
) -> Result[@admitted.CheckedValue?, ModelExecutionIssue] {
  if cursor.phase is DecodeReclaimed {
    return Err(OutputIdentity)
  }
  if cursor.remaining <= 0 {
    cancel_model_response_decode(cursor)
    return Err(WorkLimit)
  }
  cursor.remaining -= 1
  match cursor.phase {
    // Envelope transitions are driven by the original execution, so observed
    // usage is accounted before a refusal or cancellation can end this child.
    ReadChat(_) | ReadNative(_, _) => return Err(OutputIdentity)
    ParseNativeAnswer(parse, original, probability) =>
      match @source.advance_json_parse(parse, 1) {
        Ok(@source.JsonParseContinue(..)) => ()
        Ok(@source.JsonParseComplete(source, ..)) => {
          let admit = match
            @decode.start_admission(source.node, {
              max_nodes: cursor.limits.parse_nodes,
              max_depth: cursor.limits.parse_depth,
              max_string_bytes: cursor.limits.response_bytes,
              max_total_string_bytes: cursor.limits.response_bytes,
            }) {
            Ok(admit) => admit
            Err(_) => return Err(OutputValue)
          }
          cursor.phase = AdmitNativeAnswer(admit, original, probability)
        }
        _ => {
          cancel_model_response_decode(cursor)
          return Err(OutputValue)
        }
      }
    AdmitNativeAnswer(admit, original, probability) =>
      match @decode.advance_admission(admit, 1) {
        Ok(@decode.AdmissionContinue(..)) => ()
        Ok(@decode.AdmissionComplete(source, ..)) => {
          guard original.decision is Some(decision) else {
            return Err(RequestIdentity)
          }
          let work = match
            @environment.validate_decision_answers(
              decision,
              source,
              probability,
              cursor.remaining,
            ) {
            Ok(work) => work
            Err({ kind: WorkLimit, .. }) => return Err(WorkLimit)
            Err(_) => return Err(OutputValue)
          }
          cursor.remaining -= work
          let typed = match
            @admitted.start_typed_admission(output, source, value_limits) {
            Ok(typed) => typed
            Err(_) => return Err(OutputValue)
          }
          cursor.phase = TypeAnswer(typed)
        }
        _ => {
          cancel_model_response_decode(cursor)
          return Err(OutputValue)
        }
      }
    ParseAnswer(parse) =>
      match @source.advance_json_parse(parse, 1) {
        Ok(@source.JsonParseContinue(..)) => ()
        Ok(@source.JsonParseComplete(source, ..)) => {
          let admission = match
            @decode.start_admission(source.node, {
              max_nodes: cursor.limits.parse_nodes,
              max_depth: cursor.limits.parse_depth,
              max_string_bytes: cursor.limits.response_bytes,
              max_total_string_bytes: cursor.limits.response_bytes,
            }) {
            Ok(admission) => admission
            Err(issue) =>
              return fail_model_answer_decode(
                cursor,
                model_answer_decode_issue(
                  model_response_admission_issue(issue.kind),
                ),
              )
          }
          cursor.phase = AdmitAnswer(admission)
        }
        Ok(@source.JsonParseFailed(issue, ..)) =>
          return fail_model_answer_decode(
            cursor,
            model_answer_decode_issue(model_response_source_issue(issue.issue)),
          )
        Err(_) => return fail_model_answer_decode(cursor, OutputIdentity)
      }
    AdmitAnswer(admission) =>
      match @decode.advance_admission(admission, 1) {
        Ok(@decode.AdmissionContinue(..)) => ()
        Ok(@decode.AdmissionComplete(source, ..)) => {
          let typed = match
            @admitted.start_typed_admission(output, source, value_limits) {
            Ok(typed) => typed
            Err(issue) =>
              return fail_model_answer_decode(
                cursor,
                model_answer_typed_issue(issue),
              )
          }
          cursor.phase = TypeAnswer(typed)
        }
        Ok(@decode.AdmissionFailed(issue, ..)) =>
          return fail_model_answer_decode(
            cursor,
            model_answer_decode_issue(
              model_response_admission_issue(issue.kind),
            ),
          )
        Err(_) => return fail_model_answer_decode(cursor, OutputIdentity)
      }
    TypeAnswer(typed) =>
      match @admitted.advance_typed_admission(typed) {
        @admitted.TypedAdmissionContinue => ()
        @admitted.TypedAdmissionComplete(checked, _, _) => {
          // The parent consumes selected raw observations with this answer;
          // parser reclamation alone cannot drop them before that transfer.
          cancel_model_response_decode(cursor, preserve_observation=true)
          return Ok(Some(checked))
        }
        @admitted.TypedAdmissionFailed(issue) =>
          return fail_model_answer_decode(
            cursor,
            model_answer_typed_issue(issue),
          )
        @admitted.TypedAdmissionTerminal =>
          return fail_model_answer_decode(cursor, OutputIdentity)
      }
    DecodeReclaimed => return Err(OutputIdentity)
  }
  Ok(None)
}

///|
// Only a structural answer failure needs the original observation for
// provider settlement. Release the answer cursor on engine refusals now.
fn fail_model_answer_decode(
  cursor : ModelResponseDecode,
  issue : ModelExecutionIssue,
) -> Result[@admitted.CheckedValue?, ModelExecutionIssue] {
  if !(issue is Provider(SchemaInvalid)) {
    cancel_model_response_decode(cursor)
  }
  Err(issue)
}

///|
// Bounded usage readers share the same source and admission owners. An
// exhausted budget or a noncurrent cursor cannot make a provider failure.
fn model_response_source_issue(
  issue : @source.ParseIssue,
) -> ModelExecutionIssue {
  match issue {
    @source.InvalidLimits => InvalidLimits
    @source.InputLimit | @source.NodeLimit | @source.DepthLimit => WorkLimit
    _ => OutputValue
  }
}

///|
fn model_response_admission_issue(
  issue : @decode.IssueKind,
) -> ModelExecutionIssue {
  match issue {
    @decode.InvalidLimits => InvalidLimits
    @decode.BudgetExceeded => WorkLimit
    _ => OutputValue
  }
}

///|
// Use this internal classification only for an actual structural failure.
// Whether it is a provider outcome is decided by the original carrier.
fn model_answer_decode_issue(
  issue : ModelExecutionIssue,
) -> ModelExecutionIssue {
  match issue {
    OutputValue => Provider(SchemaInvalid)
    _ => issue
  }
}

///|
fn model_answer_typed_issue(issue : @admitted.Issue) -> ModelExecutionIssue {
  match issue {
    @admitted.Decode(issue) =>
      model_answer_decode_issue(model_response_admission_issue(issue.kind))
    @admitted.ValueIssue(InvalidLimits, ..) => InvalidLimits
    @admitted.ValueIssue(BudgetExceeded, ..) => WorkLimit
    @admitted.ValueIssue(
      UnsupportedReference
      | InvalidReference
      | UnauthorizedReference,
      ..
    ) => OutputIdentity
    @admitted.ValueIssue(_, ..) => Provider(SchemaInvalid)
  }
}

///|
fn adopt_invalid_saved_model_answer(
  state : ModelState,
  cursor : ModelResponseDecode,
) -> @bounded.KernelStep[ModelCaptureBundle, ModelExecutionIssue] {
  let invalid = @bounded.Failed(OutputIdentity, 1, 1)
  guard state.progress.call is Some(call) else { return invalid }
  match (call.terminal, cursor.raw_chat) {
    (Some(PhysicalSavedStructuredResponse(saved)), None) if model_saved_structured_response_original(
        saved, call,
      ) => ()
    (Some(PhysicalChatResponse(original)), Some(raw)) if physical_equal(
        original, raw,
      ) &&
      model_chat_response_original(raw, call) &&
      raw.transport_eof &&
      raw.status >= 200 &&
      raw.status < 300 => {
      guard cursor.observation is Some(observation) &&
        state.physical_plans.get(state.progress.slot) is Some(plan) &&
        plan.response_profile is Some(profile) else {
        return invalid
      }
      retain_chat_failure_observation(raw, observation, profile)
    }
    _ => {
      cancel_model_response_decode(cursor)
      return @bounded.Failed(OutputValue, 1, 1)
    }
  }
  cancel_model_response_decode(cursor)
  accept_structured_model_failure(state, SchemaInvalid)
}
