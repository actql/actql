///|
/// Exact private envelope of the existing saved Effect material. These are
/// serialization fields, not admitted material, current authority or a Run.
pub(all) struct ClientEffectMaterialJournalPacket {
  intent_cid : String
  materials_cid : String
  materials_wire : String
  request_scope_cid : String
  run_definition_cid : String
  submission_reference : String
}

///|
pub fn client_effect_material_journal_packet_wire(
  packet : ClientEffectMaterialJournalPacket,
) -> Result[String, ClientJournalEncodingIssue] {
  try {
    let writer = @encode.writer(131072, 16, 2)
    @encode.begin_object(writer)
    for
      (key, value) in [
        ("intent_cid", packet.intent_cid),
        ("materials_cid", packet.materials_cid),
        ("materials_wire", packet.materials_wire),
        ("request_scope_cid", packet.request_scope_cid),
        ("run_definition_cid", packet.run_definition_cid),
        ("submission_reference", packet.submission_reference),
      ] {
      @encode.key(writer, key)
      @encode.string_value(writer, value)
    }
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    @encode.OutputLimit => Err(CapacityExceeded)
    _ => Err(Encoding)
  }
}

///|
pub fn read_client_effect_material_journal_packet(
  wire : String,
) -> Result[ClientEffectMaterialJournalPacket, ClientJournalDecodingIssue] {
  let source = match
    @source.parse_json_bytes_preserving(@utf8.encode(wire), {
      max_input_bytes: 131072,
      max_nodes: 16,
      max_depth: 2,
    }) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let cursor = match
    @decode.admit(source, {
      max_nodes: 16,
      max_depth: 2,
      max_string_bytes: 131072,
      max_total_string_bytes: 131072,
    }) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  guard @decode.closed_object(cursor, [
      "intent_cid", "materials_cid", "materials_wire", "request_scope_cid", "run_definition_cid",
      "submission_reference",
    ])
    is Ok(fields) &&
    effect_material_journal_text(fields, "intent_cid") is Some(intent_cid) &&
    effect_material_journal_text(fields, "materials_cid") is Some(materials_cid) &&
    effect_material_journal_text(fields, "materials_wire")
    is Some(materials_wire) &&
    !materials_wire.is_empty() &&
    effect_material_journal_text(fields, "request_scope_cid")
    is Some(request_scope_cid) &&
    effect_material_journal_text(fields, "run_definition_cid")
    is Some(run_definition_cid) &&
    effect_material_journal_text(fields, "submission_reference")
    is Some(submission_reference) else {
    return Err(CustodyLost)
  }
  let packet : ClientEffectMaterialJournalPacket = {
    intent_cid,
    materials_cid,
    materials_wire,
    request_scope_cid,
    run_definition_cid,
    submission_reference,
  }
  guard client_effect_material_journal_packet_wire(packet) is Ok(canonical) &&
    canonical == wire else {
    return Err(CustodyLost)
  }
  Ok(packet)
}

///|
fn effect_material_journal_text(
  object : @decode.ObjectView,
  key : String,
) -> String? {
  @decode.lookup(object, key).bind(value => @decode.text(value).to_option())
}
