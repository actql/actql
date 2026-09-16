///|
/// Key-only scratch for logical join obligations. Whole input rows remain in
/// their retained representation; provisional keys cannot produce evidence
/// until every exact attached input has finished content verification.
struct FixedJoinStream {
  owner : @lower.BoundPrepared
  profile : @lower.PreparedInnerJoin
  inputs : Array[ProducerRead]
  layout : FixedJoinValidationLayout
  limits : FixedJoinValidationLimits
  rows : Array[Array[Array[Value]]]
  attached : Array[Bool]
  verified : Array[Bool]
  mut open : Bool
}

///|
priv struct JoinKeyRows {
  rows : Array[Array[Value]]
  width : Int
}

///|
impl IndexedRows for JoinKeyRows with fn row_count(self) {
  self.rows.length()
}

///|
impl IndexedRows for JoinKeyRows with fn column_count(self) {
  self.width
}

///|
impl IndexedRows for JoinKeyRows with fn row_width(self, row) {
  self.rows[row].length()
}

///|
impl IndexedRows for JoinKeyRows with fn read_cell(self, row, column) {
  self.rows[row][column]
}

///|
pub fn cancel_fixed_join_stream(value : FixedJoinStream) -> Unit {
  value.open = false
  for rows in value.rows {
    rows.clear()
  }
}

///|
fn collect_fixed_join_keys(
  value : FixedJoinStream,
  port : Int,
  read : (Int) -> Value,
) -> Result[Unit, RowIssue] {
  if !value.open {
    return Err(InputMismatch)
  }
  let width = value.layout.keys.length()
  for side in 0..<2 {
    if port != (if side == 0 { value.layout.left } else { value.layout.right }) {
      continue
    }
    if value.rows[side].length() >= value.limits.max_rows ||
      !reserve_slots(value.layout.workspace, width) ||
      !reserve_slots(value.layout.workspace, 1) ||
      !spend_control(value.layout.control, width) {
      cancel_fixed_join_stream(value)
      return Err(RowLimit)
    }
    value.rows[side].push(
      value.layout.keys.map(pair => {
        read(if side == 0 { pair.0 } else { pair.1 })
      }),
    )
  }
  Ok(())
}

///|
pub fn prepare_fixed_join_stream(
  owner : @lower.BoundPrepared,
  profile : @lower.PreparedInnerJoin,
  inputs : Array[ProducerRead],
  limits : FixedJoinValidationLimits,
) -> Result[FixedJoinStream, RowIssue] {
  let layout = match
    prepare_fixed_join_validation_layout(owner, profile, inputs, limits) {
    Ok(layout) => layout
    Err(issue) => return Err(issue)
  }
  let value : FixedJoinStream = {
    owner,
    profile,
    inputs: inputs.copy(),
    layout,
    limits,
    rows: [[], []],
    attached: Array::make(inputs.length(), false),
    verified: Array::make(inputs.length(), false),
    open: true,
  }
  for port, input in inputs {
    if input.bound.output.table is Some(table) {
      let reader = ProducerGuardRows::{ input, table, }
      for row in 0..<producer_read_row_count(input) {
        match
          collect_fixed_join_keys(value, port, column => {
            IndexedRows::read_cell(reader, row, column)
          }) {
          Ok(_) => ()
          Err(issue) => return Err(issue)
        }
      }
      value.attached[port] = true
      value.verified[port] = true
    }
  }
  Ok(value)
}

///|
pub fn attach_retained_join_scan(
  scan : RetainedProducerScan,
  value : FixedJoinStream,
) -> Result[Unit, RowIssue] {
  let port = producer_read_input_index(scan.input)
  if !value.open ||
    !scan.open ||
    scan.stream.rows != 0 ||
    scan.join_validation is Some(_) ||
    port < 0 ||
    port >= value.inputs.length() ||
    value.attached[port] ||
    !physical_equal(value.inputs[port], scan.input) {
    return Err(InputMismatch)
  }
  value.attached[port] = true
  scan.join_validation = Some(value)
  Ok(())
}

///|
pub fn finish_fixed_join_stream(
  value : FixedJoinStream,
) -> Result[FixedJoinValidation, RowIssue] {
  if !value.open ||
    !value.verified.all(verified => verified) ||
    !value.inputs.all(input => producer_read_available(input)) {
    cancel_fixed_join_stream(value)
    return Err(InputMismatch)
  }
  let width = value.layout.keys.length()
  if !reserve_slots(value.layout.workspace, width) ||
    !reserve_slots(value.layout.workspace, width) ||
    !reserve_slots(value.layout.workspace, 2) ||
    !spend_control(value.layout.control, width) {
    cancel_fixed_join_stream(value)
    return Err(RowLimit)
  }
  let keys = Array::makei(width, column => (column, column))
  let orders = Array::makei(width, column => ColumnOrder::{
    column,
    descending: false,
    nulls_first: true,
  })
  let result = validate_join_obligations(
    value.profile,
    JoinKeyRows::{ rows: value.rows[0], width, },
    JoinKeyRows::{ rows: value.rows[1], width, },
    keys,
    [orders, orders],
    value.layout.control,
    value.layout.workspace,
  )
  cancel_fixed_join_stream(value)
  match result {
    Err(issue) => Err(issue)
    Ok(_) =>
      Ok({
        owner: value.owner,
        profile: value.profile,
        inputs: value.inputs.copy(),
        work: value.limits.max_work - value.layout.control.remaining,
        peak: value.layout.workspace.peak,
      })
  }
}
