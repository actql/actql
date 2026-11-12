///|
// Fixed roles in the existing READ caller, not a second ledger or a CID cache:
// service entry/index/manifest/retention/extension; delivery entry; selected
// entry/binding; temporary metadata inventory; schema wire/field holding;
// one holding record and the selected extension record. No role deduplicates
// another live body merely because their CIDs or values compare equal.
priv struct ClientRequestResultMetadataBudget {
  slots : Array[Int64]
  mut active : Bool
  mut before_retention : Int64
  mut before_execution : Int64
  mut before_held : Int64
  mut peak : Int64
}

///|
fn[I] result_read_metadata_active(owner : ClientRequestPreparation[I]) -> Bool {
  owner.result_read_metadata is Some(value) && value.active
}

///|
fn result_read_metadata_held(
  value : ClientRequestResultMetadataBudget,
) -> Int64 {
  let mut held = 0L
  for cost in value.slots {
    held += cost
  }
  held
}

///|
// The pre-read bound is temporary constructor demand. It is never recorded as
// the retained node count of a long string or accumulated across finished reads.
pub fn[I] reserve_request_result_read_metadata(
  owner : ClientRequestPreparation[I],
  input : I,
  bytes : Int,
) -> Result[Unit, ClientRequestPreparationIssue] {
  guard owner.phase == Open || owner.phase == ResultRead else {
    return Err(WrongPhase)
  }
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  if bytes < 0 {
    return Err(Policy)
  }
  let peak = match
    result_read_data_cost(
      bytes.to_int64(),
      6L * bytes.to_int64(),
      2L * bytes.to_int64(),
    ) {
    Some(value) => value
    None => return Err(Policy)
  }
  let old = match
    @resources.preparation_capacity_working_extents(owner.capacity, input) {
    Ok(value) => value
    Err(issue) => return Err(Capacity(issue))
  }
  let value = match owner.result_read_metadata {
    Some(value) => value
    None => {
      let value = {
        slots: Array::make(12, 0L),
        active: false,
        before_retention: 0L,
        before_execution: 0L,
        before_held: 0L,
        peak: 0L,
      }
      owner.result_read_metadata = Some(value)
      value
    }
  }
  let phase = owner.phase
  owner.phase = Selecting
  let result = @resources.reserve_working_preparation_phase(
    owner.capacity,
    input,
    old.0 + peak,
    old.1 + peak,
  )
  owner.phase = phase
  match result {
    Err(issue) => Err(Capacity(issue))
    Ok(_) => {
      if !value.active {
        value.before_retention = old.0
        value.before_execution = old.1
        value.before_held = result_read_metadata_held(value)
        value.peak = 0L
      }
      value.peak += peak
      value.active = true
      Ok(())
    }
  }
}

///|
fn[I] set_request_result_metadata_slot(
  owner : ClientRequestPreparation[I],
  input : I,
  slot : Int,
  cost : Int64,
) -> Result[Unit, ClientRequestPreparationIssue] {
  guard (owner.phase == Open || owner.phase == ResultRead) &&
    owner.result_read_metadata is Some(value) else {
    return Err(WrongPhase)
  }
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  if slot < 0 || slot >= value.slots.length() || cost < 0L {
    return Err(Policy)
  }
  let delta = cost - value.slots[slot]
  if !value.active && delta > 0L {
    return Err(WrongPhase)
  }
  if value.active {
    if result_read_metadata_held(value) + delta - value.before_held > value.peak {
      return Err(Policy)
    }
  } else {
    let old = match
      @resources.preparation_capacity_working_extents(owner.capacity, input) {
      Ok(value) => value
      Err(issue) => return Err(Capacity(issue))
    }
    let phase = owner.phase
    owner.phase = Selecting
    let result = @resources.reconcile_working_preparation_phase(
      owner.capacity,
      input,
      old.0 + delta,
      old.1 + delta,
    )
    owner.phase = phase
    if result is Err(issue) {
      return Err(Capacity(issue))
    }
  }
  value.slots[slot] = cost
  if owner.result_read is Some(read) {
    read.base_retention += delta
    read.base_execution += delta
  }
  Ok(())
}

