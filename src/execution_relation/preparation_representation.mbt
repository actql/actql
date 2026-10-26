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
  if total < 0L ||
    count < 0L ||
    price <= 0L ||
    count > (9223372036854775807L - total) / price {
    None
  } else {
    Some(total + count * price)
  }
}
