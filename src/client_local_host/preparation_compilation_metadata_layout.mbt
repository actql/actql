///|
/// Finite metadata emitted by the one-Values/full-Result compilation recipe.
/// These are constructor facts, not an admission grant or a second compiler.
priv struct ClosedValuesCompilationMetadataLayout {
  retained : @execution.PreparationRepresentationUnits
  temporary : @execution.PreparationRepresentationUnits
  graph_extra : ClosedValuesLexicalFacts
  material_extra : ClosedValuesLexicalFacts
  plan_extra : ClosedValuesLexicalFacts
  max_wire_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_facts : Int
  max_witnesses : Int
}

///|
/// Complete emitted families: row/byte limit, binding, row/byte fact entry,
/// witness, checked row contract, Result plan, direct root, invocation bindings,
/// bound template, compiled plan, fact manifest, and three outer envelopes.
/// F is exact original field count; L bounds original identifier UTF16 length.
fn compilation_metadata_facts(
  kind : Int,
  fields : Int,
  name_units : Int,
) -> ClosedValuesLexicalFacts? {
  if fields < 1 || name_units < 0 {
    return None
  }
  let f = fields.to_int64()
  let l = name_units.to_int64()
  // All projected JSON extents cross Int APIs; reject before Int64 products.
  if l > (2147483647L - 2092L) / 4L ||
    f > (2147483647L - 418L - 3L * l) / (100L + 2L * l) {
    return None
  }
  // Tuple: values, objects, arrays, object fields, quoted tokens, quoted units,
  // container depth. Key spellings are counted from the actual emitters.
  let (n, o, a, k, q, u, d) : (Int64, Int64, Int64, Int64, Int64, Int64, Int) = match
    kind {
    // Context row template, with Unit subject<=92+2L and leaf witness's Unit
    // subject85 replacing checked-step:0 (14). Byte drops that leaf witness.
    0 => (40L, 7L, 3L, 35L, 62L, 1187L + 2L * l, 5)
    1 => (25L, 4L, 2L, 22L, 39L, 721L + 2L * l, 5)
    2 => (12L, 2L, 0L, 11L, 20L, 477L + 3L * l, 2)
    // {kind:"resolved_limit",value:<limit>} adds 2 nodes, 1 object,
    // two keys and one String (key/value text total23).
    3 => (42L, 8L, 3L, 37L, 65L, 1210L + 2L * l, 6)
    4 => (27L, 5L, 2L, 24L, 42L, 744L + 2L * l, 6)
    // Three pre-dedup scopes: leaf Values + row Host + byte Host. All are
    // dominated by the Unit leaf witness (15 nodes,466 quoted units).
    5 => (15L, 3L, 1L, 13L, 23L, 466L, 3)
    6 =>
      (
        5L + 3L * f,
        2L + f,
        0L,
        4L + 3L * f,
        5L + 4L * f,
        45L + f * (18L + l),
        3,
      )
    // Inherited direct root requires zero order terms; projection has F
    // {input,output,value_contract_cid} records. Row contract is distinct.
    7 =>
      (
        15L + 4L * f,
        3L + f,
        2L,
        14L + 3L * f,
        23L + 6L * f,
        418L + 3L * l + f * (100L + 2L * l),
        3,
      )
    8 => (6L, 2L, 0L, 5L, 9L, 38L + 3L * l, 2)
    9 => (4L, 2L, 0L, 3L, 5L, 138L, 2)
    10 => (11L, 1L, 1L, 10L, 19L, 751L, 2)
    11 => (10L, 1L, 0L, 9L, 18L, 631L, 1)
    // Manifest root+array+two entries+CID/version. No parse in its issuer.
    12 => (73L, 14L, 6L, 64L, 112L, 2092L + 4L * l, 8)
    // Material has a Program placeholder; retaining that extra scalar is
    // explicit one-node slack when composing the actual Program subtree.
    13 => (15L, 3L, 2L, 14L, 23L, 907L + l, 2)
    14 => (14L, 1L, 9L, 13L, 16L, 353L, 2)
    15 => (4L, 1L, 3L, 3L, 3L, 24L, 2)
    _ => return None
  }
  // Every non-string scalar is a finite Number or Bool. 25 bounds either;
  // six bytes per UTF16 unit handles escaping without assuming ASCII values.
  let atoms = n - o - a - (q - k)
  let bytes = 6L * u + 2L * q + 25L * atoms + k + (n - 1L) + 2L * (o + a)
  let longest = Int64::max(92L + 2L * l, 71L)
  if atoms < 0L ||
    n > 2147483647L ||
    k > 2147483647L ||
    q > 2147483647L ||
    u > 2147483647L ||
    bytes > 2147483647L ||
    longest > 2147483647L {
    return None
  }
  Some({
    input_bytes: bytes.to_int(),
    node_upper: n.to_int(),
    objects: o.to_int(),
    arrays: a.to_int(),
    fields_upper: k.to_int(),
    quoted_tokens: q.to_int(),
    quoted_utf16_units: u.to_int(),
    longest_quoted_utf16: longest.to_int(),
    longest_atom_utf16: 25,
    depth_upper: d,
  })
}

