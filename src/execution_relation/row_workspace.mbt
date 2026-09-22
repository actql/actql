///|
/// Per-operation structural storage bound, in container entries, not bytes.
/// It counts borrowed input entries, copied expression-view entries and live
/// continuations too. Immutable nested payload sizes use separate logical
/// budgets; this is not a heap meter.
priv struct RowWorkspace {
  limit : Int
  mut live : Int
  mut peak : Int
}

///|
fn row_workspace(limit : Int) -> RowWorkspace {
  { limit, live: if limit < 0 { -1 } else { 0 }, peak: 0, }
}

///|
fn reserve_slots(w : RowWorkspace, count : Int) -> Bool {
  if w.live < 0 || count < 0 || count > w.limit - w.live {
    return false
  }
  w.live += count
  w.peak = Int::max(w.peak, w.live)
  true
}

///|
/// Reserve an outer container and all fixed-width inner entries before either
/// allocation. This keeps rejected matrix dimensions from allocating first and
/// failing the logical workspace check afterward.
fn reserve_matrix_slots(w : RowWorkspace, outer : Int, inner : Int) -> Bool {
  if outer < 0 || inner < 0 || outer > w.limit - w.live {
    return false
  }
  let remaining = w.limit - w.live - outer
  if outer > 0 && inner > remaining / outer {
    return false
  }
  reserve_slots(w, outer + outer * inner)
}

///|
fn release_slots(w : RowWorkspace, count : Int) -> Unit {
  if w.live < 0 || count < 0 || count > w.live {
    w.live = -1
    return
  }
  w.live -= count
}

///|
fn workspace_healthy(w : RowWorkspace) -> Bool {
  w.live >= 0 && w.live <= w.limit
}

///|
priv struct SlotScope {
  workspace : RowWorkspace
  baseline : Int
  mut open : Bool
}

///|
fn begin_slot_scope(workspace : RowWorkspace, count : Int) -> SlotScope? {
  if !reserve_slots(workspace, count) {
    None
  } else {
    Some({ workspace, baseline: workspace.live - count, open: true, })
  }
}

///|
fn SlotScope::close(self : SlotScope, keep? : Int = 0) -> Bool {
  if !self.open || keep < 0 || self.workspace.live < 0 {
    self.workspace.live = -1
    return false
  }
  let used = self.workspace.live - self.baseline
  if keep > used {
    self.workspace.live = -1
    return false
  }
  self.open = false
  release_slots(self.workspace, used - keep)
  workspace_healthy(self.workspace)
}

///|
fn SlotScope::commit(self : SlotScope) -> Bool {
  if !self.open || !workspace_healthy(self.workspace) {
    self.workspace.live = -1
    return false
  }
  self.open = false
  true
}

///|
fn SlotScope::rollback(self : SlotScope) -> Bool {
  if !self.open {
    self.workspace.live = -1
    return false
  }
  self.open = false
  self.workspace.live = self.baseline
  true
}

///|
fn[T] with_scoped_slots(
  workspace : RowWorkspace,
  action : () -> Result[T, RowIssue],
) -> Result[T, RowIssue] {
  guard begin_slot_scope(workspace, 0) is Some(scope) else {
    return Err(RowLimit)
  }
  match action() {
    Ok(value) =>
      if scope.commit() {
        Ok(value)
      } else {
        scope.rollback() |> ignore
        Err(RowLimit)
      }
    Err(issue) => {
      let healthy = workspace_healthy(workspace)
      scope.rollback() |> ignore
      if healthy {
        Err(issue)
      } else {
        Err(RowLimit)
      }
    }
  }
}

///|
/// Charge and reserve one row container and its fixed-width cells before the
/// caller allocates either. The returned scope owns the reservation until the
/// row is committed or abandoned.
fn charge_row(
  workspace : RowWorkspace,
  control : ControlBudget,
  width : Int,
) -> SlotScope? {
  if width < 0 || width == 2147483647 {
    return None
  }
  let units = width + 1
  if !spend_control(control, units) {
    return None
  }
  begin_slot_scope(workspace, units)
}

///|
fn charge_named(control : ControlBudget, name : String) -> Bool {
  spend_control(control, 1) && spend_control_text(control, name)
}

///|
/// Charge the complete UTF-8 size before allocating a derived label.
fn charge_text_append(
  control : ControlBudget,
  prefix : String,
  ascii_suffix_bytes : Int,
) -> Bool {
  ascii_suffix_bytes >= 0 &&
  charge_named(control, prefix) &&
  spend_control(control, ascii_suffix_bytes)
}
