///|
/// Exact ordinary program-intent wrapper over the same proved ASCII object.
/// No stopBefore/readOnly/parameters or string-input route is inferred here.
/// Counts are constructor inputs to the original phase owner, never a grant.
// `_observed_*` fields retain exact bound observations for white-box tests;
// production consumes the admitted totals, not these diagnostic projections.
priv struct ClosedValuesIntentInventories {
  retained : @execution.PreparationRepresentationUnits
  js_temporary : @execution.PreparationRepresentationUnits
  core_temporary : @execution.PreparationRepresentationUnits
  shared_temporary : @execution.PreparationRepresentationUnits
  _observed_wire_facts : ClosedValuesLexicalFacts
}

///|
fn closed_values_intent_source_facts(
  input : ClientClosedValuesInputEnvelope,
) -> ClosedValuesLexicalFacts? {
  if input.input_bytes_upper < 0 ||
    input.input_bytes_upper > 2147483602 ||
    input.node_upper < 1 ||
    input.node_upper > 2147483639 ||
    input.objects < 1 ||
    input.objects > 2147483646 ||
    input.arrays < 0 ||
    input.fields_upper < 0 ||
    input.fields_upper > 2147483644 ||
    input.quoted_tokens < 0 ||
    input.quoted_tokens > 2147483643 ||
    input.quoted_utf16_units < 0 ||
    input.quoted_utf16_units > 2147483621 ||
    input.depth_upper < 1 ||
    input.depth_upper > 2147483645 ||
    input.fields < 1 ||
    input.rows < 0 {
    return None
  }
  // {"input":INPUT,"kind":"program","parameters":null}:45 extra ASCII
  // bytes; root/kind/null3 actual nodes. The lexical upper additionally
  // counts the three new key tokens:6. Four quoted tokens own26 units.
  Some({
    input_bytes: input.input_bytes_upper + 45,
    node_upper: input.node_upper + 6,
    objects: input.objects + 1,
    arrays: input.arrays,
    fields_upper: input.fields_upper + 3,
    quoted_tokens: input.quoted_tokens + 4,
    quoted_utf16_units: input.quoted_utf16_units + 26,
    longest_quoted_utf16: Int::max(10, input.longest_quoted_utf16),
    longest_atom_utf16: Int::max(4, input.longest_atom_utf16),
    depth_upper: input.depth_upper + 1,
  })
}

///|
/// Scale only logical owner counts, with the same checked arithmetic as the
/// tariff; this returns representation data, never another grant or byte pool.
fn closed_values_intent_scale_units(
  original : @execution.PreparationRepresentationUnits,
  count : Int64,
) -> @execution.PreparationRepresentationUnits? {
  if count < 1L {
    return None
  }
  guard @execution.checked_preparation_add_product(
      0L,
      original.record_headers,
      count,
    )
    is Some(h) &&
    @execution.checked_preparation_add_product(
      0L,
      original.reference_slots,
      count,
    )
    is Some(r) &&
    @execution.checked_preparation_add_product(0L, original.scalar_words, count)
    is Some(w) &&
    @execution.checked_preparation_add_product(
      0L,
      original.owned_utf16_units,
      count,
    )
    is Some(t) &&
    @execution.checked_preparation_add_product(
      0L,
      original.owned_wire_bytes,
      count,
    )
    is Some(b) else {
    return None
  }
  Some({
    record_headers: h,
    reference_slots: r,
    scalar_words: w,
    owned_utf16_units: t,
    owned_wire_bytes: b,
  })
}

