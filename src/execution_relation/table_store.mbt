///|
priv struct HeldTable {
  table : Table
  units : Int
}

///|
/// Private fragment storage, not execution admission. Only the future admitted
/// driver may supply successfully evaluated tables. No public constructors.
priv struct TableStore {
  wiring : Wiring
  tables : Array[HeldTable?]
  workspace : RowWorkspace
  mut next : Int
}

///|
priv enum StoreIssue {
  InvalidState
  OwnerMismatch
  MissingInput
  Limit
}

///|
fn table_store(
  wiring : Wiring,
  workspace : RowWorkspace,
) -> Result[TableStore, StoreIssue] {
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
fn reserve_table(
  table : Table,
  store : TableStore,
  control : ControlBudget,
) -> Result[HeldTable, StoreIssue] {
  let before = store.workspace.live
  if !reserve_slots(store.workspace, table.names.length()) ||
    !reserve_slots(store.workspace, table.rows.length()) {
    return Err(Limit)
  }
  for row in table.rows {
    if !spend_control(control, 1) ||
      !reserve_slots(store.workspace, row.length()) {
      return Err(Limit)
    }
    if row.length() != table.names.length() {
      return Err(InvalidState)
    }
  }
  Ok({ table, units: store.workspace.live - before, })
}

///|
fn drop_table(store : TableStore, slot : Int) -> Unit {
  if store.tables[slot] is Some(held) {
    store.tables[slot] = None
    release_slots(store.workspace, held.units)
  }
}

///|
fn install_table_input(
  store : TableStore,
  slot : Int,
  table : Table,
  control : ControlBudget,
) -> Result[Unit, StoreIssue] {
  if store.next != 0 ||
    slot < 0 ||
    slot >= store.wiring.input_count ||
    store.tables[slot] is Some(_) {
    return Err(InvalidState)
  }
  if !physical_equal(table.owner, store.wiring.owner) {
    return Err(OwnerMismatch)
  }
  if !spend_control_text(control, table.id) {
    return Err(Limit)
  }
  if table.id != store.wiring.ids[slot] {
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
fn commit_table(
  store : TableStore,
  step : Int,
  table : Table,
  control : ControlBudget,
) -> Result[Unit, StoreIssue] {
  if step != store.next || step < 0 || step >= store.wiring.routes.length() {
    return Err(InvalidState)
  }
  if !physical_equal(table.owner, store.wiring.owner) {
    return Err(OwnerMismatch)
  }
  let slot = store.wiring.input_count + step
  if !spend_control(control, 1) || !spend_control_text(control, table.id) {
    return Err(Limit)
  }
  if table.id != store.wiring.ids[slot] || store.tables[slot] is Some(_) {
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
