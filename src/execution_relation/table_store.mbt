///|
priv struct HeldTable[T] {
  table : T
  units : Int
}

///|
/// Private fragment storage, not execution admission. Only the future admitted
/// driver may supply successfully evaluated tables. No public constructors.
priv struct TableStore[T] {
  wiring : Wiring
  tables : Array[HeldTable[T]?]
  workspace : RowWorkspace
  mut next : Int
}

///|
pub(all) enum StoreIssue {
  InvalidState
  OwnerMismatch
  MissingInput
  Limit
}

///|
fn[T] table_store(
  wiring : Wiring,
  workspace : RowWorkspace,
) -> Result[TableStore[T], StoreIssue] {
  if workspace.limit < 0 || workspace.live != 0 || workspace.peak != 0 {
    return Err(InvalidState)
  }
  if !reserve_slots(workspace, wiring.ids.length()) {
    return Err(Limit)
  }
  Ok({
    wiring,
    tables: Array::make(wiring.ids.length(), None),
    workspace,
    next: 0,
  })
}

///|
fn[T : RelationRows] reserve_table(
  table : T,
  store : TableStore[T],
  control : ControlBudget,
) -> Result[HeldTable[T], StoreIssue] {
  let before = store.workspace.live
  let width = table.field_names().length()
  let count = IndexedRows::row_count(table)
  if !reserve_slots(store.workspace, width) ||
    !reserve_slots(store.workspace, count) {
    return Err(Limit)
  }
  for row = 0; row < count; row = row + 1 {
    if !spend_control(control, 1) ||
      !reserve_slots(store.workspace, IndexedRows::row_width(table, row)) {
      return Err(Limit)
    }
    if IndexedRows::row_width(table, row) != width {
      return Err(InvalidState)
    }
  }
  Ok({ table, units: store.workspace.live - before, })
}

///|
fn[T] drop_table(store : TableStore[T], slot : Int) -> Unit {
  if store.tables[slot] is Some(held) {
    store.tables[slot] = None
    release_slots(store.workspace, held.units)
  }
}

///|
fn[T : RelationRows] install_table_input(
  store : TableStore[T],
  slot : Int,
  table : T,
  control : ControlBudget,
) -> Result[Unit, StoreIssue] {
  if store.next != 0 ||
    slot < 0 ||
    slot >= store.wiring.input_count ||
    store.tables[slot] is Some(_) {
    return Err(InvalidState)
  }
  if !physical_equal(table.checked_owner(), store.wiring.owner) {
    return Err(OwnerMismatch)
  }
  if !spend_control_text(control, table.relation_id()) {
    return Err(Limit)
  }
  if table.relation_id() != store.wiring.ids[slot] {
    return Err(InvalidState)
  }
  let held = match reserve_table(table, store, control) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  store.tables[slot] = Some(held)
  // Unreferenced supplied inputs need not remain after their admission.
  if store.wiring.last_use[slot] < 0 && !store.wiring.retained[slot] {
    drop_table(store, slot)
  }
  Ok(())
}

///|
fn[T : RelationRows] commit_table(
  store : TableStore[T],
  step : Int,
  table : T,
  control : ControlBudget,
) -> Result[Unit, StoreIssue] {
  if step != store.next || step < 0 || step >= store.wiring.routes.length() {
    return Err(InvalidState)
  }
  if !physical_equal(table.checked_owner(), store.wiring.owner) {
    return Err(OwnerMismatch)
  }
  let slot = store.wiring.input_count + step
  if !spend_control(control, 1) ||
    !spend_control_text(control, table.relation_id()) {
    return Err(Limit)
  }
  if table.relation_id() != store.wiring.ids[slot] ||
    store.tables[slot] is Some(_) {
    return Err(InvalidState)
  }
  let route = store.wiring.routes[step]
  // Validate and precharge all work before changing any retained table.
  for source in route {
    if !spend_control(control, 1) {
      return Err(Limit)
    }
    if store.tables[source] is None {
      return Err(MissingInput)
    }
  }
  let held = match reserve_table(table, store, control) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  store.tables[slot] = Some(held)
  for source in route {
    if store.wiring.last_use[source] == step && !store.wiring.retained[source] {
      drop_table(store, source)
    }
  }
  if store.wiring.last_use[slot] == step && !store.wiring.retained[slot] {
    drop_table(store, slot)
  }
  store.next += 1
  Ok(())
}
