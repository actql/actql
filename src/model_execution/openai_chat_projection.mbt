///|
pub(all) enum OpenAIChatProjectionIssue {
  ForeignRequest
  Unsupported
  Limit
} derive(Eq, Debug)

///|
/// Original admitted Task/prompt and mapped values, not a schema callback or
/// execution grant. The caller supplies already-funded finite preparation
/// bounds; these limits alone do not reserve an operation's holding.
pub fn project_openai_chat_request(
  provider : AdmittedModelProvider,
  request : ModelRequest,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_frames : Int,
  max_work : Int,
) -> Result[
  (String, String, String, String, String, String, String),
  OpenAIChatProjectionIssue,
] {
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
  let mut work = instructions.length()
  try {
    let writer = @encode.writer(max_bytes, max_nodes, max_depth)
    let cursor = match
      @contract.start_json_schema_emission(
        @environment.model_task_output(task),
        writer,
        max_frames,
      ) {
      Ok(value) => value
      Err(@contract.Unsupported) => return Err(Unsupported)
      Err(_) => return Err(Limit)
    }
    let mut done = false
    while !done {
      if work >= max_work {
        @contract.cancel_checked_emission(cursor)
        return Err(Limit)
      }
      work += 1
      match @contract.advance_json_schema_emission(cursor) {
        Ok(value) => done = value
        Err(@contract.Unsupported) => return Err(Unsupported)
        Err(_) => return Err(Limit)
      }
    }
    let schema = @encode.finish(writer)
    let input = @encode.writer(max_bytes, max_nodes, max_depth)
    @encode.begin_ordered_object(input)
    for (name, value) in request.inputs {
      let key = @encode.start_ordered_key(input, name)
      let mut key_done = false
      while !key_done {
        if work >= max_work {
          @encode.cancel_ordered_key(key)
          @encode.cancel_writer(input)
          return Err(Limit)
        }
        work += 1
        key_done = @encode.advance_ordered_key(key)
      }
      let emission = @admitted.start_wire_emit(value.value, input)
      let mut value_done = false
      while !value_done {
        if work >= max_work ||
          @admitted.wire_emit_pending_frames(emission) > max_frames {
          @admitted.cancel_wire_emit(emission)
          @encode.cancel_writer(input)
          return Err(Limit)
        }
        work += 1
        value_done = @admitted.advance_wire_emit(emission)
      }
    }
    @encode.end_object(input)
    Ok(
      (
        instructions,
        @encode.finish(input),
        schema,
        @environment.model_task_identity(task).2,
        @environment.model_task_prompt_cid(task),
        @environment.model_task_schema_cids(task).1,
        @environment.model_task_model_selector(task),
      ),
    )
  } catch {
    _ => Err(Limit)
  }
}
