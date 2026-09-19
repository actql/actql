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
fn reserve_slots(w : RowWorkspace, count : Int) -> Bool {
  if count < 0 || count > w.limit - w.live {
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
  w.live -= count
}
