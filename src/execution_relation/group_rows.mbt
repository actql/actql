///|
/// Group/count uses the ordinary retained-output sink. Input keys are read
/// through storage coordinates; no input row snapshots or expression roots
/// are constructed for direct-field counts.
fn[T : RelationRows] evaluate_count_group_into(
  group : @lower.PreparedCountGroup,
  input : T,
  max_rows : Int,
  control : ControlBudget,
  output : ValueBudget,
  workspace : RowWorkspace,
  accept_row : (Array[Value], Int, Array[String], Array[Int]?) -> Result[
    Unit,
    RowIssue,
  ],
) -> Result[Array[String], RowIssue] {
  let names = input.field_names()
  let ordinals : Map[String, Int] = Map([])
  for i in 0..<names.length() {
    if !spend_control(control, 1) ||
      !spend_control_text(control, names[i]) ||
      !reserve_slots(workspace, 1) {
      return Err(RowLimit)
    }
    if ordinals.contains(names[i]) {
      return Err(InvalidRows)
    }
    ordinals[names[i]] = i
  }
  let resolve = fn(field : @schema.FieldName) -> Result[Int, RowIssue] {
    let name = @schema.reference_name(field)
    if !spend_control(control, 1) || !spend_control_text(control, name) {
      return Err(RowLimit)
    }
    match ordinals.get(name) {
      Some(i) => Ok(i)
      None => Err(InvalidRows)
    }
  }
  let key_count = @lower.count_group_key_count(group)
  let count_count = @lower.count_group_aggregate_count(group)
  if !reserve_slots(workspace, key_count) ||
    !reserve_slots(workspace, count_count) ||
    !reserve_slots(workspace, count_count) {
    return Err(RowLimit)
  }
  let order : Array[ColumnOrder] = []
  for i in 0..<key_count {
    let column = match resolve(@lower.count_group_key_at(group, i).unwrap()) {
      Ok(i) => i
      Err(e) => return Err(e)
    }
    order.push({ column, descending: false, nulls_first: true, })
  }
  let columns : Array[Int?] = []
  let count_names : Map[String, Int] = Map([])
  for i in 0..<count_count {
    let count = @lower.count_group_aggregate_at(group, i).unwrap()
    if !spend_control(control, 1) || !spend_control_text(control, count.name) {
      return Err(RowLimit)
    }
    count_names[count.name] = i
    columns.push(
      match count.field {
        None => None
        Some(field) =>
          match resolve(field) {
            Ok(i) => Some(i)
            Err(e) => return Err(e)
          }
      },
    )
  }
  let schema = @lower.count_group_output_schema(group)
  let width = @schema.field_count(schema)
  if !reserve_slots(workspace, width) || !reserve_slots(workspace, width) {
    return Err(RowLimit)
  }
  let output_names : Array[String] = []
  // (true, i) reads the aggregate vector; (false, i) reads a key cell.
  let projection : Array[(Bool, Int)] = []
  for i in 0..<width {
    let field = @schema.field_at(schema, i).unwrap().name
    let name = @schema.reference_name(field)
    if !spend_control(control, 1) || !spend_control_text(control, name) {
      return Err(RowLimit)
    }
    output_names.push(name)
    match count_names.get(name) {
      Some(index) => projection.push((true, index))
      None =>
        match resolve(field) {
          Ok(index) => projection.push((false, index))
          Err(e) => return Err(e)
        }
    }
  }
  let groups = match
    count_groups(input, order, columns, max_rows, control, workspace) {
    Ok(groups) => groups
    Err(InvalidInput) => return Err(InvalidRows)
    Err(Limit) => return Err(RowLimit)
    Err(Scalar(e)) => return Err(Comparison(e))
  }
  for group in groups {
    if !spend_control(control, 1) ||
      !spend_control(control, width) ||
      !reserve_slots(workspace, 1) ||
      !reserve_slots(workspace, width) {
      return Err(RowLimit)
    }
    let row : Array[Value] = []
    for (aggregate, index) in projection {
      if aggregate {
        row.push(Number(group.counts[index].to_double()))
      } else {
        guard group.representative is Some(source) else {
          return Err(InvalidRows)
        }
        row.push(IndexedRows::read_cell(input, source, index))
      }
    }
    if !retain_row(row, output_names, output) {
      return Err(RowLimit)
    }
    match
      accept_row(row, group.representative.unwrap_or(-1), output_names, None) {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
  }
  Ok(output_names)
}
