///|
/// Per-operation structural storage bound, in container entries, not bytes.
/// It counts borrowed input entries too. Immutable nested payload sizes and
/// expression continuations use their own budgets; this is not a heap meter.
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
fn release_slots(w : RowWorkspace, count : Int) -> Unit {
  w.live -= count
}
