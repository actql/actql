///|
priv enum OpenAIProjectionPhase {
  Schema(@encode.Writer, @contract.CheckedEmission)
  InputStart(String)
  InputRole(String, @encode.Writer, Int)
  InputKey(String, @encode.Writer, Int, @encode.OrderedKeyEmitCursor)
  InputValue(String, @encode.Writer, Int, @admitted.WireEmitCursor)
  Ready((String, String, String, String, String, String, String))
  Failed(OpenAIChatProjectionIssue)
  Retired
}

///|
/// Read-only child of the existing Model preparation, never an execution or
/// funding owner. Original inputs and writers remain borrowed until retirement.
struct OpenAIChatProjection {
  mut request : ModelRequest?
  mut instructions : String?
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_frames : Int
  max_work : Int
  mut work : Int
  mut phase : OpenAIProjectionPhase
}

///|
pub fn start_openai_chat_projection(
  provider : AdmittedModelProvider,
  request : ModelRequest,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_frames : Int,
  max_work : Int,
) -> Result[OpenAIChatProjection, OpenAIChatProjectionIssue] {
  let task = @environment.model_execution_task(provider.execution)
  if !physical_equal(task, request.task) ||
    !@environment.single_attempt_model_dependencies_match(
      provider.dependencies,
      provider.execution,
    ) {
    return Err(ForeignRequest)
  }
  if @environment.model_task_kind(task) != @environment.StructuredGenerate {
    return Err(Unsupported)
  }
  let prompt = @environment.single_attempt_model_prompt(provider.dependencies)
  let instructions = match @environment.model_openai_chat_instructions(prompt) {
    Some(value) => value
    None => return Err(Unsupported)
  }
  if max_bytes < 1 ||
    max_nodes < 1 ||
    max_depth < 1 ||
    max_frames < 1 ||
    max_work < 0 ||
    instructions.length() > max_work {
    return Err(Limit)
  }
  try {
    let writer = @encode.writer(max_bytes, max_nodes, max_depth)
    let emission = match
      @contract.start_json_schema_emission(
        @environment.model_task_output(task),
        writer,
        max_frames,
      ) {
      Ok(value) => value
      Err(@contract.Unsupported) => return Err(Unsupported)
      Err(_) => return Err(Limit)
    }
    Ok({
      request: Some(request),
      instructions: Some(instructions),
      max_bytes,
      max_nodes,
      max_depth,
      max_frames,
      max_work,
      work: instructions.length(),
      phase: Schema(writer, emission),
    })
  } catch {
    _ => Err(Limit)
  }
}

///|
pub fn retire_openai_chat_projection(cursor : OpenAIChatProjection) -> Unit {
  match cursor.phase {
    Schema(writer, emission) => {
      @contract.cancel_checked_emission(emission)
      @encode.cancel_writer(writer)
    }
    InputKey(_, writer, _, key) => {
      @encode.cancel_ordered_key(key)
      @encode.cancel_writer(writer)
    }
    InputValue(_, writer, _, value) => {
      @admitted.cancel_wire_emit(value)
      @encode.cancel_writer(writer)
    }
    InputRole(_, writer, _) => @encode.cancel_writer(writer)
    _ => ()
  }
  cursor.phase = Retired
  cursor.request = None
  cursor.instructions = None
}

///|
fn openai_projection_fail(
  cursor : OpenAIChatProjection,
  issue : OpenAIChatProjectionIssue,
) -> Result[
  (String, String, String, String, String, String, String)?,
  OpenAIChatProjectionIssue,
] {
  retire_openai_chat_projection(cursor)
  cursor.phase = Failed(issue)
  Err(issue)
}

///|
pub fn openai_chat_projection_work(cursor : OpenAIChatProjection) -> Int {
  cursor.work
}

