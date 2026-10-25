///|
/// Logical preparation representation units, not engine heap measurements.
/// Each field counts independently owned storage. Borrowed strings/containers
/// contribute references here and their backing only at their nominal owner.
/// Array slots include spare capacity; Map entries and their backing are
/// expanded into headers/slots by the constructor-specific inventory.
/// Payload-bearing variants (including Some) use one header, one scalar tag,
/// and their payload slots. Zero-payload variants are inline scalar tags, not
/// new records; shared canonical tags belong to the Host baseline. Algorithmic
/// recursion frames use their bounded live local/reference inventory. Opaque
/// engine stack and GC backing are outside this logical representation.
/// Fixed nonrecursive VM frames, for both ordinary Core and builtin helpers,
/// are the installed runtime baseline rather than request-owned records.
/// Allocated objects created by those calls remain charged, as do explicit
/// dynamic work containers and input-dependent recursion/sort frames.
struct PreparationRepresentationUnits {
  record_headers : Int64
  reference_slots : Int64
  scalar_words : Int64
  owned_utf16_units : Int64
  owned_wire_bytes : Int64
} derive(Eq)

///|
/// One internal accounting representation, version 1. A word is eight logical
/// bytes and a record header is two words. UTF16 and wire storage retain their
/// different units. These are selected ledger tariffs, not a V8/MoonBit object
/// layout claim or a bound on opaque GC/allocator metadata. They do not grant
/// any resource allowance: the original installed Ledger still admits totals.
priv struct PreparationRepresentationCostPolicy {
  record_header_bytes : Int64
  reference_slot_bytes : Int64
  scalar_word_bytes : Int64
  utf16_unit_bytes : Int64
  wire_byte_bytes : Int64
}

///|
let preparation_representation_cost_policy : PreparationRepresentationCostPolicy={
  record_header_bytes:16L,
  reference_slot_bytes:8L,
  scalar_word_bytes:8L,
  utf16_unit_bytes:2L,
  wire_byte_bytes:1L,
}

///|
/// Checked projection shared by preparation phase proofs and actual logical
/// inventory reconciliation. No separate quote/runtime coefficient table.
fn preparation_representation_cost(units : PreparationRepresentationUnits) -> Int64? {
  let policy=preparation_representation_cost_policy
  let mut total=0L
  guard preparation_cost_add(total,units.record_headers,policy.record_header_bytes) is Some(next) else {return None}
  total=next
  guard preparation_cost_add(total,units.reference_slots,policy.reference_slot_bytes) is Some(next) else {return None}
  total=next
  guard preparation_cost_add(total,units.scalar_words,policy.scalar_word_bytes) is Some(next) else {return None}
  total=next
  guard preparation_cost_add(total,units.owned_utf16_units,policy.utf16_unit_bytes) is Some(next) else {return None}
  total=next
  preparation_cost_add(total,units.owned_wire_bytes,policy.wire_byte_bytes)
}

///|
fn preparation_cost_add(total : Int64,count : Int64,price : Int64) -> Int64? {
  if count<0L || price<=0L || count>(9223372036854775807L-total)/price {None} else {Some(total+count*price)}
}

///|
/// Reconcile one typed owner family in one immutable phase snapshot. The
/// inventory itself is borrowed, not allocated here. Equal content is not
/// identity: distinct copied owners are charged separately. Repeated identity
/// with different extents is not a valid immutable snapshot and refuses.
fn[T] preparation_owned_representation_cost(
  owners : Array[(T,PreparationRepresentationUnits)],max_work : Int,
) -> Int64? {
  if max_work<0 {return None}
  let mut remaining=max_work
  let mut total=0L
  for index in 0..<owners.length() {
    if remaining==0 {return None}
    remaining-=1
    let (owner,units)=owners[index]
    let mut duplicate=false
    for earlier in 0..<index {
      if remaining==0 {return None}
      remaining-=1
      let (previous,extent)=owners[earlier]
      if physical_equal(owner,previous) {
        if units!=extent {return None}
        duplicate=true
        break
      }
    }
    if !duplicate {
      guard preparation_representation_cost(units) is Some(cost) else {return None}
      if cost>9223372036854775807L-total {return None}
      total+=cost
    }
  }
  Some(total)
}

///|
/// Fixed owned control family of the ordinary Node structural scanner. Its
/// source-owned inventory is independently checked in the adapter suite; byte
/// pricing remains exclusively this Common tariff, not a Node-issued grant.
fn preparation_node_own_data_scan_cost() -> Int64? {
  preparation_representation_cost({record_headers:4L,reference_slots:5L,
    scalar_words:31L,owned_utf16_units:0L,owned_wire_bytes:0L})
}

///|
/// Valid narrow input traversal count from the original header's F/R facts.
/// UTF16 lengths are inspected in O(1), not characters, in this Node phase.
/// JSON byte bounds and the later Common lexical scan have distinct units.
fn preparation_node_own_data_scan_work(fields : Int,rows : Int) -> Int? {
  if fields<1 || rows<0 {return None}
  let f=fields.to_int64()
  let r=rows.to_int64()
  let maximum=2147483647L
  if f>(maximum-140L)/(f+19L) {return None}
  let base=140L+f*f+19L*f
  let per_row=4L+6L*f
  if r>(maximum-base)/per_row {return None}
  Some((base+r*per_row).to_int())
}

///|
/// A nominal input-bound header survives into the full scan: one record with
/// input identity/F/R facts and private state. It is additional to the scanner
/// owned control family, not hidden in its 344-byte component quote.
fn preparation_node_own_data_header_cost() -> Int64? {
  preparation_representation_cost({record_headers:1L,reference_slots:3L,
    scalar_words:3L,owned_utf16_units:0L,owned_wire_bytes:0L})
}

///|
/// Domain callers supply storage/slot inventories, never another tariff or
/// an already guessed budget. Workspace is simultaneous with retained state;
/// ExecutionCapacity therefore includes both components in its execution peak.
struct PreparationExecutionInventory {
  retained : PreparationRepresentationUnits
  workspace : PreparationRepresentationUnits
  retained_nodes : Int64
  workspace_nodes : Int64
  retained_bytes : Int64
  workspace_bytes : Int64
}

///|
fn preparation_execution_capacity(
  inventory : PreparationExecutionInventory,
) -> @execution.ExecutionCapacity? {
  let node = @execution.execution_capacity_node_bytes()
  guard preparation_representation_cost(inventory.retained) is Some(retained) else {
    return None
  }
  guard preparation_cost_add(retained, inventory.retained_nodes, node) is Some(retained) else {
    return None
  }
  guard preparation_cost_add(retained, inventory.retained_bytes, 1L) is Some(retained) else {
    return None
  }
  guard preparation_representation_cost(inventory.workspace) is Some(workspace) else {
    return None
  }
  guard preparation_cost_add(workspace, inventory.workspace_nodes, node) is Some(workspace) else {
    return None
  }
  guard preparation_cost_add(workspace, inventory.workspace_bytes, 1L) is Some(workspace) else {
    return None
  }
  guard preparation_cost_add(retained, workspace, 1L) is Some(execution) else {
    return None
  }
  @execution.execution_capacity(retained, execution)
}