///|
/// Only the independently admitted original numeric ClosedValues shape may
/// consume this inventory. The general canonicalizer remains authoritative.
fn closed_values_intent_inventories(
  input : ClientClosedValuesInputEnvelope,
) -> ClosedValuesIntentInventories? {
  guard closed_values_intent_source_facts(input) is Some(facts) else {
    return None
  }
  let n = facts.node_upper.to_int64()
  let f = facts.fields_upper.to_int64()
  let o = facts.objects.to_int64()
  let a = facts.arrays.to_int64()
  let c = o + a
  let e = n - 1L
  let d = facts.depth_upper.to_int64() + 1L
  let b = facts.input_bytes.to_int64()
  // Final ClientSubmittedIntent (wire,CID,two flags), wire String and CID.
  // The SDK input object and original document remain independently owned.
  let retained : @execution.PreparationRepresentationUnits = {
    record_headers: 3L,
    reference_slots: 2L,
    scalar_words: 2L,
    owned_utf16_units: b + 71L,
    owned_wire_bytes: 0L,
  }
  let source = closed_values_source_inventories(facts)
  // from_source(data_keys=true) borrows validated ASCII strings: one canonical
  // variant/node; FrozenArray+array wrapper/backing/container; field tuples.
  let canonical : @execution.PreparationRepresentationUnits = {
    record_headers: n + 3L * c + f,
    reference_slots: n + 2L * c + e + 2L * f,
    scalar_words: n + 2L * c,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // canonicalJson/from_source return only Strings/CanonicalValues. A completed
  // row cannot retain its temporary key Maps, entry arrays, Sets or callbacks.
  // Only the active ancestor chain owns these containers. On the original
  // guarded shape every object has <=max(field_count,4) keys, including the
  // intent wrapper and all fixed Program/Stage/Result/contract envelopes.
  let k = Int::max(input.fields, 4)
  guard closed_values_map_constructor_layout(k) is Some(map) else {
    return None
  }
  // The generic map family prices both occupied/bucket references; additionally
  // count old/new empty bucket scalar tags, rather than hiding them as refs.
  let bucket_slots = map.reference_slots - 2L - 6L * k.to_int64()
  let map_with_tags = { ..map, scalar_words: map.scalar_words + bucket_slots, }
  guard closed_values_intent_scale_units(map_with_tags, d) is Some(maps) else {
    return None
  }
  // Per live object: entries/filter/normalized/key/render arrays and pair arrays.
  // Per live array: its mapped String slots remain until join. The largest
  // array is rows or selected fields; at most d such ancestor arrays coexist.
  let width = Int::max(Int::max(input.rows, input.fields), 4).to_int64()
  let js_array_frame : @execution.PreparationRepresentationUnits = {
    record_headers: 12L + 4L * k.to_int64(),
    reference_slots: 54L + 16L * k.to_int64() + 2L * width,
    scalar_words: 12L + 4L * k.to_int64(),
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  guard closed_values_intent_scale_units(js_array_frame, d) is Some(js_arrays) else {
    return None
  }
  // Five object callbacks, one array callback, one {dataKeys} and recursive
  // control per live depth. Original input/envelope references are borrowed.
  let js_controls : @execution.PreparationRepresentationUnits = {
    record_headers: 8L * d + 1L,
    reference_slots: 12L * d + 3L,
    scalar_words: 5L * d,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // Scalar JSON strings, rendered key:value fragments, join strings and final
  // container strings: each emitted token appears in <=depth+1 ancestors and
  // <=four such owned renderings. This prices actual subtree string overlap,
  // not four copies of the mutable input tree. Original keys are borrowed.
  // Exclude the final returned wire here: its one owner is shared_temporary.
  // Retain the old cumulative String-header upper; no early string GC assumed.
  guard @execution.checked_preparation_add_product(0L, b, 4L * d - 1L)
    is Some(js_text) else {
    return None
  }
  let rendered : @execution.PreparationRepresentationUnits = {
    record_headers: 4L * n - 1L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: js_text,
    owned_wire_bytes: 0L,
  }
  let sort = closed_values_sort_scratch_layout(Int::max(input.fields, 4)).unwrap()
  // Canonical from_source recursive frames, map callback closures, InputBudget;
  // canonical emit_value owns only parent cursors, not one copied subtree/node.
  let traversal : @execution.PreparationRepresentationUnits = {
    record_headers: 8L * d + 9L,
    reference_slots: 17L * d + 15L,
    scalar_words: 10L * d + 14L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // Both writers use the same source-derived frame/map inventory. Using a
  // hash inventory for the material writer is conservative for control/SHA
  // state; its distinct TextOutput/StringBuilder and old/new text are below.
  // Hash envelope adds {intent:VALUE,version:"actql-submitted-intent/0.1"}:
  // two nodes and one container depth beyond the intent object.
  guard @encode.hash_writer_construction_inventory(
      facts.node_upper + 2,
      facts.depth_upper + 1,
    )
    is Some(hash) else {
    return None
  }
  let writer : @execution.PreparationRepresentationUnits = {
    record_headers: hash.record_headers,
    reference_slots: hash.reference_slots,
    scalar_words: hash.scalar_words,
    owned_utf16_units: hash.owned_utf16_units,
    owned_wire_bytes: hash.owned_wire_bytes,
  }
  let text_output : @execution.PreparationRepresentationUnits = {
    record_headers: 5L,
    reference_slots: 2L,
    scalar_words: 2L,
    owned_utf16_units: 3L * b,
    owned_wire_bytes: 0L,
  }
  // Only this final JS canonical wire crosses the synchronous phase boundary.
  let shared_temporary : @execution.PreparationRepresentationUnits = {
    record_headers: 1L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: b,
    owned_wire_bytes: 0L,
  }
  // Core owns UTF8 bytes, decoded ASCII document and CID concatenation scratch.
  // Its source AST remains live through the entire original Core call.
  let wires : @execution.PreparationRepresentationUnits = {
    record_headers: 4L,
    reference_slots: 0L,
    scalar_words: 2L,
    owned_utf16_units: b + 64L + 71L,
    owned_wire_bytes: b,
  }
  // Quote construction: at most24 unit records(120words), facts(11words),
  // source-inventory record(9refs), output(3refs), eight Option/Result
  // carriers, two API tuples,18-slot sum-array/backing and active arithmetic
  // returns. The48H/72R/152W packet dominates those named objects.
  // Source parsing error/path carriers are already in its original inventory.
  let controls : @execution.PreparationRepresentationUnits = {
    record_headers: 48L,
    reference_slots: 72L,
    scalar_words: 152L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // JS canonicalization fully returns before prepare_client_submitted_intent.
  // Caller prices shared+JS and shared+Core using the SAME tariff, then reserves
  // their scalar maximum before either phase. Never componentwise-max units,
  // which would mix one phase's String peak with another's container peak.
  guard closed_values_sum_layouts([
      maps, js_arrays, js_controls, rendered, sort, controls,
    ])
    is Some(js_temporary) &&
    closed_values_sum_layouts([
      source.source_retained,
      source.source_growth_peak,
      source.key_admission_peak,
      source.parser_ancestry_peak,
      source.parser_controls_peak,
      canonical,
      maps,
      sort,
      traversal,
      writer,
      writer,
      text_output,
      wires,
      controls,
    ])
    is Some(core_temporary) else {
    return None
  }
  Some({
    retained,
    js_temporary,
    core_temporary,
    shared_temporary,
    _observed_wire_facts: facts,
  })
}
