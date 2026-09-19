///|
/// Portable admission failures for an ordered physical representation.
/// Filesystem ownership and physical reads remain adapter responsibilities.
pub(all) enum PhysicalManifestIssue {
  InvalidManifest
  ManifestLimit
  CountOverflow
  RowCountMismatch
} derive(Eq, Debug)

///|
/// One occurrence in the ordered physical representation. Equal chunk CIDs
/// may occur more than once; their positions remain semantically significant.
pub(all) struct PhysicalChunk {
  cid : String
  byte_length : Int64
  row_count : Int
}

///|
/// The admitted manifest is the portable authority for canonical identity and
/// bounded aggregate facts. It grants no execution or publication authority.
pub(all) struct PhysicalManifest {
  schema_contract_cid : String
  view_contract_cid : String
  codec_contract_cid : String
  row_count : Int
  chunks : Array[PhysicalChunk]
  manifest_cid : String
  metadata_bytes : Int
  referenced_bytes : Int64
}

///|
const MAX_SAFE_JSON_INTEGER : Int64 = 9007199254740991L

///|
fn valid_cid(value : String) -> Bool {
  if value.length() != 71 || !value.has_prefix("sha256:") {
    return false
  }
  for index = 7; index < 71; index = index + 1 {
    let unit = value[index].to_int()
    if !((unit >= 48 && unit <= 57) || (unit >= 97 && unit <= 102)) {
      return false
    }
  }
  true
}

///|
fn safe_json_count(value : Int64) -> Bool {
  value >= 0L && value <= MAX_SAFE_JSON_INTEGER
}

///|
fn emit_manifest(
  manifest : PhysicalManifest,
  max_manifest_bytes : Int,
) -> Result[(String, String, Int), PhysicalManifestIssue] {
  let nodes = manifest.chunks.length() * 4 + 16
  let writer = @encode.writer(max_manifest_bytes, nodes, 3) catch {
    _ => return Err(ManifestLimit)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "chunks")
    @encode.begin_array(writer)
    for chunk in manifest.chunks {
      @encode.begin_object(writer)
      @encode.key(writer, "byte_length")
      @encode.number_value(writer, chunk.byte_length.to_double())
      @encode.key(writer, "cid")
      @encode.string_value(writer, chunk.cid)
      @encode.key(writer, "row_count")
      @encode.number_value(writer, chunk.row_count.to_double())
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    @encode.key(writer, "codec_contract_cid")
    @encode.string_value(writer, manifest.codec_contract_cid)
    @encode.key(writer, "row_count")
    @encode.number_value(writer, manifest.row_count.to_double())
    @encode.key(writer, "schema_contract_cid")
    @encode.string_value(writer, manifest.schema_contract_cid)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-managed-physical-manifest/0.1")
    @encode.key(writer, "view_contract_cid")
    @encode.string_value(writer, manifest.view_contract_cid)
    @encode.end_object(writer)
    let body = @encode.finish(writer)
    let hex = match @sha256.text_hex(body) {
      Ok(value) => value
      Err(_) => return Err(InvalidManifest)
    }
    Ok((body, "sha256:" + hex, body.length()))
  } catch {
    @encode.OutputLimit => Err(ManifestLimit)
    _ => Err(InvalidManifest)
  }
}