///|
/// This observes the SAME admitted tree and cached encoder usage. No wire is
/// reissued, parsed or admitted to price a retained role. Mode 0 retains only
/// the parsed JS body; 1 the opaque contract; 2 both actual representations.
pub fn[I] retain_request_result_metadata_contract(
  owner : ClientRequestPreparation[I],
  input : I,
  slot : Int,
  contract : @publication.PublicationContract,
  mode : Int,
) -> Result[Unit, ClientRequestPreparationIssue] {
  if mode < 0 || mode > 2 {
    return Err(Policy)
  }
  guard @publication.publication_contract_wire_usage(contract)
    is Some((bytes, nodes, depth)) else {
    return Err(Policy)
  }
  let extent = match
    @publication.publication_contract_representation_extent(
      contract,
      nodes,
      depth,
      Int64::min(2147483647L, 4L * bytes.to_int64() + 1024L).to_int(),
    ) {
    Ok(value) => value
    Err(_) => return Err(Policy)
  }
  let tree = extent.canonical
  let canonical = match
    @execution.preparation_representation_cost({
      record_headers: extent.contract_records +
      extent.contract_strings +
      3L * tree.nodes +
      tree.strings +
      tree.arrays +
      tree.objects +
      2L * tree.object_backing_slots,
      reference_slots: 8L * extent.contract_records +
      extent.contract_strings +
      2L * tree.nodes +
      tree.array_backing_slots +
      3L * tree.object_backing_slots,
      scalar_words: 4L * extent.contract_records + 2L * tree.nodes,
      owned_utf16_units: extent.contract_text_utf16_units +
      tree.text_utf16_units,
      owned_wire_bytes: 0L,
    }) {
    Some(value) => value
    None => return Err(Policy)
  }
  let parsed = match
    result_read_data_cost(tree.nodes, tree.text_utf16_units, 0L) {
    Some(value) => value
    None => return Err(Policy)
  }
  set_request_result_metadata_slot(
    owner,
    input,
    slot,
    if mode == 0 {
      parsed
    } else if mode == 1 {
      canonical
    } else {
      canonical + parsed
    },
  )
}

///|
/// Fixed closed-schema producer observations, including the schema wire and
/// field-name holding. DATA cannot supply a different Request or reservation.
pub fn[I] retain_request_result_metadata_data(
  owner : ClientRequestPreparation[I],
  input : I,
  slot : Int,
  nodes : Int,
  text_units : Int,
) -> Result[Unit, ClientRequestPreparationIssue] {
  if nodes < 0 || text_units < 0 {
    return Err(Policy)
  }
  let cost = match
    result_read_data_cost(nodes.to_int64(), text_units.to_int64(), 0L) {
    Some(value) => value
    None => return Err(Policy)
  }
  set_request_result_metadata_slot(owner, input, slot, cost)
}

///|
pub fn[I] release_request_result_metadata(
  owner : ClientRequestPreparation[I],
  input : I,
  slot : Int,
) -> Result[Unit, ClientRequestPreparationIssue] {
  set_request_result_metadata_slot(owner, input, slot, 0L)
}

///|
/// Only the original producer calls this after its decoder/FD scratch ended.
/// A pending failure skips it and keeps the peak until original cleanup ACK.
pub fn[I] finish_request_result_metadata(
  owner : ClientRequestPreparation[I],
  input : I,
) -> Result[Unit, ClientRequestPreparationIssue] {
  guard (owner.phase == Open || owner.phase == ResultRead) &&
    owner.result_read_metadata is Some(value) &&
    value.active else {
    return Err(WrongPhase)
  }
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  let delta = result_read_metadata_held(value) - value.before_held
  let phase = owner.phase
  owner.phase = Selecting
  let result = @resources.reconcile_working_preparation_phase(
    owner.capacity,
    input,
    value.before_retention + delta,
    value.before_execution + delta,
  )
  owner.phase = phase
  match result {
    Err(issue) => Err(Capacity(issue))
    Ok(_) => {
      value.active = false
      value.peak = 0L
      Ok(())
    }
  }
}
