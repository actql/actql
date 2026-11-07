///|
pub(all) enum KeyedInputRequestIssue {
  InvalidLimits
  WorkLimit
  ForeignPipeline
  ForeignParameters
  ForeignInput
  UnsupportedInput
  InvalidRow
  MissingColumn(Int)
  InvalidValue(Int)
  Request(@acquisition.KeyedRowRequestIssue)
} derive(Eq, Debug)

///|
/// Identify the real checked keyed response port. Equal schemas or a caller's
/// request wire cannot authorize another input occurrence or parameter owner.
pub fn keyed_response_input_schema(
  owner : @lower.BoundPrepared,
  join : @acquisition.KeyedJoin,
  request : @acquisition.KeyedRowRequest,
) -> Result[@schema.Schema, KeyedInputRequestIssue] {
  let schema = match keyed_response_port_schema(owner, join) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !physical_equal(
      @acquisition.keyed_row_request_owner(request),
      @acquisition.keyed_join_request(join),
    ) {
    return Err(ForeignParameters)
  }
  Ok(schema)
}

///|
/// Pre-I/O selection of the checked response port. This validates the original
/// pipeline and parameter owner without inventing a row request or receipt.
pub fn keyed_response_port_schema(
  owner : @lower.BoundPrepared,
  join : @acquisition.KeyedJoin,
) -> Result[@schema.Schema, KeyedInputRequestIssue] {
  let index = match keyed_response_input_index(owner, join) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match
    @lower.preparation_input_schema(@lower.bound_preparation(owner), index) {
    Some(schema) => Ok(schema)
    None => Err(ForeignInput)
  }
}

///|
// Source inventory coordinates exclude imported Results. Decode and retained
// runtime inputs instead use the actual checked JOIN right port in its pipeline.
// Keep the inventory coordinate unchanged for Catalog/Source obligation checks.
pub fn keyed_response_input_index(
  owner : @lower.BoundPrepared,
  join : @acquisition.KeyedJoin,
) -> Result[Int, KeyedInputRequestIssue] {
  let pipeline = @lower.pipeline(@lower.bound_preparation(owner))
  guard @pipeline.step_at(pipeline, @acquisition.keyed_join_step(join))
    is Some(step) &&
    step.operation
    is @pipeline.Join(checked=operation, right=@pipeline.Input(index)) &&
    physical_equal(operation, @acquisition.keyed_join_operation(join)) &&
    step.input == Some(@acquisition.keyed_join_left(join)) else {
    return Err(ForeignPipeline)
  }
  let parameters = @acquisition.request_parameter_values(
    @acquisition.parameterized_keyed_request_parameters(
      @acquisition.keyed_join_request(join),
    ),
  )
  match @lower.parameter_bindings(owner) {
    Some(bound) =>
      if !physical_equal(bound, parameters) {
        return Err(ForeignParameters)
      }
    None =>
      if @parameter.bound_value_count(parameters) != 0 {
        return Err(ForeignParameters)
      }
  }
  let input = @acquisition.keyed_request_input(
    @acquisition.parameterized_keyed_request(
      @acquisition.keyed_join_request(join),
    ),
  )
  if @pipeline.lookup(pipeline, @acquisition.declaration(input).input_name) !=
    Some(@pipeline.Input(index)) {
    return Err(ForeignInput)
  }
  Ok(index)
}

///|
/// Bind one captured left occurrence to the actual checked keyed JOIN. Values
/// are borrowed from its immutable admitted input, not decoded from a caller's
/// JSON. This is request preparation only: the existing acquisition owner must
/// still authorize I/O, validate complete-per-key responses and retain custody.
/// The caller reserves the overlapping key/request workspace before entering.
pub fn start_captured_keyed_request(
  owner : @lower.BoundPrepared,
  join : @acquisition.KeyedJoin,
  left : @execution.CapturedRows,
  row : Int,
  limits : @acquisition.RequestLimits,
) -> Result[(@acquisition.KeyedRowRequestCursor, Int), KeyedInputRequestIssue] {
  let valid = match @acquisition.keyed_join_left(join) {
    @pipeline.Input(input) =>
      physical_equal(@execution.captured_owner(left), owner) &&
      @execution.captured_origin(left) == @execution.SuppliedInput(input)
    _ => return Err(UnsupportedInput)
  }
  start_left_keyed_request(
    owner,
    join,
    valid,
    @execution.captured_schema(left),
    @execution.captured_row_count(left),
    row,
    column => {
      @execution.captured_cell(left, row, column).map(@execution.capture)
    },
    limits,
  )
}

