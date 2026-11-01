///|
/// Integrity of the exact retained codec wire, never execution authority.
pub fn client_task_material_original_cid(
  wire : String,
) -> Result[String, ClientJournalEncodingIssue] {
  let bytes = @utf8.encode(wire)
  if bytes.length() == 0 ||
    bytes.length() > @remote.REMOTE_RUN_MATERIALS_MAX_BYTES {
    return Err(CapacityExceeded)
  }
  Ok("sha256:" + @sha.hex(bytes))
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
  match client_task_material_original_cid(wire) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let bytes = @utf8.encode(wire)
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
  guard client_task_material_original_cid(wire) is Ok(actual) && actual == cid else {
    return Err(custody_lost)
  }
  let expected = match client_task_material_original_chunks(key, wire) {
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
  Ok(wire)
}
