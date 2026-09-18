///|
/// Resolved, owner-bound view of one checked row-window operation. This is
/// execution preparation, not a second parser or an admission token.
struct PreparedWindow {
  owner : BoundPrepared
  step_index : Int
  input_id : String
  kind : @window.Kind
  time : @schema.FieldName
  start : @schema.FieldName
  end : @schema.FieldName
  size : Int64
  authored_step : Int64?
  offset : Int64
  epoch_milliseconds : Bool
}

///|
pub(all) enum WindowIssue {
  InvalidWindowLimits
  MissingWindowNode
  InvalidWindowWiring
  WindowBudgetExceeded
  MissingWindowParameter(String)
  InvalidWindowParameter(String)
} derive(Eq, Debug)

///|
fn resolve_window_milliseconds(
  owner : BoundPrepared,
  value : @window.Milliseconds,
  max_name_bytes : Int,
) -> Result[(Int64, Int), WindowIssue] {
  match value {
    @window.Literal(value) => Ok((value, 0))
    @window.Parameter(name, duration~, domain~) => {
      if name.length() > max_name_bytes {
        return Err(WindowBudgetExceeded)
      }
      let name_bytes = @utf8.encode(name).length()
      if name_bytes > max_name_bytes {
        return Err(WindowBudgetExceeded)
      }
      guard parameter_value(owner, name) is Some(bound) else {
        return Err(MissingWindowParameter(name))
      }
      let value = if duration {
        match bound.value {
          @value.Text(text) => @scalar.read_duration_ms(text)
          _ => None
        }
      } else {
        match bound.value {
          @value.Number(number) => @scalar.read_safe_integer(number)
          _ => None
        }
      }
      match value {
        Some(value) if domain == @window.SignedMilliseconds || value > 0L =>
          Ok((value, name_bytes))
        _ => Err(InvalidWindowParameter(name))
      }
    }
  }
}

///|
fn prepare_window(
  owner : BoundPrepared,
  step_index : Int,
  max_bindings~ : Int,
  max_name_bytes~ : Int,
  max_work~ : Int,
) -> Result[(PreparedWindow, Int, Int, Int), WindowIssue] {
  if max_bindings < 0 || max_name_bytes < 0 || max_work < 0 {
    return Err(InvalidWindowLimits)
  }
  guard owner.prepared.nodes.get(step_index) is Some(node) &&
    node.payload is RowWindow(checked) else {
    return Err(MissingWindowNode)
  }
  if node.inputs.length() != 1 {
    return Err(InvalidWindowWiring)
  }
  let options = @window.options(checked)
  let (start, end) = @window.boundary_fields(@window.window_roles(checked))
  let names = [@window.time_field(checked), start, end]
  let scalar_count = 2 + (if @window.step(options) is Some(_) { 1 } else { 0 })
  let work = names.length() + scalar_count
  if names.length() > max_bindings || work > max_work {
    return Err(WindowBudgetExceeded)
  }
  let mut name_bytes = 0
  for field in names {
    let name = @schema.reference_name(field)
    if name.length() > max_name_bytes - name_bytes {
      return Err(WindowBudgetExceeded)
    }
    let bytes = @utf8.encode(name).length()
    if bytes > max_name_bytes - name_bytes {
      return Err(WindowBudgetExceeded)
    }
    name_bytes += bytes
  }
  let (size, size_name_bytes) = match
    resolve_window_milliseconds(
      owner,
      @window.size(options),
      max_name_bytes - name_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  name_bytes += size_name_bytes
  let authored_step = match @window.step(options) {
    None => None
    Some(value) =>
      match
        resolve_window_milliseconds(owner, value, max_name_bytes - name_bytes) {
        Ok((value, used)) => {
          name_bytes += used
          Some(value)
        }
        Err(issue) => return Err(issue)
      }
  }
  let (offset, offset_name_bytes) = match
    resolve_window_milliseconds(
      owner,
      @window.offset(options),
      max_name_bytes - name_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  name_bytes += offset_name_bytes
  let kind = @window.kind(options)
  if size <= 0L ||
    (kind == @window.Sliding && authored_step is None) ||
    (authored_step is Some(value) && value <= 0L) {
    return Err(InvalidWindowWiring)
  }
  Ok(
    (
      {
        owner,
        step_index,
        input_id: node.inputs[0],
        kind,
        time: @window.time_field(checked),
        start,
        end,
        size,
        authored_step,
        offset,
        epoch_milliseconds: @window.requires_epoch_milliseconds(checked),
      },
      name_bytes,
      names.length(),
      work,
    ),
  )
}

///|
pub fn window_owner(value : PreparedWindow) -> BoundPrepared {
  value.owner
}

///|
pub fn window_step_index(value : PreparedWindow) -> Int {
  value.step_index
}

///|
pub fn window_input(value : PreparedWindow) -> String {
  value.input_id
}

///|
pub fn window_kind(value : PreparedWindow) -> @window.Kind {
  value.kind
}

///|
pub fn window_time(value : PreparedWindow) -> @schema.FieldName {
  value.time
}

///|
pub fn window_boundaries(
  value : PreparedWindow,
) -> (@schema.FieldName, @schema.FieldName) {
  (value.start, value.end)
}

///|
pub fn window_size(value : PreparedWindow) -> Int64 {
  value.size
}

///|
pub fn window_authored_step(value : PreparedWindow) -> Int64? {
  value.authored_step
}

///|
pub fn window_effective_step(value : PreparedWindow) -> Int64 {
  match value.kind {
    @window.Fixed => value.size
    @window.Sliding => value.authored_step.unwrap()
  }
}

///|
pub fn window_offset(value : PreparedWindow) -> Int64 {
  value.offset
}

///|
pub fn window_requires_epoch_milliseconds(value : PreparedWindow) -> Bool {
  value.epoch_milliseconds
}

///|
pub fn emit_window_node(
  value : PreparedWindow,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  let node = value.owner.prepared.nodes[value.step_index]
  @encode.begin_object(out)
  @encode.key(out, "id")
  @encode.string_value(out, node.id)
  @encode.key(out, "in")
  @encode.begin_array(out)
  @encode.string_value(out, value.input_id)
  @encode.end_array(out)
  @encode.key(out, "op")
  @encode.string_value(
    out,
    match value.kind {
      @window.Fixed => "REL.window.fixed"
      @window.Sliding => "REL.window.sliding"
    },
  )
  @encode.key(out, "params")
  @encode.begin_object(out)
  @encode.key(out, "offset_ms")
  @encode.number_value(out, value.offset.to_double())
  @encode.key(out, "size_ms")
  @encode.number_value(out, value.size.to_double())
  if value.kind == @window.Sliding {
    @encode.key(out, "step_ms")
    @encode.number_value(out, value.authored_step.unwrap().to_double())
  }
  @encode.key(out, "time")
  @encode.string_value(out, @schema.reference_name(value.time))
  @encode.end_object(out)
  @encode.end_object(out)
}
