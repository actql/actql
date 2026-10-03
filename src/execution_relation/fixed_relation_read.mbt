///|
/// One exact receiving port for fixed Compute. Supplied rows remain bound to
/// their checked Stage input and are not manufactured as producer completions.
pub enum FixedRelationRead {
  CompletedRelation(ProducerRead)
  SuppliedRelation(SuppliedRelationRead)
}

///|
pub fn fixed_completed_relation_read(read : ProducerRead) -> FixedRelationRead {
  CompletedRelation(read)
}

///|
pub fn fixed_supplied_relation_read(
  read : SuppliedRelationRead,
) -> FixedRelationRead {
  SuppliedRelation(read)
}

///|
pub fn fixed_relation_read_receiver(
  read : FixedRelationRead,
) -> @lower.BoundPrepared {
  match read {
    CompletedRelation(value) => producer_read_receiver(value)
    SuppliedRelation(value) => supplied_relation_read_receiver(value)
  }
}

///|
pub fn fixed_relation_read_available(read : FixedRelationRead) -> Bool {
  match read {
    CompletedRelation(value) => producer_read_available(value)
    SuppliedRelation(value) => supplied_relation_read_available(value)
  }
}

///|
pub fn fixed_relation_read_row_count(read : FixedRelationRead) -> Int {
  match read {
    CompletedRelation(value) => producer_read_row_count(value)
    SuppliedRelation(value) => supplied_relation_read_row_count(value)
  }
}

///|
pub fn fixed_relation_read_matches_input(
  read : FixedRelationRead,
  owner : @lower.BoundPrepared,
  input_index : Int,
) -> Bool {
  match read {
    CompletedRelation(value) =>
      physical_equal(producer_read_receiver(value), owner) &&
      producer_read_input_index(value) == input_index &&
      producer_read_available(value)
    SuppliedRelation(value) =>
      supplied_relation_read_matches_input(value, owner, input_index)
  }
}

///|
pub fn fixed_relation_read_matches_operation_input(
  read : FixedRelationRead,
  owner : @lower.BoundPrepared,
  step : Int,
  input_index : Int,
) -> Bool {
  match read {
    CompletedRelation(value) =>
      producer_read_matches_operation_input(value, owner, step, input_index)
    SuppliedRelation(value) =>
      supplied_relation_read_matches_operation_input(
        value, owner, step, input_index,
      )
  }
}

///|
pub fn fixed_relation_read_completed(read : FixedRelationRead) -> ProducerRead? {
  match read {
    CompletedRelation(value) => Some(value)
    SuppliedRelation(_) => None
  }
}

///|
pub fn fixed_relation_read_supplied(
  read : FixedRelationRead,
) -> SuppliedRelationRead? {
  match read {
    CompletedRelation(_) => None
    SuppliedRelation(value) => Some(value)
  }
}

///|
pub fn fixed_relation_read_same(
  left : FixedRelationRead,
  right : FixedRelationRead,
) -> Bool {
  match (left, right) {
    (CompletedRelation(a), CompletedRelation(b)) =>
      producer_read_same_binding(a, b)
    (SuppliedRelation(a), SuppliedRelation(b)) =>
      supplied_relation_read_same_binding(a, b)
    _ => false
  }
}
