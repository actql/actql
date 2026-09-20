///|
/// Owner-bound typed parameters for one admitted as-of join occurrence.
struct PreparedAsOfJoin {
  owner : BoundPrepared
  step : Int
  checked : @asof.CheckedAsOf
  keys : Array[(@schema.FieldName, @schema.FieldName)]
  projection : Array[InnerJoinField]
  identity : Array[@schema.FieldName]
  tie_break : Array[@schema.FieldName]
  tolerance : Int64
  name_bytes : Int
}

///|
pub(all) enum AsOfJoinIssue {
  InvalidAsOfJoinLimits
  InvalidAsOfJoinShape
  AsOfJoinPreparationLimit
  MissingAsOfJoinParameter(String)
  InvalidAsOfJoinParameter(String)
} derive(Eq, Debug)

///|
fn prepare_asof_join(
  owner : BoundPrepared,
  step : Int,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[PreparedAsOfJoin, AsOfJoinIssue] {
  if max_entries < 0 || max_name_bytes < 0 {
    return Err(InvalidAsOfJoinLimits)
  }
  guard owner.prepared.nodes.get(step) is Some(node) &&
    node.payload is AsOfJoinRows(checked) &&
    node.inputs.length() == 2 else {
    return Err(InvalidAsOfJoinShape)
  }
  let keys = @asof.asof_keys(checked).map(pair => (pair.left, pair.right))
  let identity = @asof.asof_identity(checked)
  let tie_break = @asof.asof_completed_tie_break(checked)
  let output_schema = @asof.asof_output_schema(checked)
  let width = @schema.field_count(output_schema)
  let key_entries = keys.length() * 2
  let projection_entries = width * 2
  if keys.length() > max_entries / 2 ||
    width > max_entries / 2 ||
    key_entries > max_entries ||
    identity.length() > max_entries - key_entries ||
    tie_break.length() > max_entries - key_entries - identity.length() ||
    projection_entries >
    max_entries - key_entries - identity.length() - tie_break.length() ||
    2 >
    max_entries -
    key_entries -
    identity.length() -
    tie_break.length() -
    projection_entries {
    return Err(AsOfJoinPreparationLimit)
  }
  let mut remaining = max_name_bytes
  let spend = fn(field : @schema.FieldName) -> Bool {
    let name = @schema.reference_name(field)
    if name.length() > remaining {
      return false
    }
    let bytes = @utf8.encode(name).length()
    if bytes > remaining {
      return false
    }
    remaining -= bytes
    true
  }
  for (left, right) in keys {
    if !spend(left) || !spend(right) {
      return Err(AsOfJoinPreparationLimit)
    }
  }
  for field in identity {
    if !spend(field) {
      return Err(AsOfJoinPreparationLimit)
    }
  }
  for field in tie_break {
    if !spend(field) {
      return Err(AsOfJoinPreparationLimit)
    }
  }
  if !spend(@asof.asof_time(checked, @schema.Left)) ||
    !spend(@asof.asof_time(checked, @schema.Right)) {
    return Err(AsOfJoinPreparationLimit)
  }
  let projection : Array[InnerJoinField] = []
  for index in 0..<width {
    guard @asof.asof_projection_at(checked, index) is Some(field) else {
      return Err(InvalidAsOfJoinShape)
    }
    if !spend(field.output) || !spend(field.input) {
      return Err(AsOfJoinPreparationLimit)
    }
    projection.push({ output: field.output, input: field.input, })
  }
  let (tolerance, tolerance_names) = match
    resolve_window_milliseconds(owner, @asof.asof_tolerance(checked), remaining) {
    Ok(value) => value
    Err(WindowBudgetExceeded) => return Err(AsOfJoinPreparationLimit)
    Err(MissingWindowParameter(name)) =>
      return Err(MissingAsOfJoinParameter(name))
    Err(InvalidWindowParameter(name)) =>
      return Err(InvalidAsOfJoinParameter(name))
    Err(_) => return Err(InvalidAsOfJoinShape)
  }
  remaining -= tolerance_names
  Ok({
    owner,
    step,
    checked,
    keys,
    projection,
    identity,
    tie_break,
    tolerance,
    name_bytes: max_name_bytes - remaining,
  })
}

///|
pub fn asof_join_owner(value : PreparedAsOfJoin) -> BoundPrepared {
  value.owner
}

///|
pub fn asof_join_step(value : PreparedAsOfJoin) -> Int {
  value.step
}

///|
pub fn asof_join_input(value : PreparedAsOfJoin, left : Bool) -> String {
  value.owner.prepared.nodes[value.step].inputs[if left { 0 } else { 1 }]
}

///|
pub fn asof_join_kind(value : PreparedAsOfJoin) -> @join.Kind {
  @asof.asof_kind(value.checked)
}

///|
pub fn asof_join_direction(value : PreparedAsOfJoin) -> @asof.AsOfDirection {
  @asof.asof_direction(value.checked)
}

///|
pub fn asof_join_time(
  value : PreparedAsOfJoin,
  left : Bool,
) -> @schema.FieldName {
  @asof.asof_time(
    value.checked,
    if left {
      @schema.Left
    } else {
      @schema.Right
    },
  )
}

///|
pub fn asof_join_uses_timestamp(value : PreparedAsOfJoin, left : Bool) -> Bool {
  @asof.asof_uses_timestamp(
    value.checked,
    if left {
      @schema.Left
    } else {
      @schema.Right
    },
  )
}

///|
pub fn asof_join_tolerance(value : PreparedAsOfJoin) -> Int64 {
  value.tolerance
}

///|
pub fn asof_join_key_count(value : PreparedAsOfJoin) -> Int {
  value.keys.length()
}

///|
pub fn asof_join_key_at(
  value : PreparedAsOfJoin,
  index : Int,
) -> (@schema.FieldName, @schema.FieldName)? {
  value.keys.get(index)
}

///|
pub fn asof_join_identity_count(value : PreparedAsOfJoin) -> Int {
  value.identity.length()
}

///|
pub fn asof_join_identity_at(
  value : PreparedAsOfJoin,
  index : Int,
) -> @schema.FieldName? {
  value.identity.get(index)
}

///|
pub fn asof_join_tie_break_count(value : PreparedAsOfJoin) -> Int {
  value.tie_break.length()
}

///|
pub fn asof_join_tie_break_at(
  value : PreparedAsOfJoin,
  index : Int,
) -> @schema.FieldName? {
  value.tie_break.get(index)
}

///|
pub fn asof_join_field_count(value : PreparedAsOfJoin) -> Int {
  value.projection.length()
}

///|
pub fn asof_join_field_at(
  value : PreparedAsOfJoin,
  index : Int,
) -> InnerJoinField? {
  value.projection.get(index)
}

///|
pub fn asof_join_input_schema(
  value : PreparedAsOfJoin,
  left : Bool,
) -> @schema.Schema? {
  @carrier.complete_schema(
    @asof.asof_input_records(
      value.checked,
      if left {
        @schema.Left
      } else {
        @schema.Right
      },
    ),
  )
}

///|
pub fn emit_asof_join(
  value : PreparedAsOfJoin,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  let node = value.owner.prepared.nodes[value.step]
  @encode.begin_object(out)
  @encode.key(out, "id")
  @encode.string_value(out, node.id)
  @encode.key(out, "in")
  @encode.begin_array(out)
  for input in node.inputs {
    @encode.string_value(out, input)
  }
  @encode.end_array(out)
  @encode.key(out, "op")
  @encode.string_value(out, "TEA.join.asof")
  @encode.key(out, "params")
  @encode.begin_object(out)
  @encode.key(out, "columns")
  @encode.begin_array(out)
  for field in value.projection {
    @encode.begin_object(out)
    @encode.key(out, "from")
    @encode.string_value(out, @schema.reference_name(field.input))
    @encode.key(out, "to")
    @encode.string_value(out, @schema.reference_name(field.output))
    @encode.end_object(out)
  }
  @encode.end_array(out)
  @encode.key(out, "direction")
  @encode.string_value(
    out,
    match @asof.asof_direction(value.checked) {
      @asof.AsOfDirection::Backward => "backward"
      @asof.AsOfDirection::Forward => "forward"
      @asof.AsOfDirection::Nearest => "nearest"
    },
  )
  @encode.key(out, "how")
  @encode.string_value(
    out,
    if @asof.asof_kind(value.checked) == @join.Left {
      "left"
    } else {
      "inner"
    },
  )
  @encode.key(out, "identity")
  @encode.begin_array(out)
  for field in value.identity {
    @encode.string_value(out, @schema.reference_name(field))
  }
  @encode.end_array(out)
  @encode.key(out, "key_pairs")
  @encode.begin_array(out)
  for (left, right) in value.keys {
    @encode.begin_object(out)
    @encode.key(out, "left")
    @encode.string_value(out, @schema.reference_name(left))
    @encode.key(out, "right")
    @encode.string_value(out, @schema.reference_name(right))
    @encode.end_object(out)
  }
  @encode.end_array(out)
  @encode.key(out, "left_time")
  @encode.string_value(
    out,
    @schema.reference_name(@asof.asof_time(value.checked, @schema.Left)),
  )
  @encode.key(out, "right_tie_break")
  @encode.begin_array(out)
  for field in value.tie_break {
    @encode.string_value(out, @schema.reference_name(field))
  }
  @encode.end_array(out)
  @encode.key(out, "right_time")
  @encode.string_value(
    out,
    @schema.reference_name(@asof.asof_time(value.checked, @schema.Right)),
  )
  @encode.key(out, "time_domain")
  @encode.string_value(
    out,
    if @asof.asof_uses_timestamp(value.checked, @schema.Left) {
      "timestamp"
    } else {
      "utc_milliseconds"
    },
  )
  @encode.key(out, "tolerance_ms")
  @encode.number_value(out, value.tolerance.to_double())
  @encode.end_object(out)
  @encode.end_object(out)
}
