///|
/// The four original writers of a single-text-field UPDATE have distinct
/// wire extents. The rendered request body alone crosses HTTP.
pub(all) struct InstalledUpdateTextWireExtent {
  bytes : Int64
  utf16_units : Int64
} derive(Eq, Debug)

///|
pub(all) struct InstalledUpdateTextWireExtents {
  body : InstalledUpdateTextWireExtent
  request : InstalledUpdateTextWireExtent
  request_cid_preimage : InstalledUpdateTextWireExtent
  recovery : InstalledUpdateTextWireExtent
}

///|
fn update_quoted_text(text : String) -> InstalledUpdateTextWireExtent? {
  guard @encode.quoted_string_construction_extent(text)
    is Some((bytes, utf16_units)) else {
    return None
  }
  Some({ bytes, utf16_units, })
}

///|
fn InstalledUpdateTextWireExtent::append(
  self : InstalledUpdateTextWireExtent,
  other : InstalledUpdateTextWireExtent,
) -> InstalledUpdateTextWireExtent {
  {
    bytes: self.bytes + other.bytes,
    utf16_units: self.utf16_units + other.utf16_units,
  }
}

///|
fn InstalledUpdateTextWireExtent::ascii(
  self : InstalledUpdateTextWireExtent,
  bytes : Int64,
) -> InstalledUpdateTextWireExtent {
  { bytes: self.bytes + bytes, utf16_units: self.utf16_units + bytes, }
}

///|
/// Count extra ASCII escapes when the quoted scalar itself sits inside a
/// quoted JSON body. A literal backslash or quote contributes two escaped ASCII
/// characters on the second pass; a control escape introduces one slash.
/// The first encoder has already checked the exact original UTF16.
fn update_quote_inside_body(
  text : String,
  extent : InstalledUpdateTextWireExtent,
) -> InstalledUpdateTextWireExtent {
  let mut escapes = 2L // The two original quote delimiters.
  for index in 0..<text.length() {
    let unit = text[index].to_int()
    if unit == 0x22 || unit == 0x5c {
      escapes += 2L
    } else if unit < 32 {
      escapes += 1L
    }
  }
  extent.ascii(escapes)
}

///|
fn update_member_digits(index : Int) -> Int64 {
  let mut digits = 1L
  let mut remaining = index
  while remaining >= 10 {
    remaining = remaining / 10
    digits += 1L
  }
  digits
}

///|
/// Measure the original logical request `{idField: target, field: text, body}`,
/// its existing `{version, boundaryCid, ...request}` CID preimage, and the
/// independently stored `[boundaryCid, [effectId, ordinal, mappingCid],
/// target, text]` recovery witness. Keep their actual quotes separate before
/// any writer or hash input is created. A quote supplies size only.
pub fn installed_update_text_wire_extents(
  identity_field : String,
  field : String,
  target : String,
  text : String,
  request_domain : String,
  boundary_cid : String,
  effect_id : String,
  member_index : Int,
  mapping_cid : String,
  explicit_null? : Bool = false,
) -> InstalledUpdateTextWireExtents? {
  guard member_index >= 0 &&
    (!explicit_null || text.is_empty()) &&
    update_quoted_text(identity_field) is Some(identity_key) &&
    update_quoted_text(field) is Some(field_key) &&
    update_quoted_text(target) is Some(identity) &&
    update_quoted_text(text) is Some(value) &&
    update_quoted_text(request_domain) is Some(domain) &&
    update_quoted_text(boundary_cid) is Some(boundary) &&
    update_quoted_text(effect_id) is Some(effect) &&
    update_quoted_text(mapping_cid) is Some(mapping) else {
    return None
  }
  let (value, body_value) = if explicit_null {
    let literal = { bytes: 4L, utf16_units: 4L, }
    (literal, literal)
  } else {
    (value, update_quote_inside_body(text, value))
  }
  let body = field_key.append(value).ascii(3L) // Braces and colon.
  let quoted_body = update_quote_inside_body(field, field_key)
    .append(body_value)
    .ascii(5L) // Braces, colon and outer quotes.
  let request = identity_key
    .append(identity)
    .append(field_key)
    .append(value)
    .append(quoted_body)
    .ascii(13L) // Seven punctuation bytes and six for `"body"`.
  let request_cid_preimage = request.append(domain).append(boundary).ascii(26L) // Four punctuation bytes and `"version"`, `"boundaryCid"`.
  let recovery = boundary
    .append(effect)
    .append(mapping)
    .append(identity)
    .append(value)
    .ascii(9L + update_member_digits(member_index))
  Some({ body, request, request_cid_preimage, recovery, })
}

///|
/// Enforce independent output bounds before constructing the first wire. The
/// capacities for output records, serializers and hash scratch are separate.
pub fn installed_update_text_wire_fits(
  extents : InstalledUpdateTextWireExtents,
  max_body_bytes : Int64,
  max_request_bytes : Int64,
  max_request_cid_preimage_bytes : Int64,
  max_recovery_bytes : Int64,
) -> Bool {
  extents.body.bytes <= max_body_bytes &&
  extents.request.bytes <= max_request_bytes &&
  extents.request_cid_preimage.bytes <= max_request_cid_preimage_bytes &&
  extents.recovery.bytes <= max_recovery_bytes
}

