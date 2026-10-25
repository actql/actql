///|
/// Node's original own-data scan supplies these input bounds through the fixed
/// adapter. They are not lexical eligibility, a resource quota or a semantic
/// admission; the existing JSON parser and ASCII proof still run afterwards.
pub(all) struct ClientClosedValuesInputEnvelope {
  input_bytes_upper : Int
  node_upper : Int
  objects : Int
  arrays : Int
  fields_upper : Int
  quoted_tokens : Int
  quoted_utf16_units : Int
  longest_quoted_utf16 : Int
  longest_atom_utf16 : Int
  depth_upper : Int
  fields : Int
  rows : Int
}

///|
priv struct ClosedValuesSnapshotInventories {
  retained_host_share : PreparationRepresentationUnits
  temporary : PreparationRepresentationUnits
  document : PreparationRepresentationUnits
}

///|
/// JS logical owned object/property/array/String layout. Native JSON intrinsic
/// implementation, GC and enumeration backing stay with the installed engine;
/// no heap/RSS claim is made. Property keys and copied String values are counted
/// independently, without assuming interning. The input object itself is an
/// existing caller-owned borrow; only the SDK's actual cloned tree is new.
fn closed_values_snapshot_inventories(
  facts : ClientClosedValuesInputEnvelope,
  consent_refs : Int,
) -> ClosedValuesSnapshotInventories? {
  if facts.fields < 1 ||
    facts.rows < 0 ||
    consent_refs < 0 ||
    facts.input_bytes_upper < 1 ||
    facts.node_upper < 1 ||
    facts.objects < 0 ||
    facts.arrays < 0 ||
    facts.fields_upper < 0 ||
    facts.quoted_tokens < 0 ||
    facts.quoted_utf16_units < 0 ||
    facts.longest_quoted_utf16 < 0 ||
    facts.longest_atom_utf16 < 0 ||
    facts.depth_upper < 0 {
    return None
  }
  let o = facts.objects.to_int64()
  let a = facts.arrays.to_int64()
  let f = facts.fields_upper.to_int64()
  let q = facts.quoted_tokens.to_int64()
  let u = facts.quoted_utf16_units.to_int64()
  let b = facts.input_bytes_upper.to_int64()
  // Cloned Program object/property/value slots. Every property owns one key
  // reference and one tagged JS value word (the tariff prices both at8). Do
  // conservatively also include scalar property slots for component-wise reconciliation; this deliberately overquotes reference-valued properties.
  // Four arrays are stages/steps/rows/selected fields, so total occupied array
  // slots are exactly R+F+2, NOT the whole indexed tree's node count. Arrays
  // use wrapper/backing, <=8+2*children slots and length/capacity words.
  let cloned_program : PreparationRepresentationUnits = {
    record_headers: o + 2L * a + q,
    reference_slots: 2L * f +
    9L * a +
    2L * (facts.rows.to_int64() + facts.fields.to_int64() + 2L),
    scalar_words: 2L * a + f,
    owned_utf16_units: u,
    owned_wire_bytes: 0L,
  }
  // Valid selected SDK epoch is a SIX-field object, not a String. Main clone
  // adds4objects/15fields/23quotedStrings/445UTF16/2numbers/1null. The separately
  // cloned newSubmission reference adds2objects/8fields/13Strings/336UTF16/2nums.
  let metadata_clones : PreparationRepresentationUnits = {
    record_headers: 4L + 23L + 2L + 13L,
    reference_slots: 2L * 15L + 2L * 8L,
    scalar_words: 23L,
    owned_utf16_units: 445L + 336L,
    owned_wire_bytes: 0L,
  }
  // Original ref/attempt wrappers, two UUID Strings, two default empty options,
  // spread options, body, context, lookup and shallow snapshot root. The last
  // root SHARES the cloned input: never charge a second Program tree for it.
  // Private caller-value publication receipt+body/snapshot binding:2h/2refs.
  let controls : PreparationRepresentationUnits = {
    record_headers: 2L + 2L + 2L + 1L + 1L + 1L + 1L + 1L + 2L + 9L,
    reference_slots: 4L + 1L + 5L + 4L + 2L + 8L + 2L + 16L,
    scalar_words: 0L,
    owned_utf16_units: 72L,
    owned_wire_bytes: 0L,
  }
  guard closed_values_sum_layouts([cloned_program, metadata_clones, controls])
    is Some(retained_host_share) else {
    return None
  }
  // Main JSON String <=program upper+2786; newSubmission ref source <=2092.
  // Both are conservatively summed although their constructor scopes differ.
  // Later program-only stringify is a separate named document owner below.
  let wire_strings : PreparationRepresentationUnits = {
    record_headers: 2L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: b + 2786L + 2092L,
    owned_wire_bytes: 0L,
  }
  // Two freeze traversals are sequential; sum their original ancestor arrays
  // conservatively. The second also walks original installed consentRefs C.
  // Nine recursive frames per traversal; fixed nonrecursive frames are not
  // charged. Each frame holds value, values-array and current child references.
  let first = facts.rows.to_int64() + facts.fields.to_int64() + 21L
  let second = Int64::max(
    facts.rows.to_int64() + facts.fields.to_int64() + 24L,
    13L + consent_refs.to_int64(),
  )
  let freeze_scratch : PreparationRepresentationUnits = {
    record_headers: 2L * 18L + 18L,
    reference_slots: 18L + first + second + 3L * 18L,
    scalar_words: 2L * 18L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  guard closed_values_sum_layouts([wire_strings, freeze_scratch])
    is Some(temporary) else {
    return None
  }
  let document : PreparationRepresentationUnits = {
    record_headers: 1L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: b,
    owned_wire_bytes: 0L,
  }
  // Caller-facing SDK value custody transfers explicitly. These units remain
  // on the Host reservation while ANY Host alias survives; transfer is not a
  // GC/free assertion and creates no permanent replacement SDK resource pool.
  Some({ retained_host_share, temporary, document, })
}
