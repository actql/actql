///|
/// Canonical create-row ordering is shared Effect meaning. The source index
/// lets the physical caller reorder its exact request owners to match the
/// Preview without treating equal payload rows as one operation.
pub fn derive_effect_create_row_inventory(
  after_wires : Array[String],
  max_rows : Int,
  max_total_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Array[(Int, String)], EffectPreviewIdentityIssue] {
  if max_rows < 0 ||
    max_total_bytes < 1 ||
    max_nodes < 1 ||
    max_depth < 2 ||
    after_wires.length() > max_rows {
    return Err(Encoding)
  }
  let mut remaining_bytes = max_total_bytes
  let contents : Array[(String, Int)] = []
  for index, wire in after_wires {
    if wire.length() > remaining_bytes {
      return Err(Encoding)
    }
    let bytes = @utf8.encode(wire)
    if bytes.length() > remaining_bytes {
      return Err(Encoding)
    }
    remaining_bytes -= bytes.length()
    let parsed = match
      @source.parse_json(wire, {
        max_input_bytes: bytes.length(),
        max_nodes,
        max_depth,
      }) {
      Ok(value) => value
      Err(_) => return Err(InvalidMember)
    }
    let after = @json.from_source(parsed, max_nodes, max_depth, bytes.length()) catch {
      _ => return Err(InvalidMember)
    }
    guard @json.object_field(after, "state") is Some(@json.String("present")) &&
      @json.object_field(after, "value") is Some(value) &&
      @json.object_field_count(value) is Some(_) else {
      return Err(InvalidMember)
    }
    let writer = @encode.hashing_writer(max_total_bytes, max_nodes, max_depth) catch {
      _ => return Err(Encoding)
    }
    let digest = try {
      @encode.begin_object(writer)
      @encode.key(writer, "value")
      @json.emit_value(after, writer)
      @encode.key(writer, "version")
      @encode.string_value(writer, "actql-effect-content-row/0.1")
      @encode.end_object(writer)
      @encode.finish_hash(writer)
    } catch {
      _ => return Err(Encoding)
    }
    contents.push(("sha256:" + digest, index))
  }
  contents.sort_by((left, right) => {
    let order = @canonical.compare_utf16(left.0, right.0)
    if order == 0 {
      left.1.compare(right.1)
    } else {
      order
    }
  })
  let result : Array[(Int, String)] = []
  let mut previous = ""
  let mut occurrence = 0
  for (content_cid, source_index) in contents {
    if content_cid == previous {
      occurrence += 1
    } else {
      previous = content_cid
      occurrence = 0
    }
    let writer = @encode.writer(max_total_bytes, max_nodes, max_depth) catch {
      _ => return Err(Encoding)
    }
    let identity = try {
      @encode.begin_object(writer)
      @encode.key(writer, "content_cid")
      @encode.string_value(writer, content_cid)
      @encode.key(writer, "occurrence")
      @encode.number_value(writer, occurrence.to_double())
      @encode.end_object(writer)
      @encode.finish(writer)
    } catch {
      _ => return Err(Encoding)
    }
    result.push((source_index, identity))
  }
  Ok(result)
}
