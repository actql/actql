///|
// Reusable control slots owned by the existing Ledger inventory. Vacated
// references become None; index order preserves the live issuance inventory.
// Neither array is an identity issuer, capacity grant or independent owner.
priv struct OriginalTokenSlots[T] {
  slots : Array[T?]
  order : Array[Int]
}

///|
fn[T] original_token_slots(capacity? : Int = 0) -> OriginalTokenSlots[T] {
  { slots: Array(capacity~), order: Array(capacity~), }
}

///|
fn[T] OriginalTokenSlots::length(self : OriginalTokenSlots[T]) -> Int {
  self.order.length()
}

///|
fn[T] OriginalTokenSlots::is_empty(self : OriginalTokenSlots[T]) -> Bool {
  self.order.is_empty()
}

///|
#alias("_[_]")
fn[T] OriginalTokenSlots::get(self : OriginalTokenSlots[T], index : Int) -> T {
  self.slots[self.order[index]].unwrap()
}

///|
fn[T] OriginalTokenSlots::push(self : OriginalTokenSlots[T], value : T) -> Unit {
  for index in 0..<self.slots.length() {
    if self.slots[index] is None {
      self.slots[index] = Some(value)
      self.order.push(index)
      return
    }
  }
  let index = self.slots.length()
  self.slots.push(Some(value))
  self.order.push(index)
}

///|
fn[T] OriginalTokenSlots::remove(
  self : OriginalTokenSlots[T],
  index : Int,
) -> T {
  let slot = self.order.remove(index)
  let value = self.slots[slot].unwrap()
  // Array.remove on non-JS backends retains an unused tail reference. Only
  // scalar indices use it here; the actual token slot is explicitly cleared.
  self.slots[slot] = None
  value
}

///|
fn[T] OriginalTokenSlots::any(
  self : OriginalTokenSlots[T],
  predicate : (T) -> Bool,
) -> Bool {
  for index in 0..<self.length() {
    if predicate(self[index]) {
      return true
    }
  }
  false
}

///|
fn[T] OriginalTokenSlots::all(
  self : OriginalTokenSlots[T],
  predicate : (T) -> Bool,
) -> Bool {
  !self.any(value => !predicate(value))
}

///|
fn[T, U] OriginalTokenSlots::map(
  self : OriginalTokenSlots[T],
  f : (T) -> U,
) -> Array[U] {
  Array::makei(self.length(), index => f(self[index]))
}

///|
fn[T] OriginalTokenSlots::clear(self : OriginalTokenSlots[T]) -> Unit {
  for index in 0..<self.slots.length() {
    self.slots[index] = None
  }
  self.slots.clear()
  self.slots.release_unused(placeholder=None)
  self.order.clear()
}

///|
fn[T] OriginalTokenSlots::shrink_to_fit(self : OriginalTokenSlots[T]) -> Unit {
  self.slots.shrink_to_fit()
  self.order.shrink_to_fit()
}