///|
fn compilation_metadata_sum_facts(
  values : Array[ClosedValuesLexicalFacts],
  depth : Int,
) -> ClosedValuesLexicalFacts? {
  let mut b = 0L
  let mut n = 0L
  let mut o = 0L
  let mut a = 0L
  let mut k = 0L
  let mut q = 0L
  let mut u = 0L
  let mut longest = 0
  for v in values {
    b += v.input_bytes.to_int64()
    n += v.node_upper.to_int64()
    o += v.objects.to_int64()
    a += v.arrays.to_int64()
    k += v.fields_upper.to_int64()
    q += v.quoted_tokens.to_int64()
    u += v.quoted_utf16_units.to_int64()
    longest = Int::max(longest, v.longest_quoted_utf16)
  }
  if b > 2147483647L ||
    n > 2147483647L ||
    k > 2147483647L ||
    q > 2147483647L ||
    u > 2147483647L {
    return None
  }
  Some({
    input_bytes: b.to_int(),
    node_upper: n.to_int(),
    objects: o.to_int(),
    arrays: a.to_int(),
    fields_upper: k.to_int(),
    quoted_tokens: q.to_int(),
    quoted_utf16_units: u.to_int(),
    longest_quoted_utf16: longest,
    longest_atom_utf16: 25,
    depth_upper: depth,
  })
}

