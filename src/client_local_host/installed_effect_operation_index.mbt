///|
// Actual declared operation coordinates only, without names, CIDs or mutable
// authority. The optional private probe output is transient on lookup keys;
// stored keys always retain None. It is excluded from equality and hashing.
priv struct ClientEffectOperationCoordinate {
  member_index : Int
  per_row : Bool
  operation_index : Int
  row_index : Int
  lookup_probes : Ref[Int64]?
}

///|
impl Eq for ClientEffectOperationCoordinate with fn equal(a, b) {
  record_effect_operation_lookup_probe(
    if a.lookup_probes is Some(_) {
      a.lookup_probes
    } else {
      b.lookup_probes
    },
  )
  a.member_index == b.member_index &&
  a.per_row == b.per_row &&
  a.operation_index == b.operation_index &&
  a.row_index == b.row_index
}

///|
impl Hash for ClientEffectOperationCoordinate with fn hash_combine(self, hasher) {
  record_effect_operation_lookup_probe(self.lookup_probes)
  hasher.combine(self.member_index)
  hasher.combine(self.per_row)
  hasher.combine(self.operation_index)
  hasher.combine(self.row_index)
}

///|
// The existing Run control slot retains its SAME original capacity token and
// the coordinate-to-stable-slot index. This is not a cleanup or Resource owner.
// Spent coordinates outlive body retirement without retaining the heavy view.
priv struct ClientEffectOperationControls {
  reservation : @resources.CapacityReservation
  coordinates : Map[ClientEffectOperationCoordinate, Int]
  construction_deferred : Bool
  mut construction_active : Bool
  // One same-Run Preview input; its existing producer retains wire storage.
  mut host_input : (String, @execution.ExecutionCapacity)?
}
