///|
/// Integrity of the exact retained codec wire, never execution authority.
pub fn client_task_material_original_cid(
  wire : String,
) -> Result[String, ClientJournalEncodingIssue] {
  task_material_original_cid_bytes(@utf8.encode(wire))
}

///|
// The SAME raw UTF8/SHA256 identity domain. This private pure port only lets
// focused controls count actual work; public callers always use the real hash.
fn task_material_original_cid_bytes(
  bytes : Bytes,
  digest? : (Bytes) -> String = @sha.hex,
) -> Result[String, ClientJournalEncodingIssue] {
  if bytes.length() == 0 ||
    bytes.length() > @remote.REMOTE_RUN_MATERIALS_MAX_BYTES {
    return Err(CapacityExceeded)
  }
  Ok("sha256:" + digest(bytes))
}

///|
/// Preserve the Native physical row cap and the existing logical material
/// cap. UTF-8 characters remain intact; at most three chunks are possible.
pub fn client_task_material_original_chunks(
  key : String,
  wire : String,
) -> Result[Array[(String, String)], ClientJournalEncodingIssue] {
  if !valid_client_request_cid(key) {
    return Err(Encoding)
  }
  task_material_original_chunk_bytes(key, @utf8.encode(wire))
}

///|
// Reuse this reader's already encoded bytes. Chunk construction needs the
// original key/extent/UTF8 seam checks, not another discarded whole-wire hash.
fn task_material_original_chunk_bytes(
  key : String,
  bytes : Bytes,
) -> Result[Array[(String, String)], ClientJournalEncodingIssue] {
  if !valid_client_request_cid(key) {
    return Err(Encoding)
  }
  if bytes.length() == 0 ||
    bytes.length() > @remote.REMOTE_RUN_MATERIALS_MAX_BYTES {
    return Err(CapacityExceeded)
  }
  let chunks : Array[(String, String)] = []
  let mut start = 0
  while start < bytes.length() {
    let mut end = Int::min(start + 131072, bytes.length())
    // A UTF-8 continuation byte cannot begin the next physical row.
    while end < bytes.length() &&
          bytes[end].to_int() >= 128 &&
          bytes[end].to_int() <= 191 {
      end -= 1
    }
    let body = @utf8.decode(bytes[start:end]) catch {
      _ => return Err(Encoding)
    }
    if chunks.length() == 3 {
      return Err(CapacityExceeded)
    }
    chunks.push((key + ":" + chunks.length().to_string(), body))
    start = end
  }
  Ok(chunks)
}

///|
/// Read only the fixed bounded original chunks from this same Store snapshot.
/// A pointer without its exact immutable chunks is lost custody, never a
/// request to regenerate input or to backfill an already admitted Run.
pub fn[E] read_client_task_material_original(
  key : String,
  cid : String,
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  custody_lost : E,
) -> Result[String, E] {
  read_task_material_original_details(key, cid, read, custody_lost).map(value => {
    value.0
  })
}

///|
// One synchronous fresh read returns its ALREADY checked canonical chunks.
// This is transient DATA only: no inventory/current/authority cache or new
// reader lifetime. Physical reads and their supplied fences remain unchanged.
fn[E] read_task_material_original_details(
  key : String,
  cid : String,
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  custody_lost : E,
  digest? : (Bytes) -> String = @sha.hex,
) -> Result[(String, Array[(String, String)]), E] {
  let mut wire = ""
  let mut total = 0
  let mut ended = false
  let observed : Array[String] = []
  for index in 0..<4 {
    let chunk_key = key + ":" + index.to_string()
    match read("client_task_run_materials", chunk_key) {
      Err(issue) => return Err(issue)
      Ok(None) => ended = true
      Ok(Some(row)) => {
        if ended ||
          index == 3 ||
          row.key != chunk_key ||
          row.revision != 0L ||
          row.body.length() == 0 ||
          row.body.length() > 131072 {
          return Err(custody_lost)
        }
        total += row.body.length()
        if total > @remote.REMOTE_RUN_MATERIALS_MAX_BYTES {
          return Err(custody_lost)
        }
        let body = @utf8.decode(row.body) catch {
          _ => return Err(custody_lost)
        }
        wire += body
        observed.push(body)
      }
    }
  }
  let bytes = @utf8.encode(wire)
  guard task_material_original_cid_bytes(bytes, digest~) is Ok(actual) &&
    actual == cid else {
    return Err(custody_lost)
  }
  let expected = match task_material_original_chunk_bytes(key, bytes) {
    Ok(value) => value
    Err(_) => return Err(custody_lost)
  }
  if expected.length() != observed.length() {
    return Err(custody_lost)
  }
  for index in 0..<expected.length() {
    if expected[index].1 != observed[index] {
      return Err(custody_lost)
    }
  }
  Ok((wire, expected))
}