///|
/// Wire returned by the selected standard UPDATE constructor. It conveys the
/// physical JSON body and the exact original logical Request CID only.
pub(all) struct InstalledUpdateTextRequest {
  body : String
  request_cid : String
}

///|
/// These are checked Mapping field names for the selected original. The
/// constructor also refuses collisions with fixed Request/CID members.
fn installed_update_text_field(field : String) -> Bool {
  match field {
    "" | "body" | "version" | "boundaryCid" => false
    _ => true
  }
}

///|
fn installed_update_text_value(
  writer : @encode.Writer,
  text : String,
  explicit_null : Bool,
) -> Unit raise @encode.EncodeFailure {
  if explicit_null {
    @encode.null_value(writer)
  } else {
    @encode.string_value(writer, text)
  }
}

///|
/// Check the request and CID sizes against their own selected limits before
/// either writer starts. Only the rendered body remains when computing the CID.
/// The original member witness has its own later construction phase.
pub fn construct_installed_update_text_request(
  identity_field : String,
  field : String,
  target : String,
  text : String,
  request_domain : String,
  boundary_cid : String,
  max_body_bytes : Int,
  max_request_bytes : Int,
  max_request_cid_preimage_bytes : Int,
  explicit_null? : Bool = false,
) -> InstalledUpdateTextRequest? {
  guard identity_field != field &&
    installed_update_text_field(identity_field) &&
    installed_update_text_field(field) &&
    installed_update_text_wire_extents(
      identity_field,
      field,
      target,
      text,
      request_domain,
      boundary_cid,
      "",
      0,
      "",
      explicit_null~,
    )
    is Some(extents) &&
    extents.body.bytes <= max_body_bytes.to_int64() &&
    extents.request.bytes <= max_request_bytes.to_int64() &&
    extents.request_cid_preimage.bytes <=
    max_request_cid_preimage_bytes.to_int64() else {
    return None
  }
  try {
    let output = @encode.writer(extents.body.bytes.to_int(), 2, 1)
    @encode.begin_object(output)
    @encode.key(output, field)
    installed_update_text_value(output, text, explicit_null)
    @encode.end_object(output)
    let body = @encode.finish(output)
    let entries = [
      ("body", body),
      ("boundaryCid", boundary_cid),
      (identity_field, target),
      (field, text),
      ("version", request_domain),
    ]
    entries.sort_by((left, right) => @canonical.compare_utf16(left.0, right.0))
    let hasher = @encode.hashing_writer(
      extents.request_cid_preimage.bytes.to_int(),
      6,
      1,
    )
    @encode.begin_object(hasher)
    for (name, value) in entries {
      @encode.key(hasher, name)
      installed_update_text_value(hasher, value, explicit_null && name == field)
    }
    @encode.end_object(hasher)
    Some({ body, request_cid: "sha256:" + @encode.finish_hash(hasher), })
  } catch {
    _ => None
  }
}

///|
/// The historical recovery encoding is an independent selected member writer.
/// Restoring its exact text/CID from the original Preview does not grant write
/// permission or attest that an earlier request was or was not sent.
pub fn construct_installed_update_text_recovery(
  boundary_cid : String,
  effect_id : String,
  member_index : Int,
  mapping_cid : String,
  target : String,
  text : String,
  max_recovery_bytes : Int,
  explicit_null? : Bool = false,
) -> (String, String)? {
  guard installed_update_text_wire_extents(
      "",
      "",
      target,
      text,
      "",
      boundary_cid,
      effect_id,
      member_index,
      mapping_cid,
      explicit_null~,
    )
    is Some(original) &&
    original.recovery.bytes <= max_recovery_bytes.to_int64() else {
    return None
  }
  try {
    let output = @encode.writer(original.recovery.bytes.to_int(), 8, 2)
    @encode.begin_array(output)
    @encode.string_value(output, boundary_cid)
    @encode.begin_array(output)
    @encode.string_value(output, effect_id)
    @encode.number_value(output, member_index.to_double())
    @encode.string_value(output, mapping_cid)
    @encode.end_array(output)
    @encode.string_value(output, target)
    installed_update_text_value(output, text, explicit_null)
    @encode.end_array(output)
    let wire = @encode.finish(output)
    match @sha.text_hex(wire) {
      Ok(digest) => Some((wire, "sha256:" + digest))
      Err(_) => None
    }
  } catch {
    _ => None
  }
}

///|
/// The selected physical key admits only unescaped ASCII. The largest text
/// cell is a control which needs six units first and seven inside the body
/// String. Request CID has the same variable terms as the logical Request.
/// Keep this constructor quote independent of the physical HTTP cap.
pub fn installed_update_text_request_bounds(
  identity_field : String,
  field : String,
  request_domain : String,
  boundary_cid : String,
  target_ascii_units : Int,
  text_utf16_units : Int,
) -> (Int, Int, Int)? {
  guard target_ascii_units >= 0 &&
    text_utf16_units >= 0 &&
    installed_update_text_wire_extents(
      identity_field, field, "", "", request_domain, boundary_cid, "", 0, "",
    )
    is Some(empty) else {
    return None
  }
  let text = text_utf16_units.to_int64()
  let request_addition = target_ascii_units.to_int64() + 13L * text
  let body = empty.body.bytes + 6L * text
  let request = empty.request.bytes + request_addition
  let preimage = empty.request_cid_preimage.bytes + request_addition
  if preimage > 2147483647L {
    None
  } else {
    Some((body.to_int(), request.to_int(), preimage.to_int()))
  }
}

