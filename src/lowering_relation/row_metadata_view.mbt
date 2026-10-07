///|
/// Indexed immutable bindings from the exact checked kernel. Neither the
/// canonical map order nor authored ordered-binding occurrences are rebuilt.
struct PreparedBindings {
  bindings : Array[(String, Expression)]
  ordered : Bool
}

///|
pub fn kernel_bindings(kernel : PreparedKernel) -> PreparedBindings? {
  match kernel.body {
    SnapshotMap(bindings) => Some({ bindings, ordered: false, })
    OrderedBindings(bindings) => Some({ bindings, ordered: true, })
    _ => None
  }
}

///|
pub fn bindings_ordered(view : PreparedBindings) -> Bool {
  view.ordered
}

///|
pub fn bindings_count(view : PreparedBindings) -> Int {
  view.bindings.length()
}

///|
pub fn binding_at(
  view : PreparedBindings,
  index : Int,
) -> (String, Expression)? {
  view.bindings.get(index)
}

///|
struct PreparedUniqueKeys {
  keys : Array[@schema.FieldName]
}

///|
pub fn kernel_unique_keys(kernel : PreparedKernel) -> PreparedUniqueKeys? {
  match kernel.body {
    AssertUnique(keys) => Some({ keys, })
    _ => None
  }
}

///|
pub fn unique_key_count(view : PreparedUniqueKeys) -> Int {
  view.keys.length()
}

///|
pub fn unique_key_at(
  view : PreparedUniqueKeys,
  index : Int,
) -> @schema.FieldName? {
  view.keys.get(index)
}
