///|
/// One numeric Values, no authored evidence, no input or parameters. Operation
/// metadata only: graph-control, Unit publication, resolution-index copies and
/// encode/hash writer workspaces have distinct owners in the Context plan.
priv struct ClosedValuesOperationCapacityLayout {
  retained : @execution.PreparationRepresentationUnits
  temporary : @execution.PreparationRepresentationUnits
}

///|
/// Actual four emitter templates, including nested witness copies in rowlimit.
/// A 25-character finite-number spelling upper follows capacity_policy's
/// construction inventory. These are structural facts, not budget constants.
fn closed_values_capacity_metadata_facts(
  kind : Int,
) -> ClosedValuesLexicalFacts? {
  let (bytes, nodes, objects, arrays, fields, quoted, text, depth) = match
    kind {
    0 => (157, 7, 1, 1, 6, 10, 97, 2)
    1 => (497, 15, 3, 1, 13, 23, 395, 2)
    2 => (507, 15, 3, 1, 13, 23, 405, 2)
    3 => (1331, 40, 7, 3, 35, 62, 1048, 4)
    _ => return None
  }
  Some({
    input_bytes: bytes,
    node_upper: nodes,
    objects,
    arrays,
    fields_upper: fields,
    quoted_tokens: quoted,
    quoted_utf16_units: text,
    longest_quoted_utf16: 71,
    longest_atom_utf16: 25,
    depth_upper: depth,
  })
}