///|
/// These writers return their original wire/CID on the existing row or member
/// holder. The text emitter and hash writer complete synchronously in order.
/// The hash preimage is streamed, so no second full preimage String is live.
fn installed_update_text_output_capacity(
  output_bytes : Int,
  nodes : Int,
  depth : Int,
  hash_nodes : Int,
  hash_depth : Int,
  row_request : Bool,
) -> @execution.ExecutionCapacity? {
  guard @encode.text_writer_construction_inventory(output_bytes, nodes, depth)
    is Some(output) &&
    @encode.hash_writer_construction_inventory(hash_nodes, hash_depth)
    is Some(hash) else {
    return None
  }
  // Bridge return, Host wrapper and retained original. A row also owns the
  // logical request, RequestFacts and WeakMap entry on that original child.
  let retained : @execution.PreparationRepresentationUnits = {
    record_headers: if row_request {
      9L
    } else {
      5L
    },
    reference_slots: if row_request {
      20L
    } else {
      12L
    },
    scalar_words: if row_request {
      11L
    } else {
      6L
    },
    owned_utf16_units: output_bytes.to_int64() + 71L,
    owned_wire_bytes: 0L,
  }
  // The request hash uses one five-entry array of borrowed immutable Strings
  // and five pairs, sorted in place by the original canonical comparator.
  let hash_headers = if row_request { 7L } else { 0L }
  let hash_references = if row_request { 16L } else { 0L }
  let hash_words = if row_request { 10L } else { 0L }
  @execution.preparation_execution_capacity({
    retained,
    workspace: {
      record_headers: Int64::max(
        output.record_headers,
        hash.record_headers + hash_headers,
      ),
      reference_slots: Int64::max(
        output.reference_slots,
        hash.reference_slots + hash_references,
      ),
      scalar_words: Int64::max(
        output.scalar_words,
        hash.scalar_words + hash_words,
      ),
      owned_utf16_units: Int64::max(
        output.owned_utf16_units,
        hash.owned_utf16_units,
      ),
      owned_wire_bytes: hash.owned_wire_bytes,
    },
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  })
}

///|
/// Preserve the existing bounded provider response parser, encoding and CID
/// scratch on its physical child. Common does not interpret provider evidence.
fn installed_update_text_observation_capacity(
  bytes : Int,
) -> @execution.ExecutionCapacity? {
  guard @source.json_literal_construction_extent(bytes, bytes, bytes)
    is Some(forest) else {
    return None
  }
  let wire = bytes.to_int64()
  @execution.preparation_execution_capacity({
    retained: {
      record_headers: forest.record_headers,
      reference_slots: forest.reference_slots,
      scalar_words: forest.scalar_words,
      owned_utf16_units: forest.owned_utf16_units + wire,
      owned_wire_bytes: 0L,
    },
    workspace: {
      record_headers: 0L,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: wire,
      owned_wire_bytes: 2L * wire,
    },
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  })
}

///|
/// The described-effect composer uses its existing per-row request and the
/// two physical response roles. The same capture/recovery member retains the
/// original witness; no provider supplies or composes layout arithmetic.
pub fn installed_update_text_recipe_profiles(
  body_bytes : Int,
  request_bytes : Int,
  preimage_bytes : Int,
  recovery_bytes : Int,
  target_response_bytes : Int,
  write_response_bytes : Int,
) -> (
  Array[
    (@execution.ExecutionCapacity, @source.ParseLimits?, @source.ParseLimits?),
  ],
  Array[@execution.ExecutionCapacity],
)? {
  guard body_bytes > 0 &&
    request_bytes > body_bytes &&
    preimage_bytes > request_bytes &&
    recovery_bytes > 0 &&
    target_response_bytes > 0 &&
    write_response_bytes > 0 &&
    installed_update_text_output_capacity(body_bytes, 2, 1, 6, 1, true)
    is Some(request) &&
    installed_update_text_output_capacity(recovery_bytes, 8, 2, 0, 0, false)
    is Some(recovery) &&
    installed_update_text_observation_capacity(target_response_bytes)
    is Some(target) &&
    installed_update_text_observation_capacity(write_response_bytes)
    is Some(write) else {
    return None
  }
  // Warm Request has its own row child. The existing cold composer adds one
  // rebuilt row Request to this member's independent recovery operation.
  let empty = @execution.execution_capacity(0L, 0L).unwrap()
  Some(
    (
      [
        (request, None, None),
        (request, None, None),
        (write, None, None),
        (target, None, None),
      ],
      [recovery, empty, empty],
    ),
  )
}
