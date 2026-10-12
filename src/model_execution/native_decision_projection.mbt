///|
pub(all) enum NativeDecisionProjectionIssue {
  ForeignRequest
  Unsupported
  Limit
} derive(Eq, Debug)

///|
priv enum NativeStateFrame {
  Read(@admitted.Value)
  ArrayNext(@admitted.FrozenArray[@admitted.Value], Int)
  ObjectNext(@admitted.FrozenArray[(String, @admitted.Value)], Int)
}

///|
priv enum NativeQuestionFrame {
  Question(Int)
  Criteria(@decode.Cursor, Int, Bool)
  KeyStart(String)
  Key(@encode.OrderedKeyEmitCursor)
  TextStart(String)
  Text(@encode.StringEmitCursor)
  BeginObject
  EndObject
  BeginArray
  EndArray
}

///|
priv enum NativeDecisionProjectionPhase {
  FindState(Int, Int)
  CheckState(@admitted.Value)
  StateWire(@encode.Writer, @admitted.WireEmitCursor)
  Questions(String, @encode.Writer)
  Ready(NativeDecisionRequest)
  Failed(NativeDecisionProjectionIssue)
  Retired
}

///|
// Read-only SDK projection of the original admitted Model request, not an
// execution, capacity or authority Owner. Questions stay in the original
// dependency; only the provider's bounded wire representation is emitted.
struct NativeDecisionProjection {
  mut provider : AdmittedModelProvider?
  mut request : ModelRequest?
  mut decision : @environment.DecisionContract?
  mut questions : @decode.Cursor?
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_frames : Int
  max_work : Int
  mut work : Int
  mut state_nodes : Int
  state_frames : Array[NativeStateFrame]
  question_frames : Array[NativeQuestionFrame]
  mut phase : NativeDecisionProjectionPhase
}

///|
// Escaped immutable wires and original key correspondence have their own
// borrow lifetime. Retiring the emitting child does not retire this view.
struct NativeDecisionRequest {
  mut provider : AdmittedModelProvider?
  mut request : ModelRequest?
  mut decision : @environment.DecisionContract?
  mut questions : @decode.Cursor?
  mut state_wire : String?
  mut questions_wire : String?
}

///|
fn native_decision_field(
  value : @decode.Cursor,
  name : String,
) -> @decode.Cursor? {
  match @decode.open_object(value) {
    Ok(object) => @decode.lookup(object, name)
    Err(_) => None
  }
}

///|
fn native_decision_text(value : @decode.Cursor, name : String) -> String? {
  match native_decision_field(value, name) {
    Some(field) =>
      match @decode.text(field) {
        Ok(text) => Some(text)
        Err(_) => None
      }
    None => None
  }
}

///|
// SDK keys are data aliases of original ordered positions, never row/Slot IDs
// or new authority. Fixed-width nonnegative Int keys preserve lexical order.
fn native_decision_wire_key(prefix : String, index : Int) -> String {
  let digits = index.to_string()
  prefix + "0".repeat(10 - digits.length()) + digits
}

///|
pub fn start_native_decision_projection(
  provider : AdmittedModelProvider,
  request : ModelRequest,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_frames : Int,
  max_work : Int,
) -> Result[NativeDecisionProjection, NativeDecisionProjectionIssue] {
  let task = @environment.model_execution_task(provider.execution)
  let prompt = @environment.single_attempt_model_prompt(provider.dependencies)
  if !physical_equal(task, request.task) ||
    !@environment.single_attempt_model_dependencies_match(
      provider.dependencies,
      provider.execution,
    ) {
    return Err(ForeignRequest)
  }
  guard @environment.single_attempt_model_decision(provider.dependencies)
    is Some(decision) &&
    @environment.decision_contract_matches(decision, task, prompt) else {
    return Err(Unsupported)
  }
  guard @environment.model_dependency_payload(prompt) is Some(payload) &&
    native_decision_field(payload, "questions") is Some(questions) else {
    return Err(Unsupported)
  }
  if max_bytes < 1 ||
    max_nodes < 1 ||
    max_depth < 1 ||
    max_frames < 1 ||
    max_work < 0 {
    return Err(Limit)
  }
  Ok({
    provider: Some(provider),
    request: Some(request),
    decision: Some(decision),
    questions: Some(questions),
    max_bytes,
    max_nodes,
    max_depth,
    max_frames,
    max_work,
    work: 0,
    state_nodes: 0,
    state_frames: [],
    question_frames: [],
    phase: FindState(0, 0),
  })
}

