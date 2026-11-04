///|
// Serial DATA crosses the existing Common/physical adapter module boundary.
// Builtin Int.hash uses a module-local seed; an already populated Map cannot
// change that hash when another module operates on the SAME inventory.
// This nominal scalar retains Int's representation and adds no token/grant.
priv struct OriginalTokenSerial(Int) derive(Eq)

///|
impl Hash for OriginalTokenSerial with fn hash(self) {
  let OriginalTokenSerial(serial) = self
  serial
}

///|
impl Hash for OriginalTokenSerial with fn hash_combine(self, hasher) {
  let OriginalTokenSerial(serial) = self
  hasher.combine_int(serial)
}

///|
// Same-Ledger serial DATA selects an original; it never authenticates one.
// The builtin linked Map preserves live issuance order and unlinks by key.
// Only the scalar ordinal view is rebuilt, once when an actual indexed reader
// next needs it. No token array is shifted or searched during retirement.
priv struct OriginalTokenSlots[T] {
  mut values : Map[OriginalTokenSerial, T]
  order : Array[OriginalTokenSerial]
  mut order_dirty : Bool
}

///|
fn[T] original_token_slots(capacity? : Int = 0) -> OriginalTokenSlots[T] {
  { values: Map([]), order: Array(capacity~), order_dirty: false, }
}

///|
// The SAME inventory's owner has already admitted full Map construction/growth
// and this scalar backing. The builtin Map grows under that same envelope;
// this method does not copy/reissue originals or publish a spare logical slot.
fn[T] OriginalTokenSlots::reserve_capacity(
  self : OriginalTokenSlots[T],
  capacity : Int,
) -> Unit {
  self.order.reserve_capacity(capacity)
}

///|
fn[T] OriginalTokenSlots::length(self : OriginalTokenSlots[T]) -> Int {
  self.values.length()
}

///|
fn[T] OriginalTokenSlots::is_empty(self : OriginalTokenSlots[T]) -> Bool {
  self.values.is_empty()
}

///|
#alias("_[_]")
fn[T] OriginalTokenSlots::get(self : OriginalTokenSlots[T], index : Int) -> T {
  if self.order_dirty {
    self.order.clear()
    self.values.each(fn(serial, _) { self.order.push(serial) })
    self.order_dirty = false
  }
  self.values[self.order[index]]
}

///|
// Production serials are issued once by the SAME Ledger. White-box descriptor
// fixtures use explicit occurrence keys so duplicate inputs remain duplicates.
fn[T] OriginalTokenSlots::push(
  self : OriginalTokenSlots[T],
  value : T,
  serial : Int,
) -> Unit {
  self.values[OriginalTokenSerial(serial)] = value
  self.order_dirty = true
}

///|
fn[T] OriginalTokenSlots::by_serial(
  self : OriginalTokenSlots[T],
  serial : Int,
) -> T? {
  self.values.get(OriginalTokenSerial(serial))
}

///|
// A matching DATA key alone cannot remove a copied or foreign token.
fn[T] OriginalTokenSlots::remove_original(
  self : OriginalTokenSlots[T],
  serial : Int,
  original : T,
) -> Bool {
  let key = OriginalTokenSerial(serial)
  guard self.values.get(key) is Some(value) && physical_equal(value, original) else {
    return false
  }
  self.values.remove(key)
  self.order_dirty = true
  true
}

///|
fn[T] OriginalTokenSlots::any(
  self : OriginalTokenSlots[T],
  predicate : (T) -> Bool,
) -> Bool {
  for value in self.values.values() {
    if predicate(value) {
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
  // Map.clear clears every bucket and the head, dropping actual token refs.
  self.values.clear()
  self.order.clear()
  self.order_dirty = false
}

///|
fn[T] OriginalTokenSlots::shrink_to_fit(self : OriginalTokenSlots[T]) -> Unit {
  if self.values.is_empty() {
    self.values = Map([])
  }
  self.order.shrink_to_fit()
}
