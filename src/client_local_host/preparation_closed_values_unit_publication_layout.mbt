///|
/// Unit publication component. ArithmeticClaims/LinkedArithmetic/CheckedArithmetic
/// graphs and HostSources control collections belong the graph-control owner.
/// Generic call/result/failure carriers belong the scaffold owner. This value
/// includes the generated proof/witness source/index and writer components;
/// none of these facts independently grants resource or publication authority.
priv struct ClosedValuesUnitPublicationLayout {
  payload : @execution.PreparationRepresentationUnits
  source_admission : @execution.PreparationRepresentationUnits
  writers : @execution.PreparationRepresentationUnits
}

///|
/// Original Values, ordinal0, actql.bound.values, SourceValue, no inputs or
/// SequenceEnforcement. These fixed emitters use only ASCII metadata: subject
/// unit:CID71#/steps/0 has length85. A finite numeral is bounded by25 chars.
/// The source recipe counts both keys and string values, not just field names.
fn closed_values_unit_publication_source_facts(
  witness : Bool,
) -> ClosedValuesLexicalFacts {
  if witness {
    {
      input_bytes: 568,
      node_upper: 15,
      objects: 3,
      arrays: 1,
      fields_upper: 13,
      quoted_tokens: 23,
      quoted_utf16_units: 466,
      longest_quoted_utf16: 85,
      longest_atom_utf16: 25,
      depth_upper: 2,
    }
  } else {
    {
      input_bytes: 228,
      node_upper: 7,
      objects: 1,
      arrays: 1,
      fields_upper: 6,
      quoted_tokens: 10,
      quoted_utf16_units: 168,
      longest_quoted_utf16: 85,
      longest_atom_utf16: 25,
      depth_upper: 2,
    }
  }
}

///|
/// Source-backed finite records (count, declared fields): selection+ceilings
/// (3,13), assembly(2,19), execution(2,11), conversion session/keys(4,15),
/// conversion frame(2,8), reidentified step/location/dependency(4,17), parsed
/// witness variants(3,12), ProgramProof(1,3), two Hosts(14,62), rowbody(5,13),
/// byte budget(1,4), Candidates(3,6), minima(2,10), pending/final Limits(4,28),
/// ConstructedLimit variants(4,12), extent tuples(8,20), ObjectViews(14,28),
/// wide-key check pair tuples(18,18): total94 records/299 fields. Counting
/// fields in both slot categories is conservative, not an actual charge.
fn closed_values_unit_publication_payload_layout(
  result_name_utf16 : Int,
) -> @execution.PreparationRepresentationUnits? {
  if result_name_utf16 < 0 {
    return None
  }
  let records : @execution.PreparationRepresentationUnits = {
    record_headers: 94L,
    reference_slots: 299L,
    scalar_words: 299L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // All listed caller Arrays and admission field/cursor arrays:67 owners,
  //122 items. Maps:7 conversion/seen maps3 entries plus19 decoder-view/key
  // validation maps90 entries. These maps are NOT the indexed-tree owner.
  let arrays = closed_values_program_arrays(67L, 122L, true)
  let maps = closed_values_program_maps(26L, 93L, true)
  // Four step-subject constructions each create ordinal1 and concatenation
  // outputs76/84/85. Row+byte subjects each create two replace outputs<=2U,
  // then prefixes76/86 and complete subjects91+2U /92+2U. Six retained CIDs
  // plus two verification CIDs71; hash digests are in the writer component.
  // Finished material Strings/Bytes228+568 coexist with their parsed owners.
  let text : @execution.PreparationRepresentationUnits = {
    record_headers: 16L + 12L + 8L + 4L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: 984L +
    679L +
    16L * result_name_utf16.to_int64() +
    568L +
    796L,
    owned_wire_bytes: 796L,
  }
  // emit_cursor sorts three objects in witness, one in proof; all scopes are
  // bounded by the root's nine fields. Sum scopes rather than assume early GC.
  guard closed_values_sort_scratch_layout(9) is Some(sort) else { return None }
  closed_values_sum_layouts([records, arrays, maps, text, sort, sort, sort])
}

///|
/// Shared writer construction truth, not a separate quote coefficient table.
/// Row limit is largest:40 value nodes and depth4 (root/candidates/witness/
/// source); byte limit25, Host/witness15, proof7 are dominated. Nine hashing
/// writers +two direct SHA operations +four measuring +two material writers
/// use seventeen conservative hash-control envelopes. Nonhash envelopes may
/// contain unused SHA controls; this is explicit slack, not claimed actual use.
/// Material output additionally owns TextOutput/StringBuilder and old/new
/// UTF16 buffer backing. Final Strings/Bytes belong payload, not this buffer.
fn closed_values_unit_publication_writer_layout() -> @execution.PreparationRepresentationUnits? {
  guard @encode.hash_writer_construction_inventory(40, 4) is Some(v) else {
    return None
  }
  let hash : @execution.PreparationRepresentationUnits = {
    record_headers: v.record_headers,
    reference_slots: v.reference_slots,
    scalar_words: v.scalar_words,
    owned_utf16_units: v.owned_utf16_units,
    owned_wire_bytes: v.owned_wire_bytes,
  }
  let buffers : @execution.PreparationRepresentationUnits = {
    record_headers: 4L,
    reference_slots: 4L,
    scalar_words: 2L,
    owned_utf16_units: 2L * (228L + 568L),
    owned_wire_bytes: 0L,
  }
  closed_values_sum_layouts([
    hash, hash, hash, hash, hash, hash, hash, hash, hash, hash, hash, hash, hash,
    hash, hash, hash, hash, buffers,
  ])
}

///|
/// The two generated documents are parsed by capacity_witness.admit and
/// bind_program_proof, unlike constructed Host/Limit claims. Conservatively
/// sum retained/parser/index peaks for both: parsed witness remains live while
/// proof is admitted. No observed-after-allocation byte count is used here.
fn closed_values_unit_publication_layout(
  result_name_utf16 : Int,
) -> ClosedValuesUnitPublicationLayout? {
  guard closed_values_unit_publication_payload_layout(result_name_utf16)
    is Some(payload) else {
    return None
  }
  guard closed_values_source_phase_layout(
      closed_values_unit_publication_source_facts(false),
    )
    is Some(proof) else {
    return None
  }
  guard closed_values_source_phase_layout(
      closed_values_unit_publication_source_facts(true),
    )
    is Some(witness) else {
    return None
  }
  // Source/index excludes the input document: borrow the shared pinned-JS
  // byte-decoding owner recipe, not a separate per-consumer coefficient table.
  guard closed_values_js_bytes_document_layout(796L, 2)
    is Some(decoded_documents) else {
    return None
  }
  guard closed_values_sum_layouts([
      decoded_documents,
      proof.retained,
      proof.parser_temporary,
      proof.decoder_temporary,
      witness.retained,
      witness.parser_temporary,
      witness.decoder_temporary,
    ])
    is Some(source_admission) else {
    return None
  }
  guard closed_values_unit_publication_writer_layout() is Some(writers) else {
    return None
  }
  guard closed_values_sum_layouts([payload, source_admission, writers])
    is Some(_) else {
    return None
  }
  Some({ payload, source_admission, writers, })
}
