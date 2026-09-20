///|
struct PreparedIntervalJoin {
  owner : BoundPrepared
  step : Int
  checked : @join.CheckedIntervalJoin
  keys : Array[(@schema.FieldName, @schema.FieldName)]
  projection : Array[InnerJoinField]
  left_operand : @join.TemporalOperand
  right_operand : @join.TemporalOperand
  output_limit : Int64?
  name_bytes : Int
}

///|
pub(all) enum IntervalJoinIssue {
  InvalidIntervalJoinLimits
  InvalidIntervalJoinShape
  IntervalJoinPreparationLimit
  InvalidIntervalJoinGuard
} derive(Eq, Debug)

///|
fn interval_operand_field_count(value : @join.TemporalOperand) -> Int {
  match value {
    @join.Point(_) => 1
    @join.Interval(_, _) => 2
  }
}

///|
fn prepare_interval_join(
  owner : BoundPrepared,
  step : Int,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[PreparedIntervalJoin, IntervalJoinIssue] {
  if max_entries < 0 || max_name_bytes < 0 {
    return Err(InvalidIntervalJoinLimits)
  }
  guard owner.prepared.nodes.get(step) is Some(node) &&
    node.payload is IntervalJoinRows(checked) &&
    node.inputs.length() == 2 else {
    return Err(InvalidIntervalJoinShape)
  }
  let key_count = @join.interval_key_count(checked)
  let output_schema = @join.interval_output_schema(checked)
  let width = @schema.field_count(output_schema)
  let left_operand = @join.interval_operand(checked, @schema.Left)
  let right_operand = @join.interval_operand(checked, @schema.Right)
  let temporal_count = interval_operand_field_count(left_operand) +
    interval_operand_field_count(right_operand)
  if key_count > max_entries ||
    width > max_entries - key_count ||
    temporal_count > max_entries - key_count - width {
    return Err(IntervalJoinPreparationLimit)
  }
  let mut remaining = max_name_bytes
  let spend = fn(field : @schema.FieldName) -> Bool {
    let name = @schema.reference_name(field)
    if name.length() > remaining {
      return false
    }
    let size = @utf8.encode(name).length()
    if size > remaining {
      return false
    }
    remaining -= size
    true
  }
  let keys = []
  for index in 0..<key_count {
    let pair = @join.interval_key_at(checked, index).unwrap()
    if !spend(pair.left) || !spend(pair.right) {
      return Err(IntervalJoinPreparationLimit)
    }
    keys.push((pair.left, pair.right))
  }
  for operand in [left_operand, right_operand] {
    match operand {
      @join.Point(field) =>
        if !spend(field) {
          return Err(IntervalJoinPreparationLimit)
        }
      @join.Interval(start, end) =>
        if !spend(start) || !spend(end) {
          return Err(IntervalJoinPreparationLimit)
        }
    }
  }
  let authored = @join.interval_projection(checked)
  let projection : Array[InnerJoinField] = []
  for index in 0..<width {
    let output = @schema.field_at(output_schema, index).unwrap().name
    let input = match authored {
      None => output
      Some(fields) => {
        guard fields.get(index) is Some(field) && field.output == output else {
          return Err(InvalidIntervalJoinShape)
        }
        field.input
      }
    }
    if !spend(output) || !spend(input) {
      return Err(IntervalJoinPreparationLimit)
    }
    projection.push({ output, input, })
  }
  let output_limit = match @join.interval_output_guard(checked) {
    None => None
    Some(@join.Literal(value)) => Some(value)
    Some(@join.Parameter(name)) => {
      if name.length() > remaining || @utf8.encode(name).length() > remaining {
        return Err(IntervalJoinPreparationLimit)
      }
      guard parameter_value(owner, name) is Some(bound) &&
        bound.value is @value.Number(number) &&
        @scalar.read_safe_integer(number) is Some(value) &&
        value > 0L else {
        return Err(InvalidIntervalJoinGuard)
      }
      remaining -= @utf8.encode(name).length()
      Some(value)
    }
  }
  Ok({
    owner,
    step,
    checked,
    keys,
    projection,
    left_operand,
    right_operand,
    output_limit,
    name_bytes: max_name_bytes - remaining,
  })
}

///|
pub fn interval_join_owner(value : PreparedIntervalJoin) -> BoundPrepared {
  value.owner
}

///|
pub fn interval_join_step(value : PreparedIntervalJoin) -> Int {
  value.step
}

///|
pub fn interval_join_input(value : PreparedIntervalJoin, left : Bool) -> String {
  value.owner.prepared.nodes[value.step].inputs[if left { 0 } else { 1 }]
}

///|
pub fn interval_join_kind(value : PreparedIntervalJoin) -> @join.Kind {
  @join.interval_kind(value.checked)
}

///|
pub fn interval_join_mode(value : PreparedIntervalJoin) -> @join.IntervalMode {
  @join.interval_mode(value.checked)
}

///|
pub fn interval_join_uses_timestamps(value : PreparedIntervalJoin) -> Bool {
  @join.interval_uses_timestamps(value.checked)
}

///|
pub fn interval_join_operand(
  value : PreparedIntervalJoin,
  left : Bool,
) -> @join.TemporalOperand {
  if left {
    value.left_operand
  } else {
    value.right_operand
  }
}

///|
pub fn interval_join_key_count(value : PreparedIntervalJoin) -> Int {
  value.keys.length()
}

///|
pub fn interval_join_key_at(
  value : PreparedIntervalJoin,
  index : Int,
) -> (@schema.FieldName, @schema.FieldName)? {
  value.keys.get(index)
}

///|
pub fn interval_join_field_count(value : PreparedIntervalJoin) -> Int {
  value.projection.length()
}

///|
pub fn interval_join_field_at(
  value : PreparedIntervalJoin,
  index : Int,
) -> InnerJoinField? {
  value.projection.get(index)
}

///|
pub fn interval_join_output_limit(value : PreparedIntervalJoin) -> Int64? {
  value.output_limit
}

///|
pub fn interval_join_input_schema(
  value : PreparedIntervalJoin,
  left : Bool,
) -> @schema.Schema {
  @join.interval_input_schema(
    value.checked,
    if left {
      @schema.Left
    } else {
      @schema.Right
    },
  )
}

///|
fn emit_interval_operand(
  out : @encode.Writer,
  value : @join.TemporalOperand,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  match value {
    @join.Point(time) => {
      @encode.key(out, "time")
      @encode.string_value(out, @schema.reference_name(time))
    }
    @join.Interval(start, end) => {
      @encode.key(out, "end")
      @encode.string_value(out, @schema.reference_name(end))
      @encode.key(out, "start")
      @encode.string_value(out, @schema.reference_name(start))
    }
  }
  @encode.end_object(out)
}

///|
pub fn emit_interval_join(
  value : PreparedIntervalJoin,
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
  @encode.string_value(out, "TEA.join.interval")
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
  @encode.key(out, "how")
  @encode.string_value(
    out,
    match @join.interval_kind(value.checked) {
      @join.Inner => "inner"
      @join.Left => "left"
      @join.Semi => "semi"
      @join.Anti => "anti"
      @join.Full => "full"
    },
  )
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
  @encode.key(out, "left")
  emit_interval_operand(out, value.left_operand)
  if value.output_limit is Some(limit) {
    @encode.key(out, "max_output_rows")
    @encode.number_value(out, limit.to_double())
  }
  @encode.key(out, "mode")
  @encode.string_value(
    out,
    match @join.interval_mode(value.checked) {
      @join.PointInInterval => "point_in_interval"
      @join.Overlap => "overlap"
    },
  )
  @encode.key(out, "right")
  emit_interval_operand(out, value.right_operand)
  @encode.key(out, "time_domain")
  @encode.string_value(
    out,
    if @join.interval_uses_timestamps(value.checked) {
      "timestamp"
    } else {
      "utc_milliseconds"
    },
  )
  @encode.end_object(out)
  @encode.end_object(out)
}