///|
pub fn retire_native_decision_projection(
  cursor : NativeDecisionProjection,
) -> Unit {
  match cursor.phase {
    StateWire(writer, emission) => {
      @admitted.cancel_wire_emit(emission)
      @encode.cancel_writer(writer)
    }
    Questions(_, writer) => {
      for frame in cursor.question_frames {
        match frame {
          Key(key) => @encode.cancel_ordered_key(key)
          Text(text) => @encode.cancel_string_value(text)
          _ => ()
        }
      }
      @encode.cancel_writer(writer)
    }
    _ => ()
  }
  cursor.state_frames.clear()
  cursor.question_frames.clear()
  cursor.provider = None
  cursor.request = None
  cursor.decision = None
  cursor.questions = None
  cursor.phase = Retired
}

///|
pub fn retire_native_decision_request(value : NativeDecisionRequest) -> Unit {
  value.provider = None
  value.request = None
  value.decision = None
  value.questions = None
  value.state_wire = None
  value.questions_wire = None
}

///|
pub fn native_decision_request_wires(
  value : NativeDecisionRequest,
) -> (String, String)? {
  match (value.state_wire, value.questions_wire) {
    (Some(state), Some(questions)) => Some((state, questions))
    _ => None
  }
}

///|
pub fn native_decision_request_matches(
  value : NativeDecisionRequest,
  provider : AdmittedModelProvider,
  request : ModelRequest,
) -> Bool {
  match (value.provider, value.request, value.decision) {
    (Some(original_provider), Some(original_request), Some(original_decision)) =>
      physical_equal(original_provider, provider) &&
      physical_equal(original_request, request) &&
      @environment.single_attempt_model_decision(provider.dependencies)
      is Some(decision) &&
      physical_equal(original_decision, decision)
    _ => false
  }
}

///|
pub fn native_decision_request_binding(
  value : NativeDecisionRequest,
) -> (String, String, String, String)? {
  match value.request {
    Some(request) => {
      let task = request.task
      Some(
        (
          @environment.model_task_identity(task).2,
          @environment.model_task_prompt_cid(task),
          @environment.model_task_schema_cids(task).1,
          @environment.model_task_model_selector(task),
        ),
      )
    }
    None => None
  }
}

///|
pub fn native_decision_question_id(
  value : NativeDecisionRequest,
  index : Int,
) -> String? {
  match value.questions {
    Some(questions) =>
      match @decode.element_at(questions, index) {
        Some(q) => native_decision_text(q, "id")
        None => None
      }
    None => None
  }
}

///|
pub fn native_decision_option_id(
  value : NativeDecisionRequest,
  question : Int,
  option : Int,
) -> String? {
  guard value.questions is Some(questions) &&
    @decode.element_at(questions, question) is Some(q) &&
    native_decision_field(q, "options") is Some(options) &&
    @decode.element_at(options, option) is Some(item) else {
    return None
  }
  native_decision_text(item, "id")
}

///|
pub fn native_decision_projection_work(
  cursor : NativeDecisionProjection,
) -> Int {
  cursor.work
}

///|
fn native_decision_projection_fail(
  cursor : NativeDecisionProjection,
  issue : NativeDecisionProjectionIssue,
) -> Result[NativeDecisionRequest?, NativeDecisionProjectionIssue] {
  retire_native_decision_projection(cursor)
  cursor.phase = Failed(issue)
  Err(issue)
}

