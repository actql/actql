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
  relation : ManagedCompletionReference?
  carrier : CarrierManagedCompletionReference?
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
    relation: None,
    carrier: Some(carrier_managed_completed_reference(value.output)),
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
