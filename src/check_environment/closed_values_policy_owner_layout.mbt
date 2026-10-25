///|
/// Policy constructor owners for the original-only ClosedValues preparation.
/// Source/indexed parser trees and encode/hash writers are separate dependencies.
/// The installed Environment, its Strings and keys remain borrowed. This is a
/// conservative simultaneous logical-owner quote, not an allocator measurement.
pub(all) struct ClosedValuesPolicyOwnerLayout {
  record_headers : Int64
  reference_slots : Int64
  scalar_words : Int64
  owned_utf16_units : Int64
  owned_wire_bytes : Int64
} derive(Eq, Debug)

///|
/// Map[String, scalar] coexistence including one old backing at growth. Each
/// Entry has two references/four words. Four Some carriers per entry bound the
/// old/new bucket and linked-list carriers while a rehash is in progress.
/// Empty bucket storage is conservatively counted in addition to occupied
/// references; reconciliation may narrow this reservation, not charge it twice.
fn closed_values_policy_map_layout(n : Int64) -> (Int64, Int64, Int64) {
  let mut capacity = 8L
  while n > capacity * 13L / 16L {
    capacity *= 2L
  }
  (3L + 5L * n, 2L + 8L * n, 5L + 8L * n + capacity + capacity / 2L)
}

///|
/// P is read in O(1) from the exact original installed host-policy Object.
/// The admitted capacity schema has17 required plus9 optional scalar ceilings;
/// TextTime has5 scalar ceilings; LookupExecution has6. Missing optional policy
/// components use less. No component may add arbitrary nested data to this
/// quote: its existing closed canonical reader remains authoritative.
pub fn closed_values_policy_owner_layout(
  original_policy_fields : Int,
) -> ClosedValuesPolicyOwnerLayout? {
  if original_policy_fields < 0 {
    return None
  }
  let (ph, pr, pw) = closed_values_policy_map_layout(
    original_policy_fields.to_int64(),
  )
  let (ch, cr, cw) = closed_values_policy_map_layout(27L)
  let (th, tr, tw) = closed_values_policy_map_layout(6L)
  let lookup_fields = original_policy_fields.to_int64() + 7L
  Some({
    // Capacity+Policy83/136/169; TextTime+Policy+Some21/32/41;
    // LookupExecution+Policy+Some+ceilings+CID+retained Cursor7/9/12.
    // Two installed-policy ObjectViews; closed-key checks at most four Maps
    // per component (three validation indexes plus returned ObjectView map).
    // Eight name/key Arrays with old backings;66 key/value tuple records;
    // 2 returned ObjectViews; at most3N+3 temporary decoder Cursor carriers
    // for each closed scalar component (27+6), conservatively simultaneous.
    // Each decoder packet includes Cursor+field tuple/lookup Some carriers
    // (3 headers/5 references/3 words). Lookup scans P+7 fields separately.
    // Reader limit/budget records: five3-word limits +lookup budget/selection.
    record_headers: 83L +
    21L +
    7L +
    2L * (ph + 1L) +
    4L * (ch + th) +
    24L +
    66L +
    2L +
    315L +
    3L * lookup_fields +
    7L,
    reference_slots: 136L +
    32L +
    9L +
    2L * (pr + 2L) +
    4L * (cr + tr) +
    173L +
    132L +
    4L +
    525L +
    5L * lookup_fields +
    1L,
    scalar_words: 169L +
    41L +
    12L +
    2L * pw +
    4L * (cw + tw) +
    16L +
    315L +
    3L * lookup_fields +
    19L,
    // Retained CIDs3*71; during each policy admission expected CID,
    // computed CID and canonical digest/CID may coexist. The returned CID is
    // already retained above; reserve two further71 and one64 per component.
    // Material writer outputs: capacity1436 and TextTime279, plus UTF8 Bytes.
    // Writer's builder/hash buffers are NOT included here.
    owned_utf16_units: 3L * 71L + 2L * (2L * 71L + 64L) + 1436L + 279L,
    owned_wire_bytes: 1436L + 279L,
  })
}