///|
pub fn advance_native_decision_projection(
  cursor : NativeDecisionProjection,
) -> Result[NativeDecisionRequest?, NativeDecisionProjectionIssue] {
  match cursor.phase {
    Ready(value) => return Ok(Some(value))
    Failed(issue) => return Err(issue)
    Retired => return Err(ForeignRequest)
    _ => ()
  }
  if cursor.work >= cursor.max_work {
    return native_decision_projection_fail(cursor, Limit)
  }
  cursor.work += 1
  guard cursor.request is Some(request) &&
    cursor.decision is Some(decision) &&
    cursor.questions is Some(questions) else {
    return native_decision_projection_fail(cursor, ForeignRequest)
  }
  try {
    match cursor.phase {
      FindState(index, position) => {
        if index >= request.inputs.length() {
          return native_decision_projection_fail(cursor, Unsupported)
        }
        let name = request.inputs[index].0
        let wanted = @environment.decision_state_input(decision)
        if name.length() != wanted.length() {
          cursor.phase = FindState(index + 1, 0)
        } else {
          let mut next = position
          let mut equal = true
          for _ in 0..<64 {
            if next == name.length() {
              break
            }
            if name[next] != wanted[next] {
              equal = false
              break
            }
            next += 1
          }
          if !equal {
            cursor.phase = FindState(index + 1, 0)
          } else if next < name.length() {
            cursor.phase = FindState(index, next)
          } else {
            // JSON's typed carrier is not part of the provider's data value.
            // Unwrap that admitted carrier, never parse/rebuild it in JS.
            let state = match request.inputs[index].1.value {
              @admitted.JsonData(inner) => inner
              value => value
            }
            cursor.state_frames.push(Read(state))
            cursor.phase = CheckState(state)
          }
        }
      }
      CheckState(state) => {
        guard cursor.state_frames.pop() is Some(frame) else {
          let writer = @encode.writer(
            cursor.max_bytes,
            cursor.max_nodes,
            cursor.max_depth,
          )
          cursor.phase = StateWire(
            writer,
            @admitted.start_wire_emit(state, writer),
          )
          return Ok(None)
        }
        match frame {
          Read(value) => {
            if cursor.state_nodes >= cursor.max_nodes {
              return native_decision_projection_fail(cursor, Limit)
            }
            cursor.state_nodes += 1
            match value {
              @admitted.Null
              | @admitted.Boolean(_)
              | @admitted.Number(_)
              | @admitted.Text(_) => ()
              @admitted.JsonData(_) =>
                return native_decision_projection_fail(cursor, Unsupported)
              @admitted.Array(items) =>
                cursor.state_frames.push(ArrayNext(items, 0))
              @admitted.Object(items) =>
                cursor.state_frames.push(ObjectNext(items, 0))
              _ => return native_decision_projection_fail(cursor, Unsupported)
            }
          }
          ArrayNext(items, index) =>
            if @admitted.element_count(items) > index {
              if cursor.state_frames.length() > cursor.max_frames - 2 {
                return native_decision_projection_fail(cursor, Limit)
              }
              cursor.state_frames.push(ArrayNext(items, index + 1))
              cursor.state_frames.push(
                Read(@admitted.element_at(items, index).unwrap()),
              )
            }
          ObjectNext(items, index) =>
            if @admitted.element_count(items) > index {
              if cursor.state_frames.length() > cursor.max_frames - 2 {
                return native_decision_projection_fail(cursor, Limit)
              }
              cursor.state_frames.push(ObjectNext(items, index + 1))
              cursor.state_frames.push(
                Read(@admitted.element_at(items, index).unwrap().1),
              )
            }
        }
        if cursor.state_frames.length() > cursor.max_frames {
          return native_decision_projection_fail(cursor, Limit)
        }
      }
      StateWire(writer, emission) => {
        if @admitted.wire_emit_pending_frames(emission) >= cursor.max_frames {
          return native_decision_projection_fail(cursor, Limit)
        }
        if @admitted.advance_wire_emit(emission) {
          let state_wire = @encode.finish(writer)
          let questions_writer = @encode.writer(
            cursor.max_bytes,
            cursor.max_nodes,
            cursor.max_depth,
          )
          @encode.begin_ordered_object(questions_writer)
          cursor.question_frames.push(Question(0))
          cursor.phase = Questions(state_wire, questions_writer)
        }
      }
      Questions(state_wire, writer) => {
        guard cursor.question_frames.pop() is Some(frame) else {
          @encode.end_object(writer)
          let value : NativeDecisionRequest = {
            provider: cursor.provider,
            request: cursor.request,
            decision: cursor.decision,
            questions: cursor.questions,
            state_wire: Some(state_wire),
            questions_wire: Some(@encode.finish(writer)),
          }
          cursor.phase = Ready(value)
          return Ok(Some(value))
        }
        match frame {
          Question(index) =>
            if index < @decode.array_length(questions).unwrap() {
              let q = @decode.element_at(questions, index).unwrap()
              let kind = native_decision_text(q, "type").unwrap()
              let instructions = native_decision_text(q, "instructions").unwrap()
              let needed = if kind == "boolean" { 8 } else { 12 }
              if cursor.question_frames.length() > cursor.max_frames - needed {
                return native_decision_projection_fail(cursor, Limit)
              }
              cursor.question_frames.push(Question(index + 1))
              cursor.question_frames.push(EndObject)
              cursor.question_frames.push(TextStart(kind))
              cursor.question_frames.push(KeyStart("type"))
              cursor.question_frames.push(TextStart(instructions))
              cursor.question_frames.push(KeyStart("instructions"))
              if kind != "boolean" {
                let items = native_decision_field(
                  q,
                  if kind == "choice" {
                    "options"
                  } else {
                    "levels"
                  },
                ).unwrap()
                let count = @decode.array_length(items).unwrap()
                // Selected TypeSafe profile limits; never a common language ban.
                if (kind == "choice" && count > 255) ||
                  (kind == "score" && count > 10) {
                  return native_decision_projection_fail(cursor, Unsupported)
                }
                cursor.question_frames.push(
                  if kind == "choice" {
                    EndObject
                  } else {
                    EndArray
                  },
                )
                cursor.question_frames.push(
                  Criteria(items, 0, kind == "choice"),
                )
                cursor.question_frames.push(
                  if kind == "choice" {
                    BeginObject
                  } else {
                    BeginArray
                  },
                )
                cursor.question_frames.push(KeyStart("criteria"))
              }
              cursor.question_frames.push(BeginObject)
              cursor.question_frames.push(
                KeyStart(native_decision_wire_key("q", index)),
              )
            }
          Criteria(items, index, choice) =>
            if index < @decode.array_length(items).unwrap() {
              let needed = if choice { 3 } else { 2 }
              if cursor.question_frames.length() > cursor.max_frames - needed {
                return native_decision_projection_fail(cursor, Limit)
              }
              let item = @decode.element_at(items, index).unwrap()
              let text = if choice {
                native_decision_text(item, "description").unwrap()
              } else {
                @decode.text(item).unwrap()
              }
              cursor.question_frames.push(Criteria(items, index + 1, choice))
              cursor.question_frames.push(TextStart(text))
              if choice {
                cursor.question_frames.push(
                  KeyStart(native_decision_wire_key("o", index)),
                )
              }
            }
          KeyStart(name) =>
            cursor.question_frames.push(
              Key(@encode.start_ordered_key(writer, name)),
            )
          Key(key) =>
            if !@encode.advance_ordered_key(key) {
              cursor.question_frames.push(Key(key))
            }
          TextStart(text) =>
            cursor.question_frames.push(
              Text(@encode.start_string_value(writer, text)),
            )
          Text(text) =>
            if !@encode.advance_string_value(text) {
              cursor.question_frames.push(Text(text))
            }
          BeginObject => @encode.begin_ordered_object(writer)
          EndObject => @encode.end_object(writer)
          BeginArray => @encode.begin_array(writer)
          EndArray => @encode.end_array(writer)
        }
        if cursor.question_frames.length() > cursor.max_frames {
          return native_decision_projection_fail(cursor, Limit)
        }
      }
      _ => return native_decision_projection_fail(cursor, ForeignRequest)
    }
    Ok(None)
  } catch {
    _ => native_decision_projection_fail(cursor, Limit)
  }
}
