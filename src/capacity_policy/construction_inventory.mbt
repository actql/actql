///|
/// Fixed policy-schema constructor dependency. Source/indexed admission and
/// writer/hash scratch are separate phases, never a zero-cost implication of
/// these retained facts. This inventory uses the selected logical record model,
/// not a backend allocator or process-memory claim.
pub(all) struct PolicyConstructionInventory {
  record_headers : Int64
  reference_slots : Int64
  scalar_words : Int64
  owned_utf16_units : Int64
  source_wire_bytes_upper : Int
  source_nodes_upper : Int
  source_fields_upper : Int
  source_quoted_tokens_upper : Int
  source_text_utf16_upper : Int
  source_longest_quoted_utf16_upper : Int
  source_longest_atom_utf16_upper : Int
  source_depth_upper : Int
  map_entries_upper : Int
  map_backing_slots_upper : Int
} derive(Eq, Debug)

///|
/// Quote before serializing or readmitting the installed scalar-only policy.
/// Unsupported future schema layouts fail closed until their constructor bound
/// is updated. No authored policy values or newly constructed output are read.
pub fn policy_construction_inventory() -> PolicyConstructionInventory? {
  if fields.length() != 17 || optional_fields.length() != 9 {
    return None
  }
  let mut key_units = 7 // version
  for field in fields {
    if field.length() > 33 {
      return None
    }
    key_units += field.length()
  }
  for field in optional_fields {
    if field.length() > 33 {
      return None
    }
    key_units += field.length()
  }
  if key_units > 645 {
    return None
  }
  Some({
    // Policy, CID String, Map, fixed backing =4; Entry26; Some52.
    // Capacity's outer environment/policy join is the caller's separate owner.
    record_headers: 82L,
    // Policy2 + Map2 + Entry52 + Some52 + occupied backing26.
    reference_slots: 134L,
    // Map5 + Entry104 + Some52 + empty bucket tags6.
    scalar_words: 167L,
    owned_utf16_units: 71L,
    // 26 positive finite number spellings <=25 bytes;27 keys+version value,
    // commas/colons/quotes/braces included. All names/version are fixed ASCII.
    source_wire_bytes_upper: 1436,
    source_nodes_upper: 28,
    source_fields_upper: 27,
    source_quoted_tokens_upper: 28,
    source_text_utf16_upper: 675,
    source_longest_quoted_utf16_upper: 33,
    source_longest_atom_utf16_upper: 25,
    source_depth_upper: 1,
    map_entries_upper: 26,
    // Map starts at8, grows by2 at13/16 occupancy.17..26 entries use32.
    map_backing_slots_upper: 32,
  })
}