///|
/// Read the actual completed left operation through its existing receiving
/// port. A Source capture cannot substitute for WHERE's output. The producer
/// read retains the completion and checks current liveness on every cell read;
/// this preparation neither owns that storage nor authorizes physical I/O.
pub fn start_produced_keyed_request(
  owner : @lower.BoundPrepared,
  join : @acquisition.KeyedJoin,
  left : @execution.ProducerRead,
  row : Int,
  limits : @acquisition.RequestLimits,
) -> Result[(@acquisition.KeyedRowRequestCursor, Int), KeyedInputRequestIssue] {
  let valid = @execution.producer_read_matches_operation_input(
    left,
    owner,
    @acquisition.keyed_join_step(join),
    0,
  )
  if valid && !@execution.producer_read_has_cell_access(left) {
    // Representation conversion belongs to the existing Store/Host owner.
    // Do not treat an unreadable retained stream as an empty Relation.
    return Err(UnsupportedInput)
  }
  start_left_keyed_request(
    owner,
    join,
    valid,
    @execution.producer_read_schema(left),
    @execution.producer_read_row_count(left),
    row,
    column => @execution.producer_read_cell(left, row, column),
    limits,
  )
}

///|
fn start_left_keyed_request(
  owner : @lower.BoundPrepared,
  join : @acquisition.KeyedJoin,
  valid_input : Bool,
  schema : @schema.Schema,
  rows : Int,
  row : Int,
  cell_at : (Int) -> @execution.Value?,
  limits : @acquisition.RequestLimits,
) -> Result[(@acquisition.KeyedRowRequestCursor, Int), KeyedInputRequestIssue] {
  if limits.max_work < 0 ||
    limits.max_pairs < 0 ||
    limits.values.max_nodes < 0 ||
    limits.values.max_depth < 0 ||
    limits.values.max_text_bytes < 0 {
    return Err(InvalidLimits)
  }
  let mut remaining = limits.max_work
  if remaining < 1 {
    return Err(WorkLimit)
  }
  remaining -= 1
  let pipeline = @lower.pipeline(@lower.bound_preparation(owner))
  guard @pipeline.step_at(pipeline, @acquisition.keyed_join_step(join))
    is Some(step) &&
    step.operation is @pipeline.Join(checked=operation, ..) &&
    physical_equal(operation, @acquisition.keyed_join_operation(join)) &&
    step.input == Some(@acquisition.keyed_join_left(join)) else {
    return Err(ForeignPipeline)
  }
  let parameters = @acquisition.request_parameter_values(
    @acquisition.parameterized_keyed_request_parameters(
      @acquisition.keyed_join_request(join),
    ),
  )
  match @lower.parameter_bindings(owner) {
    Some(bound) =>
      if !physical_equal(bound, parameters) {
        return Err(ForeignParameters)
      }
    None =>
      if @parameter.bound_value_count(parameters) != 0 {
        return Err(ForeignParameters)
      }
  }
  if !valid_input {
    return Err(ForeignInput)
  }
  if row < 0 || row >= rows {
    return Err(InvalidRow)
  }
  let keys = []
  let mut role = 0
  while @acquisition.keyed_join_role_at(join, role) is Some((_, pair)) {
    if role == limits.max_pairs {
      return Err(Request(@acquisition.PairLimit))
    }
    if remaining < 1 {
      return Err(WorkLimit)
    }
    remaining -= 1
    let mut column = -1
    for i in 0..<@schema.field_count(schema) {
      let field = @schema.field_at(schema, i).unwrap()
      let name = @schema.reference_name(field.name)
      let expected = @schema.reference_name(pair.left)
      // Reserve the visit and bounded name comparison before searching. The
      // exact checked FieldName, not value coincidence or a renamed alias,
      // identifies the input column.
      if remaining < 1 || name.length() > remaining - 1 {
        return Err(WorkLimit)
      }
      remaining -= name.length() + 1
      if expected.length() > remaining {
        return Err(WorkLimit)
      }
      remaining -= expected.length()
      if field.name == pair.left {
        column = i
        break
      }
    }
    if column < 0 {
      return Err(MissingColumn(role))
    }
    guard cell_at(column) is Some(cell) else {
      // Conditional absence is never changed into NULL or an empty request.
      return Err(MissingColumn(role))
    }
    // Convert the execution representation, not its type or authority. The
    // shared resumable request cursor rechecks the original role contract.
    let value = match cell {
      @execution.Captured(value) => Some(value)
      @execution.Null => Some(@value.null_value())
      @execution.Boolean(value) => Some(@value.boolean_value(value))
      @execution.Number(value) => @value.number_value(value)
      @execution.Text(value) => {
        if value.length() > remaining {
          return Err(WorkLimit)
        }
        remaining -= value.length()
        @value.text_value(value, limits.values.max_text_bytes)
      }
    }
    guard value is Some(value) else { return Err(InvalidValue(role)) }
    keys.push(value)
    role += 1
  }
  let extraction_work = limits.max_work - remaining
  match
    @acquisition.start_keyed_row_request(
      @acquisition.keyed_join_request(join),
      keys,
      { ..limits, max_work: remaining, },
    ) {
    Ok(cursor) => Ok((cursor, extraction_work))
    Err(issue) => Err(Request(issue))
  }
}
