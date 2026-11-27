///|
/// Pure custody codec shared by Local Hosts. A valid packet grants neither
/// publication nor read authority; the original Run journal and current
/// publisher still fence its adoption. Bounds and wire match Native originals.
pub(all) enum ClientRunPolicyOriginalsIssue {
  ForeignRun
  PublicationPolicy(@checked.LocalDependencyBodyIssue)
  CapacityExceeded
  Encoding
  CustodyLost
}

///|
fn client_policy_original_text(
  object : @decode.ObjectView,
  key : String,
) -> String? {
  @decode.lookup(object, key).bind(fn(value) { @decode.text(value).to_option() })
}

///|
/// Constructor gates supplied by the original SDK row-material owner. The
/// collector lends only the already checked body geometry and graph counts.
pub(all) struct ClientRunPolicyCollectionFunding {
  before_collection : () -> Bool
  before_measure : (Int, Int) -> Bool
  before_emit : (Int, Int, Int) -> Bool
  before_admit : (Int, Int, Int) -> Bool
  before_validate : (Int, Int) -> Bool
  current : () -> Bool
}

///|
/// Existing Policy constructors selected by the first Task row owner.
pub(all) enum ClientTaskPolicyConstructionStage {
  Collection
  Measure(Int, Int)
  Emit(Int, Int, Int)
  Admit(Int, Int, Int)
  Validate(Int, Int)
  DecodePacket(Int)
}

///|
pub fn client_task_policy_construction_capacity(
  stage : ClientTaskPolicyConstructionStage,
) -> (Int64, Int64)? {
  let (retained, scratch) = match stage {
    Collection =>
      (
        client_run_decode_units(24L, 60L, 24L, 0L, 0L),
        client_run_decode_units(32L, 80L, 48L, 0L, 0L),
      )
    DecodePacket(bytes) => {
      guard bytes > 0 &&
        bytes <= 65536 &&
        @decode.preserving_json_admission_construction_inventory(
          bytes,
          Int::min(bytes, 512),
          8,
        ) is Some(packet) else {
        return None
      }
      // The outer source/index and extracted body strings survive the
      // sequential inner admits. Their decode and traversal are one peak.
      (
        client_run_decode_units(
          packet.record_headers + 256L,
          packet.reference_slots + 1024L,
          packet.scalar_words + 512L,
          packet.owned_utf16_units + bytes.to_int64(),
          bytes.to_int64(),
        ),
        client_run_decode_units(12L, 32L, 20L, 0L, 0L),
      )
    }
    Measure(keys, depth) => {
      guard @encode.text_writer_live_key_inventory(0, keys, depth)
        is Some(writer) else {
        return None
      }
      (
        client_run_decode_units(0L, 0L, 0L, 0L, 0L),
        client_run_decode_units(
          writer.record_headers,
          writer.reference_slots,
          writer.scalar_words,
          writer.owned_utf16_units,
          0L,
        ),
      )
    }
    Emit(bytes, nodes, depth) | Admit(bytes, nodes, depth) => {
      guard bytes > 0 &&
        bytes <= 65536 &&
        nodes > 0 &&
        nodes <= 8192 &&
        depth > 0 &&
        depth <= 64 &&
        @encode.text_writer_construction_inventory(bytes, nodes, depth)
        is Some(writer) &&
        @encode.hash_writer_construction_inventory(nodes, depth) is Some(hash) else {
        return None
      }
      let b = bytes.to_int64()
      let emit = client_run_decode_units(
        writer.record_headers + hash.record_headers + 8L,
        writer.reference_slots + hash.reference_slots + 18L,
        writer.scalar_words + hash.scalar_words + 18L,
        writer.owned_utf16_units + hash.owned_utf16_units,
        hash.owned_wire_bytes + 3L * b,
      )
      if stage is Emit(_, _, _) {
        (client_run_decode_units(2L, 2L, 1L, b, 0L), emit)
      } else {
        guard @source.json_source_grammar_construction_extent(
            bytes, nodes, depth,
          )
          is Some(source) &&
          @canonical.source_conversion_construction_extent(
            nodes, nodes, nodes, nodes, depth, bytes,
          )
          is Some(canonical) &&
          @shape.map_construction_extent(2L, 2L) is Some(maps) else {
          return None
        }
        let n = nodes.to_int64()
        let held = client_run_decode_units(
          canonical.retained.record_headers + maps.record_headers + 3L * n + 18L,
          canonical.retained.reference_slots +
          maps.reference_slots +
          5L * n +
          24L,
          canonical.retained.scalar_words + maps.scalar_words + 4L * n + 18L,
          canonical.retained_utf16_units + b + 192L,
          0L,
        )
        guard @execution.compose_preparation_representation([
            emit,
            client_run_decode_units(
              source.record_headers + canonical.scratch.record_headers + 4L * n,
              source.reference_slots +
              canonical.scratch.reference_slots +
              8L * n,
              source.scalar_words + canonical.scratch.scalar_words + 4L * n,
              source.owned_utf16_units + canonical.scratch_utf16_units + 2L * b,
              2L * b,
            ),
          ])
          is Some(work) else {
          return None
        }
        (held, work)
      }
    }
    Validate(entries, references) => {
      let n = entries.to_int64()
      let edges = references.to_int64()
      guard entries > 0 &&
        entries <= 4096 &&
        references >= 0 &&
        references <= 4096 &&
        @shape.map_construction_extent(6L, 6L * n + edges) is Some(maps) else {
        return None
      }
      // Per-body projected records survive the graph walk. Its maps, edge
      // aliases, DFS frames, color/height arrays and composite keys are local.
      (
        client_run_decode_units(2L + n, 8L + 6L * n, 4L, 0L, 0L),
        client_run_decode_units(
          maps.record_headers + 28L * n + 12L * edges + 160L,
          maps.reference_slots + 48L * n + 20L * edges + 320L,
          maps.scalar_words + 36L * n + 16L * edges + 256L,
          512L * n + 256L * edges,
          0L,
        ),
      )
    }
  }
  guard @execution.preparation_representation_cost(retained) is Some(bytes) &&
    @execution.preparation_representation_cost(scratch) is Some(work) else {
    return None
  }
  Some((bytes, work))
}

