///|
priv struct RowNameCharge {
  name : String
  workspace : RowWorkspace
  mut offset : Int
  mut bytes : Int
  mut closed : Bool
}

///|
fn start_row_name_charge(
  name : String,
  workspace : RowWorkspace,
) -> RowNameCharge? {
  if !reserve_slots(workspace, 1) {
    return None
  }
  Some({ name, workspace, offset: 0, bytes: 0, closed: false, })
}

///|
fn close_row_name_charge(cursor : RowNameCharge) -> Unit {
  if !cursor.closed {
    cursor.closed = true
    release_slots(cursor.workspace, 1)
  }
}

///|
/// Preserve atomic Value name accounting. Control names instead pay each
/// scalar's original byte charge; neither path normalizes identifier spelling.
fn advance_row_name_charge(
  cursor : RowNameCharge,
  control : ControlBudget?,
  value : ValueBudget?,
) -> Result[Bool, RowIssue] {
  if cursor.closed {
    return Err(InvalidRows)
  }
  if cursor.offset < cursor.name.length() {
    guard text_function_scalar(cursor.name, cursor.offset)
      is Some((_, next, width, _)) else {
      return Err(RowLimit)
    }
    if control is Some(budget) && !spend_control(budget, width) {
      return Err(RowLimit)
    }
    if value is Some(budget) &&
      width >
      Int::min(
        budget.limits.max_text_bytes - budget.text,
        remaining_value_work(budget),
      ) -
      cursor.bytes {
      return Err(RowLimit)
    }
    cursor.bytes += width
    cursor.offset = next
    return Ok(false)
  }
  if value is Some(budget) {
    budget.text += cursor.bytes
    budget.work += cursor.bytes
  }
  close_row_name_charge(cursor)
  Ok(true)
}

///|
priv enum RowNameIssue {
  NameValueLimit
  NameWorkspaceLimit
}

///|
/// The caller pays the entry charge once. Text bytes retain their prior
/// control cost, independently of the number of physical resume fragments.
fn advance_binding_name_control_bytes(
  state : BoundedBindingRowsState,
  name : String,
) -> Result[Bool, RowIssue] {
  if name.length() <= 64 {
    return if spend_control_text(state.control, name) {
      Ok(true)
    } else {
      Err(RowLimit)
    }
  }
  if state.name_charge is None {
    guard start_row_name_charge(name, state.workspace) is Some(cursor) else {
      return Err(RowLimit)
    }
    state.name_charge = Some(cursor)
  }
  match
    advance_row_name_charge(
      state.name_charge.unwrap(),
      Some(state.control),
      None,
    ) {
    Err(issue) => Err(issue)
    Ok(false) => Ok(false)
    Ok(true) => {
      state.name_charge = None
      Ok(true)
    }
  }
}

///|
fn advance_binding_name_value(
  state : BoundedBindingRowsState,
  name : String,
  budget : ValueBudget,
) -> Result[Bool, RowNameIssue] {
  if name.length() <= 64 {
    return if charge_text(budget, name) {
      Ok(true)
    } else {
      Err(NameValueLimit)
    }
  }
  if state.name_charge is None {
    guard start_row_name_charge(name, state.workspace) is Some(cursor) else {
      return Err(NameWorkspaceLimit)
    }
    state.name_charge = Some(cursor)
  }
  match
    advance_row_name_charge(state.name_charge.unwrap(), None, Some(budget)) {
    Err(_) => Err(NameValueLimit)
    Ok(false) => Ok(false)
    Ok(true) => {
      state.name_charge = None
      Ok(true)
    }
  }
}

///|
fn binding_row_source(
  state : BoundedBindingRowsState,
  column : Int,
) -> BindingRowSource? {
  if !state.row_sources.is_empty() {
    return state.row_sources.get(column)
  }
  // An empty cache is issued only for <=8 entries and <=64-unit spellings.
  let name = state.output_names[column]
  match state.projection_ordinals {
    Some(projection) =>
      match projection.get(name) {
        Some(index) => Some(InputColumn(index))
        None => Some(GeneratedColumn)
      }
    None =>
      match state.binding_ordinals.get(name) {
        Some(index) => Some(BindingColumn(index))
        None => state.input_ordinals.get(name).map(index => InputColumn(index))
      }
  }
}