///|
/// Admit one complete ordered physical manifest. The canonical identity is
/// generated here so environment adapters cannot substitute key order,
/// aggregate counts, or a transport hash for the common physical identity.
pub fn admit(
  version : String,
  schema_contract_cid : String,
  view_contract_cid : String,
  codec_contract_cid : String,
  row_count : Int,
  chunk_cids : Array[String],
  chunk_byte_lengths : Array[Int64],
  chunk_row_counts : Array[Int],
  max_chunks : Int,
  max_manifest_bytes : Int,
  max_referenced_bytes : Int64,
) -> Result[PhysicalManifest, PhysicalManifestIssue] {
  if version != "actql-managed-physical-manifest/0.1" ||
    max_chunks < 0 ||
    max_manifest_bytes < 0 ||
    max_referenced_bytes < 0L ||
    row_count < 0 ||
    !valid_cid(schema_contract_cid) ||
    !valid_cid(view_contract_cid) ||
    !valid_cid(codec_contract_cid) ||
    chunk_cids.length() != chunk_byte_lengths.length() ||
    chunk_cids.length() != chunk_row_counts.length() {
    return Err(InvalidManifest)
  }
  if chunk_cids.length() > max_chunks {
    return Err(ManifestLimit)
  }
  let mut rows = 0L
  let mut referenced = 0L
  let chunks : Array[PhysicalChunk] = []
  for index, cid in chunk_cids {
    let bytes = chunk_byte_lengths[index]
    let chunk_rows = chunk_row_counts[index]
    if !valid_cid(cid) || !safe_json_count(bytes) || chunk_rows < 0 {
      return Err(InvalidManifest)
    }
    let chunk_rows64 = chunk_rows.to_int64()
    if rows > MAX_SAFE_JSON_INTEGER - chunk_rows64 ||
      referenced > MAX_SAFE_JSON_INTEGER - bytes {
      return Err(CountOverflow)
    }
    rows += chunk_rows64
    referenced += bytes
    if referenced > max_referenced_bytes {
      return Err(ManifestLimit)
    }
    chunks.push({ cid, byte_length: bytes, row_count: chunk_rows, })
  }
  if rows != row_count.to_int64() {
    return Err(RowCountMismatch)
  }
  let pending : PhysicalManifest = {
    schema_contract_cid,
    view_contract_cid,
    codec_contract_cid,
    row_count,
    chunks,
    manifest_cid: "pending",
    metadata_bytes: 0,
    referenced_bytes: referenced,
  }
  let (_, manifest_cid, metadata_bytes) = match
    emit_manifest(pending, max_manifest_bytes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({ ..pending, manifest_cid, metadata_bytes, })
}

///|
priv suberror PhysicalManifestDecodeStop {
  PhysicalManifestDecodeStop
}

///|
fn[T] manifest_decoded(
  value : Result[T, @decode.Issue],
) -> T raise PhysicalManifestDecodeStop {
  match value {
    Ok(result) => result
    Err(_) => raise PhysicalManifestDecodeStop
  }
}

///|
fn manifest_text(
  object : @decode.ObjectView,
  key : String,
) -> String raise PhysicalManifestDecodeStop {
  manifest_decoded(
    @decode.text(manifest_decoded(@decode.required(object, key))),
  )
}

///|
fn manifest_count64(
  object : @decode.ObjectView,
  key : String,
) -> Int64 raise PhysicalManifestDecodeStop {
  let value = manifest_decoded(
    @decode.safe_integer(manifest_decoded(@decode.required(object, key))),
  )
  if value < 0L || value > MAX_SAFE_JSON_INTEGER {
    raise PhysicalManifestDecodeStop
  }
  value
}

///|
fn manifest_count(
  object : @decode.ObjectView,
  key : String,
) -> Int raise PhysicalManifestDecodeStop {
  let value = manifest_count64(object, key)
  if value > 2147483647L {
    raise PhysicalManifestDecodeStop
  }
  value.to_int()
}

///|
fn rebuild_manifest(
  manifest : PhysicalManifest,
) -> Result[PhysicalManifest, PhysicalManifestIssue] {
  let chunks = manifest.chunks
  let rebuilt = admit(
    "actql-managed-physical-manifest/0.1",
    manifest.schema_contract_cid,
    manifest.view_contract_cid,
    manifest.codec_contract_cid,
    manifest.row_count,
    chunks.map(chunk => chunk.cid),
    chunks.map(chunk => chunk.byte_length),
    chunks.map(chunk => chunk.row_count),
    chunks.length(),
    manifest.metadata_bytes,
    manifest.referenced_bytes,
  )
  match rebuilt {
    Ok(value) =>
      if value.manifest_cid == manifest.manifest_cid &&
        value.metadata_bytes == manifest.metadata_bytes &&
        value.referenced_bytes == manifest.referenced_bytes {
        Ok(value)
      } else {
        Err(InvalidManifest)
      }
    Err(issue) => Err(issue)
  }
}

///|
/// Return canonical wire only for a currently valid admitted manifest.
pub fn manifest_json(
  manifest : PhysicalManifest,
) -> Result[String, PhysicalManifestIssue] {
  let admitted = match rebuild_manifest(manifest) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match emit_manifest(admitted, admitted.metadata_bytes) {
    Ok((body, cid, bytes)) =>
      if cid == admitted.manifest_cid && bytes == admitted.metadata_bytes {
        Ok(body)
      } else {
        Err(InvalidManifest)
      }
    Err(issue) => Err(issue)
  }
}

///|
/// Re-admit canonical manifest wire received across a process or Site boundary.
/// The claimed CID is checked independently from transport framing.
pub fn admit_json(
  body : String,
  claimed_cid : String,
  max_chunks : Int,
  max_manifest_bytes : Int,
  max_referenced_bytes : Int64,
) -> Result[PhysicalManifest, PhysicalManifestIssue] {
  if max_chunks < 0 ||
    max_chunks > 536870907 ||
    max_manifest_bytes < 0 ||
    max_referenced_bytes < 0L ||
    body.length() > max_manifest_bytes {
    return Err(ManifestLimit)
  }
  try {
    let bytes = @utf8.encode(body)
    let max_nodes = max_chunks * 4 + 16
    let node = match
      @source.parse_json_bytes(bytes, {
        max_input_bytes: max_manifest_bytes,
        max_nodes,
        max_depth: 3,
      }) {
      Ok(value) => value
      Err(_) => raise PhysicalManifestDecodeStop
    }
    let cursor = manifest_decoded(
      @decode.admit(node, {
        max_nodes,
        max_depth: 3,
        max_string_bytes: max_manifest_bytes,
        max_total_string_bytes: max_manifest_bytes,
      }),
    )
    let object = manifest_decoded(
      @decode.closed_object(cursor, [
        "chunks", "codec_contract_cid", "row_count", "schema_contract_cid", "version",
        "view_contract_cid",
      ]),
    )
    let chunks_cursor = manifest_decoded(@decode.required(object, "chunks"))
    let chunk_count = match @decode.array_length(chunks_cursor) {
      Some(value) => value
      None => raise PhysicalManifestDecodeStop
    }
    if chunk_count > max_chunks {
      return Err(ManifestLimit)
    }
    let chunk_cids : Array[String] = []
    let chunk_byte_lengths : Array[Int64] = []
    let chunk_row_counts : Array[Int] = []
    for index in 0..<chunk_count {
      let chunk_cursor = match @decode.element_at(chunks_cursor, index) {
        Some(value) => value
        None => raise PhysicalManifestDecodeStop
      }
      let chunk = manifest_decoded(
        @decode.closed_object(chunk_cursor, ["byte_length", "cid", "row_count"]),
      )
      chunk_cids.push(manifest_text(chunk, "cid"))
      chunk_byte_lengths.push(manifest_count64(chunk, "byte_length"))
      chunk_row_counts.push(manifest_count(chunk, "row_count"))
    }
    let admitted = match
      admit(
        manifest_text(object, "version"),
        manifest_text(object, "schema_contract_cid"),
        manifest_text(object, "view_contract_cid"),
        manifest_text(object, "codec_contract_cid"),
        manifest_count(object, "row_count"),
        chunk_cids,
        chunk_byte_lengths,
        chunk_row_counts,
        max_chunks,
        max_manifest_bytes,
        max_referenced_bytes,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let canonical = match manifest_json(admitted) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if canonical != body || admitted.manifest_cid != claimed_cid {
      Err(InvalidManifest)
    } else {
      Ok(admitted)
    }
  } catch {
    PhysicalManifestDecodeStop => Err(InvalidManifest)
  }
}

///|
pub fn projection(manifest : PhysicalManifest) -> Array[String] {
  [
    manifest.manifest_cid,
    manifest.metadata_bytes.to_string(),
    manifest.referenced_bytes.to_string(),
    manifest.row_count.to_string(),
  ]
}
