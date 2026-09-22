///|
/// Type-erased evidence for one exact managed producer use site. This keeps
/// Relation and non-Relation Carrier inputs in one authored order without
/// exposing either representation payload.
struct ManagedInputBinding {
  identity : Ref[Unit]
  receiver : @lower.BoundPrepared
  consumer_step : Int?
  input_index : Int
  kind : @carrier.Kind
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
    consumer_step: None,
    input_index: producer_read_input_index(value),
    kind: @carrier.RelationKind,
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
    consumer_step: value.consumer_step,
    input_index: value.input_index,
    kind: @carrier.RelationKind,
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
    consumer_step: value.consumer_step,
    input_index: value.input_index,
    kind: carrier_managed_completed_output_kind(value.output),
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
    consumer_step: None,
    input_index: supplied_relation_read_input_index(value),
    kind: @carrier.RelationKind,
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
  value.consumer_step is None &&
  physical_equal(value.receiver, receiver) &&
  value.input_index == input_index &&
  managed_input_binding_available(value)
}

///|
pub fn managed_input_binding_matches_operation_input(
  value : ManagedInputBinding,
  receiver : @lower.BoundPrepared,
  consumer_step : Int,
  input_index : Int,
) -> Bool {
  value.consumer_step == Some(consumer_step) &&
  physical_equal(value.receiver, receiver) &&
  value.input_index == input_index &&
  managed_input_binding_available(value)
}

///|
/// Rebind a verified pipeline input to its exact operation-local position.
/// Existing internal-operation bindings are checked rather than relabeled.
pub fn managed_input_binding_for_operation(
  value : ManagedInputBinding,
  receiver : @lower.BoundPrepared,
  consumer_step : Int,
  input_index : Int,
) -> ManagedInputBinding? {
  if !managed_input_binding_available(value) ||
    !physical_equal(value.receiver, receiver) {
    return None
  }
  let prepared = @lower.bound_preparation(receiver)
  guard @lower.node_at(prepared, consumer_step) is Some(node) &&
    @lower.node_input_target(node, input_index) is Some(target) &&
    @lower.preparation_carrier_at(prepared, target) is Some(carrier) &&
    @carrier.kind(carrier) == value.kind else {
    return None
  }
  let exact = match target {
    @pipeline.Input(pipeline_input) =>
      value.consumer_step is None && value.input_index == pipeline_input
    @pipeline.Step(_) =>
      value.consumer_step == Some(consumer_step) &&
      value.input_index == input_index
  }
  if !exact {
    return None
  }
  Some({ ..value, consumer_step: Some(consumer_step), input_index, })
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
