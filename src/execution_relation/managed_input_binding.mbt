///|
/// Type-erased evidence for one exact managed producer use site. This keeps
/// Relation and non-Relation Carrier inputs in one authored order without
/// exposing either representation payload.
struct ManagedInputBinding {
  identity : Ref[Unit]
  receiver : @lower.BoundPrepared
  input_index : Int
  profile_cid : String
  available : () -> Bool
  ordinary : ProducerRead?
  supplied : SuppliedRelationRead?
  relation : ManagedCompletionReference?
  carrier : CarrierManagedCompletionReference?
}

///|
/// Admit an exact ordinary Relation producer at a managed consumer boundary.
/// This preserves the original completion and receiving-port evidence; it does
/// not manufacture a managed producer occurrence or infer identity from rows.
pub fn ordinary_relation_input_binding(
  value : ProducerRead,
) -> ManagedInputBinding {
  {
    identity: Ref(()),
    receiver: producer_read_receiver(value),
    input_index: producer_read_input_index(value),
    profile_cid: managed_execution_profile_cid(
      selected_managed_execution_profile(),
    ),
    available: fn() { producer_read_available(value) },
    ordinary: Some(value),
    supplied: None,
    relation: None,
    carrier: None,
  }
}

///|
pub fn[T] managed_relation_input_binding(
  value : ManagedProducerRead[T],
) -> ManagedInputBinding {
  {
    identity: value.identity,
    receiver: value.receiver,
    input_index: value.input_index,
    profile_cid: managed_execution_profile_cid(value.output.profile),
    available: fn() { managed_producer_read_available(value) },
    ordinary: None,
    supplied: None,
    relation: Some(managed_completed_reference(value.output)),
    carrier: None,
  }
}

///|
pub fn managed_carrier_input_binding(
  value : CarrierManagedProducerRead,
) -> ManagedInputBinding {
  {
    identity: value.identity,
    receiver: value.receiver,
    input_index: value.input_index,
    profile_cid: managed_execution_profile_cid(value.output.profile),
    available: fn() { carrier_managed_producer_read_available(value) },
    ordinary: None,
    supplied: None,
    relation: None,
    carrier: Some(carrier_managed_completed_reference(value.output)),
  }
}

///|
pub fn supplied_relation_input_binding(
  value : SuppliedRelationRead,
) -> ManagedInputBinding {
  {
    identity: Ref(()),
    receiver: supplied_relation_read_receiver(value),
    input_index: supplied_relation_read_input_index(value),
    profile_cid: managed_execution_profile_cid(
      selected_managed_execution_profile(),
    ),
    available: fn() { supplied_relation_read_available(value) },
    ordinary: None,
    supplied: Some(value),
    relation: None,
    carrier: None,
  }
}

///|
pub fn managed_input_binding_profile_cid(value : ManagedInputBinding) -> String {
  value.profile_cid
}

///|
pub fn managed_input_binding_available(value : ManagedInputBinding) -> Bool {
  (value.available)()
}

///|
pub fn managed_input_binding_matches_input(
  value : ManagedInputBinding,
  receiver : @lower.BoundPrepared,
  input_index : Int,
) -> Bool {
  physical_equal(value.receiver, receiver) &&
  value.input_index == input_index &&
  managed_input_binding_available(value)
}

///|
pub fn managed_input_binding_same(
  left : ManagedInputBinding,
  right : ManagedInputBinding,
) -> Bool {
  physical_equal(left.identity, right.identity)
}

///|
pub fn managed_input_binding_matches_relation_reference(
  value : ManagedInputBinding,
  reference : ManagedCompletionReference,
) -> Bool {
  value.relation
  .map(actual => {
    managed_completed_reference_same(actual, reference) &&
    managed_input_binding_available(value)
  })
  .unwrap_or(false)
}

///|
/// Match only the exact ordinary receiving binding retained by the graph.
pub fn managed_input_binding_matches_ordinary_read(
  value : ManagedInputBinding,
  read : ProducerRead,
) -> Bool {
  value.ordinary
  .map(actual => {
    producer_read_same_binding(actual, read) &&
    managed_input_binding_available(value)
  })
  .unwrap_or(false)
}

///|
pub fn managed_input_binding_matches_supplied_read(
  value : ManagedInputBinding,
  read : SuppliedRelationRead,
) -> Bool {
  value.supplied
  .map(actual => {
    supplied_relation_read_same_binding(actual, read) &&
    managed_input_binding_available(value)
  })
  .unwrap_or(false)
}

///|
pub fn managed_input_binding_matches_carrier_reference(
  value : ManagedInputBinding,
  reference : CarrierManagedCompletionReference,
) -> Bool {
  value.carrier
  .map(actual => {
    carrier_managed_completed_reference_same(actual, reference) &&
    managed_input_binding_available(value)
  })
  .unwrap_or(false)
}
