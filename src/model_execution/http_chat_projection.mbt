///|
/// Read-only outbound codec for the initial non-reasoning Chat HTTP profile.
/// The installed Host owns model/endpoint selection. This function issues no
/// installation, capacity, Entry, capture, completion or transmission grant.
/// Physical driving must retain the original request and fund this preparation.
pub fn project_http_chat_request(
  provider : AdmittedModelProvider,
  request : ModelRequest,
  model_id : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_frames : Int,
  max_work : Int,
) -> Result[(String, String, String, String, String), OpenAIChatProjectionIssue] {
  if model_id.is_empty() {
    return Err(Unsupported)
  }
  let cursor = match
    start_openai_chat_projection(
      provider, request, max_bytes, max_nodes, max_depth, max_frames, max_work,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let mut projected = None
  while projected is None {
    match advance_openai_chat_projection(cursor) {
      Ok(value) => projected = value
      Err(issue) => return Err(issue)
    }
  }
  let used = openai_chat_projection_work(cursor)
  retire_openai_chat_projection(cursor)
  let value = projected.unwrap()
  guard @environment.model_task_generation_config(request.task)
    is Some(generation) else {
    return Err(Unsupported)
  }
  // This finite physical subset shares the initial SDK route's exact integer
  // range. It does not redefine the Task's wider Int64 domain or claim every
  // compatible endpoint preserves arbitrary integer token/seed semantics.
  if generation.max_output_tokens > 9007199254740991L {
    return Err(Unsupported)
  }
  if generation.seed_requested is Some(seed) &&
    (seed < -9007199254740991L || seed > 9007199254740991L) {
    return Err(Unsupported)
  }
  let mut remaining = max_work - used
  // Account complete string scans before the synchronous bounded convenience
  // writer. This is codec-local work, not a Ledger planning-token conversion.
  // 43 fixed writer calls, plus two only when seed is present. This local
  // structural work definition is independent of physical bytes and of the
  // checked schema emitter's own transition count below.
  let seed_work = if generation.seed_requested is Some(_) { 2 } else { 0 }
  let structural_work = 43 + seed_work
  for
    cost in [
      model_id.length(),
      value.0.length(),
      value.1.length(),
      structural_work,
    ] {
    if cost > remaining {
      return Err(Limit)
    }
    remaining -= cost
  }
  try {
    let writer = @encode.writer(max_bytes, max_nodes, max_depth)
    @encode.begin_object(writer)
    @encode.key(writer, "max_tokens")
    @encode.number_value(writer, generation.max_output_tokens.to_double())
    @encode.key(writer, "messages")
    @encode.begin_array(writer)
    for (role, content) in [("system", value.0), ("user", value.1)] {
      @encode.begin_object(writer)
      @encode.key(writer, "content")
      @encode.string_value(writer, content)
      @encode.key(writer, "role")
      @encode.string_value(writer, role)
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    @encode.key(writer, "model")
    @encode.string_value(writer, model_id)
    @encode.key(writer, "n")
    @encode.number_value(writer, 1)
    @encode.key(writer, "response_format")
    @encode.begin_object(writer)
    @encode.key(writer, "json_schema")
    @encode.begin_object(writer)
    @encode.key(writer, "name")
    @encode.string_value(writer, "actql_output")
    @encode.key(writer, "schema")
    // Use the existing checked contract emitter, not a JS parse/rebuild or a
    // second schema interpretation. The projection's schema wire remains an
    // explicitly simultaneous temporary until this convenience returns.
    let emission = match
      @contract.start_json_schema_emission(
        @environment.model_task_output(request.task),
        writer,
        max_frames,
      ) {
      Ok(value) => value
      Err(@contract.Unsupported) => return Err(Unsupported)
      Err(_) => return Err(Limit)
    }
    let mut complete = false
    while !complete {
      if remaining == 0 {
        @contract.cancel_checked_emission(emission)
        @encode.cancel_writer(writer)
        return Err(Limit)
      }
      remaining -= 1
      match @contract.advance_json_schema_emission(emission) {
        Ok(done) => complete = done
        Err(_) => return Err(Limit)
      }
    }
    @encode.key(writer, "strict")
    @encode.bool_value(writer, true)
    @encode.end_object(writer)
    @encode.key(writer, "type")
    @encode.string_value(writer, "json_schema")
    @encode.end_object(writer)
    if generation.seed_requested is Some(seed) {
      @encode.key(writer, "seed")
      @encode.number_value(writer, seed.to_double())
    }
    @encode.key(writer, "stream")
    @encode.bool_value(writer, false)
    @encode.key(writer, "temperature")
    @encode.number_value(writer, generation.temperature)
    @encode.key(writer, "top_p")
    @encode.number_value(writer, generation.top_p)
    @encode.end_object(writer)
    Ok((@encode.finish(writer), value.3, value.4, value.5, value.6))
  } catch {
    _ => Err(Limit)
  }
}