///|
/// Fixed record packet: charge each declared field as both reference and word
/// conservatively, rather than pretend a precise engine representation. The
/// small explicit slack is reported separately from observed logical charges.
fn closed_values_capacity_record_packet(
  count : Int64,
  fields : Int64,
) -> @execution.PreparationRepresentationUnits {
  {
    record_headers: count,
    reference_slots: fields,
    scalar_words: fields,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
}

///|
fn closed_values_operation_capacity_layout(
  fields : Int,
) -> ClosedValuesOperationCapacityLayout? {
  guard closed_values_append_capacity(fields) is Some(width) && fields > 0 else {
    return None
  }
  // ValuesMaterial6 + CapacityMaterial2x2 + ValuesRowBound3 + DerivedBound5;
  // StepBound2x9 + ResourceOwner2 + BoundCells3 + WireBound5 + WireLimit3;
  // RowLimit4 + RecursiveAdmission8 + RecursiveFields1 + Ceilings3x3;
  // PublicationCheck3 + Publication/Execution2x1 + MetadataBudget4;
  // WireWitness6x9 + ProgramProof2x3 + LimitClaim3x7 + HostWitness6/Ref1;
  // BoundDerivation2x9 + PreparedBoundInputs2x4 (derive and recheck).
  let records = closed_values_capacity_record_packet(
    1L +
    2L +
    1L +
    1L +
    2L +
    1L +
    1L +
    1L +
    1L +
    1L +
    1L +
    1L +
    3L +
    1L +
    2L +
    1L +
    6L +
    2L +
    3L +
    1L +
    1L +
    2L +
    2L,
    6L +
    4L +
    3L +
    5L +
    18L +
    2L +
    3L +
    5L +
    3L +
    4L +
    8L +
    1L +
    9L +
    3L +
    2L +
    4L +
    54L +
    6L +
    21L +
    6L +
    1L +
    18L +
    8L,
  )
  // Named cap-eight small Arrays: material slots/bounds/added/consumers(4),
  // bound inputs supplied/prepared ids+inputs twice/sortcopy/dependencies(7),
  // ProgramProof empty inputs twice(2), witness dependencies6(6),
  // wire arithmetic supplied witnesses/indices/candidates/selection/copy(5),
  // row supplied witnesses/decoded candidates/selection/copy(4),
  // recursive empty fields/pending frame(2). Sum30; actual empty Arrays use
  // less. Copied backing overlap is included as two cap-eight backings.
  let arrays : @execution.PreparationRepresentationUnits = {
    record_headers: 90L,
    reference_slots: 30L * 17L,
    scalar_words: 60L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  // Six witness Source wrappers, four parsed/HostSource bodies; two typed
  // ConstructedLimit bodies plus usage tuples, one ParsedLimit; two minima
  // and three Candidate payloads; retained Some slots/ceilings/meter/Rule.
  let carriers = closed_values_capacity_record_packet(
    6L + 4L + 7L + 1L + 2L + 3L + 12L,
    12L + 4L + 16L + 1L + 10L + 6L + 12L,
  )
  // Seven newly constructed CIDs; subjects and intermediate concatenations
  // (three checked-step:0, wire prefix/full, rows prefix/full), two placeholder
  // zero-digest/CID pairs. Parsed strings are separately owned below.
  let strings : @execution.PreparationRepresentationUnits = {
    record_headers: 18L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: 7L * 71L +
    3L * 14L +
    19L +
    24L +
    21L +
    24L +
    2L * (64L + 71L),
    owned_wire_bytes: 0L,
  }
  let empty_map = closed_values_map_constructor_layout(0).unwrap()
  let mut retained = closed_values_sum_layouts([
    records, arrays, carriers, strings, empty_map,
  ]).unwrap()
  let mut temporary : @execution.PreparationRepresentationUnits = {
    // selected Bool array plus old backing, one Read frame and per-cell
    // borrowed CheckedValue tuple/Result; no per-cell retained allocation.
    record_headers: 9L,
    reference_slots: 2L * width + 12L,
    scalar_words: 12L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  for kind in 0..<4 {
    let facts = closed_values_capacity_metadata_facts(kind).unwrap()
    let source = closed_values_source_inventories(facts)
    // Retain all four trees conservatively, including temporary rowproof and
    // AST containers otherwise dead after decode. Their small slack is explicit;
    // no source/indexed Strings or spans charged twice within a tree.
    retained = closed_values_sum_layouts([
      retained,
      source.source_retained,
      source.indexed_additional,
    ]).unwrap()
    temporary = closed_values_sum_layouts([
      temporary,
      source.source_growth_peak,
      source.key_admission_peak,
      source.parser_ancestry_peak,
      source.decoder_ancestry_peak,
      source.parser_controls_peak,
      source.decoder_controls_peak,
    ]).unwrap()
    let n = facts.node_upper.to_int64()
    // Canonical readmission opens an ObjectView at each object and scalar
    // projection wrappers at each node. Same-witness comparison has two trees
    // live: two complete walk families dominate both recursive active stacks.
    let walk = closed_values_walk_storage_layout(
      facts.node_upper,
      Int::min(9, facts.node_upper),
    ).unwrap()
    let map = closed_values_map_constructor_layout(9).unwrap()
    // Per-node projection packet (H,R,W): two Cursors(2,4,2), two
    // ObjectViews excluding their separately priced Maps(2,4,0), ValueView
    // carrier(1,1,1), two Some(2,2,2), two Result(2,2,2), child/name-array
    // wrapper+backing(2,1,2), projection pair(1,2,0): (12,16,9).
    // Two additional name/allowed-key arrays add (4,2,4) per node;
    // at most four whole-tree child/key projections add <=4n reference slots.
    // Thus (16,22,13) is dominated by the explicit (16,24,20) packet.
    // Sort ancestry is priced by the shared sort constructor below, not folded
    // into unexplained per-node slack.
    // The two generic walks above additionally own their Cursor/tuple stacks.
    // Numeric formatting is the shared encode/hash writer component; decoded
    // wire UTF16 is the explicit wire packet below, not borrowed/free text.
    let views : @execution.PreparationRepresentationUnits = {
      record_headers: 16L * n,
      reference_slots: 24L * n,
      scalar_words: 20L * n,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    }
    let sort = closed_values_sort_scratch_layout(9).unwrap()
    // emit_cursor recursion: one depth+1 chain; charge two conservatively.
    // same_cursor is iterative and its pending pairs are in the walk packet.
    // Each live emit frame has Cursor/writer/view/keys/current child and
    // loop/omit state. This is dynamic recursion, not fixed VM baseline.
    let frames : @execution.PreparationRepresentationUnits = {
      record_headers: 2L * (facts.depth_upper.to_int64() + 1L),
      reference_slots: 10L * (facts.depth_upper.to_int64() + 1L),
      scalar_words: 6L * (facts.depth_upper.to_int64() + 1L),
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    }
    temporary = closed_values_sum_layouts([
      temporary, walk, walk, views, sort, frames,
    ]).unwrap()
    for _ in 0..<(facts.objects * 2) {
      temporary = closed_values_sum_layouts([temporary, map]).unwrap()
    }
    // Owned serialized Bytes plus separately decoded ASCII document. The
    // common Node byte-decode recipe owns String/BytesView/subarray/result
    // controls; material writer String backing remains the writer's owner.
    let wire : @execution.PreparationRepresentationUnits = {
      record_headers: 1L,
      reference_slots: 0L,
      scalar_words: 1L,
      owned_utf16_units: 0L,
      owned_wire_bytes: facts.input_bytes.to_int64(),
    }
    let decoded = closed_values_js_bytes_document_layout(
      facts.input_bytes.to_int64(),
      1,
    ).unwrap()
    temporary = closed_values_sum_layouts([temporary, wire, decoded]).unwrap()
  }
  // Named staging copy bounds immutable pending/complete variants, closure
  // environments, API Result/Option/tuple carriers and construction limits.
  // A whole payload packet remains live beside the retained final packet;
  // this does not charge fixed VM call frames or duplicate graph-control.
  temporary = closed_values_sum_layouts([temporary, records, carriers, arrays]).unwrap()
  guard @execution.preparation_representation_cost(retained) is Some(_) &&
    @execution.preparation_representation_cost(temporary) is Some(_) else {
    return None
  }
  Some({ retained, temporary, })
}