///|
/// One existing emitter transition or one fixed structural transition. This
/// child work is not a Ledger planning-token conversion or execution grant.
pub fn advance_openai_chat_projection(
  cursor : OpenAIChatProjection,
) -> Result[
  (String, String, String, String, String, String, String)?,
  OpenAIChatProjectionIssue,
] {
  match cursor.phase {
    Ready(value) => return Ok(Some(value))
    Failed(issue) => return Err(issue)
    Retired => return Err(ForeignRequest)
    _ => ()
  }
  if cursor.work >= cursor.max_work {
    return openai_projection_fail(cursor, Limit)
  }
  cursor.work += 1
  guard cursor.request is Some(request) else {
    return openai_projection_fail(cursor, ForeignRequest)
  }
  try {
    match cursor.phase {
      Schema(writer, emission) =>
        match @contract.advance_json_schema_emission(emission) {
          Ok(true) => cursor.phase = InputStart(@encode.finish(writer))
          Ok(false) => ()
          Err(@contract.Unsupported) =>
            return openai_projection_fail(cursor, Unsupported)
          Err(_) => return openai_projection_fail(cursor, Limit)
        }
      InputStart(schema) => {
        let writer = @encode.writer(
          cursor.max_bytes,
          cursor.max_nodes,
          cursor.max_depth,
        )
        @encode.begin_ordered_object(writer)
        cursor.phase = InputRole(schema, writer, 0)
      }
      InputRole(schema, writer, index) => {
        if index == request.inputs.length() {
          @encode.end_object(writer)
          guard cursor.instructions is Some(instructions) else {
            return openai_projection_fail(cursor, ForeignRequest)
          }
          let task = request.task
          let value = (
            instructions,
            @encode.finish(writer),
            schema,
            @environment.model_task_identity(task).2,
            @environment.model_task_prompt_cid(task),
            @environment.model_task_schema_cids(task).1,
            @environment.model_task_model_selector(task),
          )
          cursor.phase = Ready(value)
          return Ok(Some(value))
        }
        cursor.phase = InputKey(
          schema,
          writer,
          index,
          @encode.start_ordered_key(writer, request.inputs[index].0),
        )
      }
      InputKey(schema, writer, index, key) =>
        if @encode.advance_ordered_key(key) {
          cursor.phase = InputValue(
            schema,
            writer,
            index,
            @admitted.start_wire_emit(request.inputs[index].1.value, writer),
          )
        }
      InputValue(schema, writer, index, value) => {
        if @admitted.wire_emit_pending_frames(value) >= cursor.max_frames {
          return openai_projection_fail(cursor, Limit)
        }
        if @admitted.advance_wire_emit(value) {
          cursor.phase = InputRole(schema, writer, index + 1)
        }
      }
      _ => return openai_projection_fail(cursor, ForeignRequest)
    }
    Ok(None)
  } catch {
    _ => openai_projection_fail(cursor, Limit)
  }
}

///|
/// Finish the pinned SDK-v4 profile on the SAME completed projection child.
/// The caller must fund expected-wire/SDK/compare overlap before starting this
/// child. Completion (including refusal) retires it before any SDK Promise.
/// Seven original materials remain byte-identical; the eighth is expected DATA.
pub fn finish_openai_chat_sdk_v4_projection(
  cursor : OpenAIChatProjection,
  model_id : String,
  max_request_bytes : Int,
) -> Result[
  (String, String, String, String, String, String, String, String),
  OpenAIChatProjectionIssue,
] {
  let value = match cursor.phase {
    Ready(value) => value
    Failed(issue) => return Err(issue)
    _ => return Err(ForeignRequest)
  }
  guard cursor.request is Some(request) else {
    retire_openai_chat_projection(cursor)
    return Err(ForeignRequest)
  }
  // A JSON.stringify body within max_request_bytes has at most that many
  // UTF-16 units. Canonical escaping takes at most six bytes per unit. The
  // 18 envelope nodes (including optional seed) and three outer schema levels
  // are additional to the unchanged projection limits, never taken from them.
  if model_id.is_empty() ||
    max_request_bytes < 1 ||
    max_request_bytes > 357913941 ||
    cursor.max_nodes > 2147483629 ||
    cursor.max_depth > 2147483644 {
    retire_openai_chat_projection(cursor)
    return Err(Unsupported)
  }
  let result = emit_chat_request_profile(
    OpenAISdkV4,
    request,
    value,
    model_id,
    max_request_bytes * 6,
    cursor.max_nodes + 18,
    cursor.max_depth + 3,
    cursor.max_frames,
    cursor.max_work - cursor.work,
  )
  // A terminal codec cannot be used to acquire another work budget, nor keep
  // borrowing Request/schema construction storage while the SDK starts.
  retire_openai_chat_projection(cursor)
  match result {
    Ok(wire) =>
      Ok((value.0, value.1, value.2, value.3, value.4, value.5, value.6, wire))
    Err(issue) => Err(issue)
  }
}
