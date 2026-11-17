///|
/// Fixed logical Node Host controls on the original Request, not SDK buffers,
/// opaque engine/GC storage, a Ledger limit or permission. The Node bridge
/// supplies this inventory through the existing caller_material grow before
/// Graph/module/operation construction. Keep its full debit until the same
/// Request retires; completing the Graph does not release future shell duty.
pub fn installed_node_model_async_control_inventory(
  max_items : Int,
) -> @execution.PreparationRepresentationUnits? {
  if max_items < 0 {
    return None
  }
  // Constructor-owned records/arrays and closure context bounds:
  // component29H/226R; operation205H/1189R; nominal wake4H/11R;
  // claimed wake5H/21R; one-shot original open14H/44R; start1H;
  // binding2H/5R. These bounds include all alternative fixed slots/captures,
  // not copied bodies, per-row payloads or completed work counts.
  // One live waiter/ticket6H/9R; run/stop/close callbacks10H/7R;
  // seven additional Promise carriers7H/14R; caller handoff6H/17R;
  // two retained failure records2H/8R. Promise/closure logical carriers use
  // this SAME shared representation tariff, not a claimed V8 heap layout.
  // Eight named carriers can overlap while close stops an AwaitIo run:
  // drive()'s async result uses 1H/2R within operation205H/1189R above;
  // the seven additional carriers are its .then flight, detached .catch
  // observer, ticket.promise, close's async IIFE, stop()'s async result,
  // stop's flight.catch await, and closeFlight.catch observer. Resolving a
  // ticket does not release its retained carrier before finally disposes it.
  let fixed_headers = 29L +
    205L +
    4L +
    5L +
    14L +
    1L +
    2L +
    6L +
    10L +
    7L +
    6L +
    2L
  let fixed_slots = 226L +
    1189L +
    11L +
    21L +
    44L +
    5L +
    9L +
    7L +
    14L +
    17L +
    8L
  // Original per-preflight setter/context and the same callback array's
  // retained spare backing. This reserves finite future construction, never
  // infers completed calls or reallocates a retired slot's authority.
  let count = max_items.to_int64()
  let value : @execution.PreparationRepresentationUnits = {
    record_headers: fixed_headers + 1L + 2L * count,
    reference_slots: fixed_slots + 6L * count,
    scalar_words: 113L + count,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  match @execution.preparation_representation_cost(value) {
    None => None
    Some(_) => Some(value)
  }
}

///|
/// Only the actual installed asynchronous Provider constructs this shell.
/// OriginalMock and legacy synchronous callers retain their old exact debit;
/// a Provider role is neither a caller-authored mode nor egress authority.
pub fn installed_node_model_caller_control_inventory(
  provider : @model.ModelProvider,
  max_items : Int,
) -> @execution.PreparationRepresentationUnits? {
  match provider.invocation {
    AsynchronousPhysical =>
      installed_node_model_async_control_inventory(max_items)
    SynchronousFixture(_) | OriginalMock(_) => None
  }
}