///|
fn capture_run_policy_collection(
  program : @checked.CheckedProgram,
  cid : String,
  funding : ClientRunPolicyCollectionFunding,
) -> Result[Array[(String, String, String)], @checked.LocalDependencyBodyIssue] {
  if !(funding.before_collection)() {
    return Err(BudgetExceeded)
  }
  if !(funding.current)() {
    return Err(ForeignBody)
  }
  let admitted : Array[@publication.CapturedEffectDependencyBody] = []
  let seen : Map[String, String] = Map([])
  let unadmitted = match
    checked_client_publication_policy_bodies(
      program,
      cid,
      65536,
      8192,
      64,
      retain_catalog=true,
      before_body=Some(funding.before_admit),
      before_emit=Some(funding.before_emit),
      before_catalog_emit=Some(funding.before_emit),
      before_measure=Some(funding.before_measure),
      current=Some(funding.current),
      retained_body_keys=Some(seen),
      admitted_body=Some((body, _) => {
        let kind = @publication.captured_effect_dependency_body_kind(body)
        let identity = @publication.captured_effect_dependency_body_cid(body)
        let wire = @publication.captured_effect_dependency_body_json(body)
        seen[kind + "\u0000" + identity] = wire
        admitted.push(body)
        Ok(())
      }),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !unadmitted.is_empty() ||
    admitted.is_empty() ||
    @publication.captured_effect_dependency_body_cid(admitted[0]) != cid {
    return Err(ForeignBody)
  }
  let mut references = 0
  for body in admitted {
    let count = @publication.captured_effect_dependency_body_reference_count(
      body,
    )
    if count > 4096 - references {
      return Err(BudgetExceeded)
    }
    references += count
  }
  if !(funding.before_validate)(admitted.length(), references) {
    return Err(BudgetExceeded)
  }
  if !(funding.current)() {
    return Err(ForeignBody)
  }
  match
    @publication.validate_captured_effect_dependency_bodies(
      admitted,
      [admitted[0]],
      0,
      {
        max_entries: 4096,
        max_total_bytes: 65536,
        max_depth: 64,
        max_references: 4096,
      },
    ) {
    Ok(_) =>
      Ok(
        admitted.map(body => {
          (
            @publication.captured_effect_dependency_body_kind(body),
            @publication.captured_effect_dependency_body_cid(body),
            @publication.captured_effect_dependency_body_json(body),
          )
        }),
      )
    Err(@publication.MissingDependency) => Err(MissingDependency)
    Err(
      @publication.InvalidLimits
      | @publication.EntryLimit
      | @publication.ByteLimit
      | @publication.ReferenceLimit
      | @publication.DepthLimit
    ) => Err(BudgetExceeded)
    Err(_) => Err(ForeignBody)
  }
}

///|
// Finite originals remain inside the existing Run row and its unchanged
// physical record budget. This is custody, never read or egress authority.
pub fn issue_client_run_policy_originals(
  prepared : PreparedClientProgram,
  compiled? : ClientCompiledRun,
  before_packet? : ((Int64, Int64) -> Bool)? = None,
  collection_funding? : ClientRunPolicyCollectionFunding? = None,
) -> Result[String, ClientRunPolicyOriginalsIssue] {
  issue_client_run_policy_originals_with_root(
    prepared, compiled, before_packet, collection_funding,
  ).map(original => original.0)
}

///|
// The same packet issuer records its selected root for the live captured Run.
// Cold restoration still validates the complete canonical packet.
fn issue_client_run_policy_originals_with_root(
  prepared : PreparedClientProgram,
  compiled : ClientCompiledRun?,
  before_packet : ((Int64, Int64) -> Bool)?,
  collection_funding : ClientRunPolicyCollectionFunding?,
) -> Result[(String, String), ClientRunPolicyOriginalsIssue] {
  let selected = match compiled {
    Some(value) => {
      if !client_compiled_run_matches(value, prepared) {
        return Err(ForeignRun)
      }
      match collection_funding {
        Some(funding) => {
          guard value.compilation is Tasks(_) &&
            prepared_client_acquisition_count(value.owner) > 0 &&
            prepared_client_publication_data_policy_cid(prepared) is Some(cid) else {
            return Err(ForeignRun)
          }
          capture_run_policy_collection(
            @strategy.graph_program(prepared.graph),
            cid,
            funding,
          )
        }
        None =>
          client_compiled_run_publication_policy_bodies(value, 65536, 8192, 64)
      }
    }
    None => {
      if collection_funding is Some(_) {
        return Err(ForeignRun)
      }
      prepared_client_publication_policy_bodies(prepared, 65536, 8192, 64)
    }
  }
  let bodies = match selected {
    Ok(value) => value
    Err(issue) => return Err(PublicationPolicy(issue))
  }
  encode_client_run_policy_originals(bodies, before_packet~).map(wire => {
    // The existing encoder refuses an empty inventory.
    (wire, bodies[0].1)
  })
}

///|
/// Borrow the original checked Effect's Result policy closure for the existing
/// packet. This issues no compilation, policy, current permission or read grant.
pub fn issue_client_effect_run_policy_originals(
  prepared : PreparedClientEffectComputation,
) -> Result[String, ClientRunPolicyOriginalsIssue] {
  let bodies = match
    prepared_client_effect_publication_policy_bodies(prepared, 65536, 8192, 64) {
    Ok(value) => value
    Err(issue) => return Err(PublicationPolicy(issue))
  }
  encode_client_run_policy_originals(bodies)
}

///|
// The checked body table stays borrowed. Account for the owned policy packet
// and its temporary writer by the exact quoted geometry of the selected wires.
fn client_policy_originals_packet_capacity(
  bodies : Array[(String, String, String)],
) -> Result[(Int64, Int64), ClientRunPolicyOriginalsIssue] {
  // The caller has checked 1..64 bodies. The quoted extent includes the
  // surrounding quotes, so these literals count only keys and punctuation.
  let fixed = "{\"bodies\":[],\"root_policy_cid\":}".length().to_int64()
  let member_units = "{\"body\":,\"cid\":,\"kind\":}".length().to_int64()
  let count = bodies.length().to_int64()
  let separators = count - 1L
  guard @encode.quoted_string_construction_extent(bodies[0].1)
    is Some((root_bytes, root_units)) else {
    return Err(Encoding)
  }
  let mut bytes = fixed + count * member_units + separators + root_bytes
  let mut units = fixed + count * member_units + separators + root_units
  for (kind, cid, body) in bodies {
    guard @encode.quoted_string_construction_extent(kind)
      is Some((kind_bytes, kind_units)) &&
      @encode.quoted_string_construction_extent(cid)
      is Some((cid_bytes, cid_units)) &&
      @encode.quoted_string_construction_extent(body)
      is Some((body_bytes, body_units)) else {
      return Err(Encoding)
    }
    bytes += kind_bytes + cid_bytes + body_bytes
    units += kind_units + cid_units + body_units
    if bytes > 65536L {
      return Err(CapacityExceeded)
    }
  }
  // Root object, body array, root CID, then each member object and its three
  // values. The ordinary writer below still uses its original 512/8 limits.
  let nodes = 3 + 4 * bodies.length()
  guard @encode.text_writer_construction_inventory(bytes.to_int(), nodes, 3)
    is Some(writer) &&
    @execution.preparation_representation_cost({
      record_headers: 2L,
      reference_slots: 1L,
      scalar_words: 1L,
      owned_utf16_units: units,
      owned_wire_bytes: 0L,
    })
    is Some(retained) &&
    @execution.preparation_representation_cost({
      record_headers: writer.record_headers,
      reference_slots: writer.reference_slots,
      scalar_words: writer.scalar_words,
      owned_utf16_units: writer.owned_utf16_units,
      owned_wire_bytes: 0L,
    })
    is Some(scratch) else {
    return Err(CapacityExceeded)
  }
  Ok((retained, scratch))
}

///|
// All callers use the same existing packet and bounds. Policy selection and
// original Host/journal authenticity are separate from this pure encoding.
fn encode_client_run_policy_originals(
  bodies : Array[(String, String, String)],
  before_packet? : ((Int64, Int64) -> Bool)? = None,
) -> Result[String, ClientRunPolicyOriginalsIssue] {
  guard bodies.length() > 0 && bodies.length() <= 64 else {
    return Err(CapacityExceeded)
  }
  if before_packet is Some(fund) {
    match client_policy_originals_packet_capacity(bodies) {
      Ok((retained, scratch)) =>
        if !fund(retained, scratch) {
          return Err(CapacityExceeded)
        }
      Err(issue) => return Err(issue)
    }
  }
  try {
    let writer = @encode.writer(65536, 512, 8)
    @encode.begin_object(writer)
    @encode.key(writer, "bodies")
    @encode.begin_array(writer)
    for (kind, cid, body) in bodies {
      @encode.begin_object(writer)
      @encode.key(writer, "body")
      @encode.string_value(writer, body)
      @encode.key(writer, "cid")
      @encode.string_value(writer, cid)
      @encode.key(writer, "kind")
      @encode.string_value(writer, kind)
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    @encode.key(writer, "root_policy_cid")
    @encode.string_value(writer, bodies[0].1)
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    @encode.OutputLimit => Err(CapacityExceeded)
    _ => Err(Encoding)
  }
}

///|
pub fn read_client_run_policy_originals(
  wire : String,
  fund? : ((ClientTaskPolicyConstructionStage) -> Bool)? = None,
) -> Result[
  Array[@publication.CapturedEffectDependencyBody],
  ClientRunPolicyOriginalsIssue,
] {
  if fund is Some(quote) {
    guard @scalar.admit_utf8_length(wire, 65536) is Ok(bytes) && bytes > 0 else {
      return Err(CustodyLost)
    }
    if !quote(DecodePacket(bytes)) {
      return Err(CapacityExceeded)
    }
  }
  let source = match
    @source.parse_json_bytes_preserving(@utf8.encode(wire), {
      max_input_bytes: 65536,
      max_nodes: 512,
      max_depth: 8,
    }) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let cursor = match
    @decode.admit(source, {
      max_nodes: 512,
      max_depth: 8,
      max_string_bytes: 65536,
      max_total_string_bytes: 65536,
    }) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  guard @decode.closed_object(cursor, ["bodies", "root_policy_cid"]) is Ok(root) &&
    client_policy_original_text(root, "root_policy_cid") is Some(root_cid) &&
    @decode.lookup(root, "bodies") is Some(list) &&
    @decode.elements(list) is Ok(elements) &&
    elements.length() > 0 &&
    elements.length() <= 64 else {
    return Err(CustodyLost)
  }
  let bodies : Array[@publication.CapturedEffectDependencyBody] = []
  for element in elements {
    guard @decode.closed_object(element, ["body", "cid", "kind"]) is Ok(fields) &&
      client_policy_original_text(fields, "body") is Some(body) &&
      client_policy_original_text(fields, "cid") is Some(cid) &&
      client_policy_original_text(fields, "kind") is Some(kind) &&
      (kind == "data_policy" || kind == "source_view_contract") else {
      return Err(CustodyLost)
    }
    if fund is Some(quote) {
      guard @scalar.admit_utf8_length(body, 65536) is Ok(bytes) && bytes > 0 else {
        return Err(CustodyLost)
      }
      if !quote(Admit(bytes, Int::min(bytes, 8192), Int::min(bytes, 64))) {
        return Err(CapacityExceeded)
      }
    }
    match
      @publication.admit_captured_effect_dependency_body(
        kind,
        Some(cid),
        body,
        65536,
        8192,
        64,
      ) {
      Ok(value) => bodies.push(value)
      Err(_) => return Err(CustodyLost)
    }
  }
  if @publication.captured_effect_dependency_body_kind(bodies[0]) !=
    "data_policy" ||
    @publication.captured_effect_dependency_body_cid(bodies[0]) != root_cid {
    return Err(CustodyLost)
  }
  if fund is Some(quote) {
    let mut references = 0
    for body in bodies {
      let count = @publication.captured_effect_dependency_body_reference_count(body)
      if count > 512 - references {
        return Err(CustodyLost)
      }
      references += count
    }
    if !quote(Validate(bodies.length(), references)) {
      return Err(CapacityExceeded)
    }
  }
  match
    @publication.validate_captured_effect_dependency_bodies(
      bodies,
      [bodies[0]],
      0,
      {
        max_entries: 64,
        max_total_bytes: 65536,
        max_depth: 64,
        max_references: 512,
      },
    ) {
    Ok(_) => Ok(bodies)
    Err(_) => Err(CustodyLost)
  }
}