///|
/// Metadata only: never price the authored row payload through this recipe.
/// Conservative complete-tree envelopes dominate body+identity-root sharing
/// for seals; this explicit small slack avoids assuming early collection.
fn closed_values_compilation_metadata_layout(
  fields : Int,
  name_units : Int,
) -> ClosedValuesCompilationMetadataLayout? {
  if fields < 1 || name_units < 0 {
    return None
  }
  let zero : @execution.PreparationRepresentationUnits = {
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  let mut retained = zero
  let mut temporary = zero
  let mut max_b = 0
  let mut max_n = 0
  let mut max_d = 0
  // Actual family multiplicities; sealed bodies and completed root copies are
  // both covered by full-tree envelopes (invocations2*2,template2,compiled2).
  // Row contract/Result plan are independently issued by root and material.
  for kind in 0..<13 {
    guard compilation_metadata_facts(kind, fields, name_units) is Some(facts) else {
      return None
    }
    let count = match kind {
      2 => 2
      5 => 3
      6 | 7 => 2
      9 => 4
      10 | 11 => 2
      _ => 1
    }
    let largest = if kind == 6 {
      Int::max(4, fields)
    } else {
      Int::min(facts.fields_upper, 14)
    }
    guard compilation_parse_layout(facts, largest) is Some(parsed) else {
      return None
    }
    // A parsed projection is deliberately retained even for the row/Result
    // identities which only keep wire/CID. It dominates those smaller records;
    // constructor carriers themselves are included in the named packet below.
    let wire : @execution.PreparationRepresentationUnits = {
      record_headers: 2L,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: facts.input_bytes.to_int64() + 71L,
      owned_wire_bytes: 0L,
    }
    // Every family has at most hash+material+measure. The common hash writer
    // dominates measuring-only controls; one text sink is separately priced.
    guard closed_values_writer_layout(
        facts.node_upper,
        facts.depth_upper,
        3,
        1,
        facts.input_bytes,
      )
      is Some(writers) else {
      return None
    }
    for _ in 0..<count {
      guard closed_values_sum_layouts([retained, parsed.value, wire]) is Some(r) &&
        closed_values_sum_layouts([temporary, parsed.temporary, writers])
        is Some(t) else {
        return None
      }
      retained = r
      temporary = t
    }
    max_b = Int::max(max_b, facts.input_bytes)
    max_n = Int::max(max_n, facts.node_upper)
    max_d = Int::max(max_d, facts.depth_upper)
  }
  let f = fields.to_int64()
  // Facts(3),witnesses(2),2 binding field records(10 each)+2 tuples(2),
  // two scope triples,2 row identities(4),2 Result identities(7),2F
  // projection records(2),direct root(6),encoded/finished manifest(2 each),
  // three RunEvidence(4),one PublicationContract(7),8 FieldRules(3)+spec(4).
  let records = closed_values_capacity_record_packet(
    28L + 2L * f,
    124L + 4L * f,
  )
  // Facts4 arrays with2 entries,witness2 with3,canonical4 with9 total,
  // manifestcopy1 with2,2 projection arrays F,names/CIDs2 with1,scope2 with2,
  // and two copied projection_names Arrays F from results.fields.
  let arrays = closed_values_program_arrays(19L, 31L + 4L * f, true)
  let maps = closed_values_program_maps(2L, 4L, true)
  // Number contract hashes in each of the two Result issuers. These do not
  // materialize a contract wire, but each produces a fresh CID String.
  if fields > 2147483647 / 2 {
    return None
  }
  guard closed_values_writer_layout(3, 1, 2 * fields, 0, 0)
    is Some(number_writers) else {
    return None
  }
  let cids : @execution.PreparationRepresentationUnits = {
    record_headers: 2L * f,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: 142L * f,
    owned_wire_bytes: 0L,
  }
  guard compilation_number_contract_emitter_layout() is Some(emitter) &&
    compilation_metadata_repeat_units(emitter, 4L + 2L * f)
    is Some(contract_emission) else {
    return None
  }
  // Six generated protocol validations (two invocation seals +template,
  // before/after): cursor,budget,<=5 live continuation variants,3 Some,
  // advance tuple and scalar-map carrier =12 records/<=40 fields. Empty
  // nested bindings has no uniqueness/alternatives or nonempty child array.
  let validation_records = closed_values_capacity_record_packet(
    6L * 12L,
    6L * 40L,
  )
  let validation_arrays = closed_values_program_arrays(6L, 6L * 4L, true)
  // CompiledPlan has no generated protocol root: two flat validate_contract
  // calls own allowed[10] + copied fields[<=9], Exact and lookup carriers.
  let flat_records = closed_values_capacity_record_packet(24L, 40L)
  let flat_arrays = closed_values_program_arrays(4L, 38L, true)
  // Binding subject replacements/concatenations (two issuances), fact-entry
  // prefix/intermediate Strings, manifest preimage/wire concatenation stages.
  // Manifest has2 preimage +4 completed-wire concatenations, a facts-array
  // wire and UTF8 encoder slice. Template/compiled body construction has
  //14/15 concatenations respectively. These are strings, not parser scopes.
  guard compilation_metadata_facts(12, fields, name_units) is Some(manifest) &&
    compilation_metadata_facts(10, fields, name_units) is Some(template) &&
    compilation_metadata_facts(11, fields, name_units) is Some(compiled) else {
    return None
  }
  let concatenations : @execution.PreparationRepresentationUnits = {
    record_headers: 61L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: 2L *
    (10L * name_units.to_int64() + 76L + 86L + 86L + 87L + 92L) +
    4L * max_b.to_int64() +
    8L * manifest.input_bytes.to_int64() +
    14L * template.input_bytes.to_int64() +
    15L * compiled.input_bytes.to_int64(),
    owned_wire_bytes: manifest.input_bytes.to_int64(),
  }
  // Small canonical scopes: facts emitted twice for manifest(4), nine Plan
  // metadata children across hash+text(18), four seals across hash+text(8).
  // Large graph/material/Plan subtree emitters are separate caller owners.
  guard compilation_canonical_emitter_layout(8) is Some(canonical_emitter) &&
    compilation_metadata_repeat_units(canonical_emitter, 30L)
    is Some(canonical_scopes) &&
    compilation_small_witness_emitter_layout() is Some(witness_scopes) else {
    return None
  }
  guard closed_values_sum_layouts([retained, records, arrays, maps, cids])
    is Some(r) &&
    closed_values_sum_layouts([
      temporary, number_writers, contract_emission, validation_records, validation_arrays,
      flat_records, flat_arrays, concatenations, canonical_scopes, witness_scopes,
    ])
    is Some(t) else {
    return None
  }
  guard compilation_metadata_sum_facts(
      [
        compilation_metadata_facts(15, fields, name_units).unwrap(),
        compilation_metadata_facts(8, fields, name_units).unwrap(),
      ],
      3,
    )
    is Some(graph_extra) &&
    compilation_metadata_facts(13, fields, name_units) is Some(material_extra) else {
    return None
  }
  guard compilation_metadata_sum_facts(
      [
        compilation_metadata_facts(14, fields, name_units).unwrap(),
        material_extra,
        compilation_metadata_facts(8, fields, name_units).unwrap(),
        compilation_metadata_facts(0, fields, name_units).unwrap(),
        compilation_metadata_facts(1, fields, name_units).unwrap(),
        compilation_metadata_facts(2, fields, name_units).unwrap(),
        compilation_metadata_facts(2, fields, name_units).unwrap(),
        compilation_metadata_facts(3, fields, name_units).unwrap(),
        compilation_metadata_facts(4, fields, name_units).unwrap(),
        compilation_metadata_facts(5, fields, name_units).unwrap(),
        compilation_metadata_facts(5, fields, name_units).unwrap(),
        compilation_metadata_facts(5, fields, name_units).unwrap(),
      ],
      8,
    )
    is Some(plan_extra) else {
    return None
  }
  Some({
    retained: r,
    temporary: t,
    graph_extra,
    material_extra,
    plan_extra,
    max_wire_bytes: max_b,
    max_nodes: max_n,
    max_depth: max_d,
    max_facts: 2,
    max_witnesses: 3,
  })
}

///|
fn compilation_metadata_repeat_units(
  value : @execution.PreparationRepresentationUnits,
  count : Int64,
) -> @execution.PreparationRepresentationUnits? {
  if count < 0L {
    return None
  }
  guard @execution.checked_preparation_add_product(
      0L,
      value.record_headers,
      count,
    )
    is Some(h) &&
    @execution.checked_preparation_add_product(0L, value.reference_slots, count)
    is Some(r) &&
    @execution.checked_preparation_add_product(0L, value.scalar_words, count)
    is Some(w) &&
    @execution.checked_preparation_add_product(
      0L,
      value.owned_utf16_units,
      count,
    )
    is Some(t) &&
    @execution.checked_preparation_add_product(
      0L,
      value.owned_wire_bytes,
      count,
    )
    is Some(b) else {
    return None
  }
  let units : @execution.PreparationRepresentationUnits = {
    record_headers: h,
    reference_slots: r,
    scalar_words: w,
    owned_utf16_units: t,
    owned_wire_bytes: b,
  }
  guard @execution.preparation_representation_cost(units) is Some(_) else {
    return None
  }
  Some(units)
}
