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
) -> Result[(String, Int), PhysicalManifestIssue] {
  let nodes = manifest.chunks.length() * 4 + 16
  let writer = @encode.hashing_writer(max_manifest_bytes, nodes, 3) catch {
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
    let (hex, bytes, _) = @encode.finish_hash_usage(writer)
    Ok(("sha256:" + hex, bytes))
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
  let (manifest_cid, metadata_bytes) = match
    emit_manifest(pending, max_manifest_bytes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({ ..pending, manifest_cid, metadata_bytes, })
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
