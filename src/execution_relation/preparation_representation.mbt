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
pub(all) struct PreparationRepresentationUnits {
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
let preparation_representation_cost_policy : PreparationRepresentationCostPolicy = {
  record_header_bytes: 16L,
  reference_slot_bytes: 8L,
  scalar_word_bytes: 8L,
  utf16_unit_bytes: 2L,
  wire_byte_bytes: 1L,
}

///|
/// Checked projection shared by preparation phase proofs and actual logical
/// inventory reconciliation. No separate quote/runtime coefficient table.
pub fn preparation_representation_cost(
  units : PreparationRepresentationUnits,
) -> Int64? {
  let policy = preparation_representation_cost_policy
  let mut total = 0L
  guard checked_preparation_add_product(
      total,
      units.record_headers,
      policy.record_header_bytes,
    )
    is Some(next) else {
    return None
  }
  total = next
  guard checked_preparation_add_product(
      total,
      units.reference_slots,
      policy.reference_slot_bytes,
    )
    is Some(next) else {
    return None
  }
  total = next
  guard checked_preparation_add_product(
      total,
      units.scalar_words,
      policy.scalar_word_bytes,
    )
    is Some(next) else {
    return None
  }
  total = next
  guard checked_preparation_add_product(
      total,
      units.owned_utf16_units,
      policy.utf16_unit_bytes,
    )
    is Some(next) else {
    return None
  }
  total = next
  checked_preparation_add_product(
    total,
    units.owned_wire_bytes,
    policy.wire_byte_bytes,
  )
}

///|
pub fn checked_preparation_add_product(
  total : Int64,
  count : Int64,
  price : Int64,
) -> Int64? {
  @preparation_counts.checked_nonnegative_add_product(total, count, price)
}

///|
/// Compose declared simultaneous inventories in the same representation units.
/// Domains own multiplicity, aliasing and lifetime facts; this common operation
/// rejects each negative extent, checked addition overflow and tariff overflow.
/// It neither deduplicates owners nor grants/reserves capacity. A caller may
/// reuse a phase peak only after the original owner confirms prior retirement.
pub fn compose_preparation_representation(
  values : Array[PreparationRepresentationUnits],
) -> PreparationRepresentationUnits? {
  let mut h = 0L
  let mut r = 0L
  let mut w = 0L
  let mut t = 0L
  let mut b = 0L
  for value in values {
    guard checked_preparation_add_product(h, value.record_headers, 1L)
      is Some(n) else {
      return None
    }
    h = n
    guard checked_preparation_add_product(r, value.reference_slots, 1L)
      is Some(n) else {
      return None
    }
    r = n
    guard checked_preparation_add_product(w, value.scalar_words, 1L) is Some(n) else {
      return None
    }
    w = n
    guard checked_preparation_add_product(t, value.owned_utf16_units, 1L)
      is Some(n) else {
      return None
    }
    t = n
    guard checked_preparation_add_product(b, value.owned_wire_bytes, 1L)
      is Some(n) else {
      return None
    }
    b = n
  }
  let result : PreparationRepresentationUnits = {
    record_headers: h,
    reference_slots: r,
    scalar_words: w,
    owned_utf16_units: t,
    owned_wire_bytes: b,
  }
  guard preparation_representation_cost(result) is Some(_) else { return None }
  Some(result)
}

///|
/// Domain callers supply storage/slot inventories, never another tariff or
/// an already guessed budget. Workspace is simultaneous with retained state;
/// ExecutionCapacity therefore includes both components in its execution peak.
pub(all) struct PreparationExecutionInventory {
  retained : PreparationRepresentationUnits
  workspace : PreparationRepresentationUnits
  retained_nodes : Int64
  workspace_nodes : Int64
  retained_bytes : Int64
  workspace_bytes : Int64
}

///|
pub fn preparation_execution_capacity(
  inventory : PreparationExecutionInventory,
) -> ExecutionCapacity? {
  guard preparation_representation_cost(inventory.retained) is Some(retained) &&
    preparation_representation_cost(inventory.workspace) is Some(workspace) else {
    return None
  }
  execution_capacity_inventory(
    [
      { unit: QuotedBytes, count: retained, copies: 1, },
      { unit: ValueNodeSlots, count: inventory.retained_nodes, copies: 1, },
      { unit: QuotedBytes, count: inventory.retained_bytes, copies: 1, },
    ],
    [
      { unit: QuotedBytes, count: workspace, copies: 1, },
      { unit: ValueNodeSlots, count: inventory.workspace_nodes, copies: 1, },
      { unit: QuotedBytes, count: inventory.workspace_bytes, copies: 1, },
    ],
    RetainedAlongsideExecution,
  )
}

///|
/// Existing logical Array representation, shared by constructor inventories.
/// The returned units include wrapper/backing growth but no element payload.
pub fn preparation_array_representation(
  count : Int64,
  items : Int64,
  growing : Bool,
) -> PreparationRepresentationUnits? {
  guard @preparation_counts.preparation_array_slots(count, items, growing)
    is Some((h, r, w)) else {
    return None
  }
  Some({
    record_headers: h,
    reference_slots: r,
    scalar_words: w,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
}
