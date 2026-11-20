///|
/// Pure material codec original. The owner parameter is retained DATA only;
/// it does not certify a Plan/wire relationship or authorize execution. The
/// enclosing Local Run capture and its original-purpose checks own that join.
pub struct ClientTaskMaterialsOriginal[Plan] {
  plan : Plan
  wire : String
  cid : String
  chunks : Array[(String, String)]
  publication_policy_originals : String
}

///|
/// Preserve the existing capture order: extent/hash/chunks, then the original
/// policy constructor. The synchronous callback is never retained.
pub fn[Plan, E] capture_client_task_materials_original(
  plan : Plan,
  key : String,
  wire : String,
  policy : () -> Result[String, E],
  encoding_failure : (ClientJournalEncodingIssue) -> E,
) -> Result[ClientTaskMaterialsOriginal[Plan], E] {
  let cid = match client_task_material_original_cid(wire) {
    Ok(value) => value
    Err(issue) => return Err(encoding_failure(issue))
  }
  let chunks = match client_task_material_original_chunks(key, wire) {
    Ok(value) => value
    Err(issue) => return Err(encoding_failure(issue))
  }
  let publication_policy_originals = match policy() {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({ plan, wire, cid, chunks, publication_policy_originals, })
}

///|
pub fn[Plan] client_task_materials_original_plan(
  original : ClientTaskMaterialsOriginal[Plan],
) -> Plan {
  original.plan
}

///|
pub fn[Plan] client_task_materials_original_cid(
  original : ClientTaskMaterialsOriginal[Plan],
) -> String {
  original.cid
}

///|
pub fn[Plan] client_task_materials_original_chunks(
  original : ClientTaskMaterialsOriginal[Plan],
) -> Array[(String, String)] {
  original.chunks.copy()
}

///|
pub fn[Plan] client_task_materials_original_policy(
  original : ClientTaskMaterialsOriginal[Plan],
) -> String {
  original.publication_policy_originals
}

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
    while end < bytes.length() && task_material_continuation(bytes[end]) {
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
fn task_material_continuation(value : Byte) -> Bool {
  value.to_int() >= 128 && value.to_int() <= 191
}

///|
// Called after strict UTF-8 decoding. A nonfinal chunk must leave no room
// for the next complete scalar, which is exactly where the splitter stops.
fn task_material_maximal_chunk(length : Int, next : Bytes) -> Bool {
  let available = 131072 - length
  if available >= 4 || available >= next.length() {
    return false
  }
  for offset in 1..<(available + 1) {
    if !task_material_continuation(next[offset]) {
      return false
    }
  }
  true
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
  let original : ClientTaskMaterialsOriginal[Unit]? = None
  read_task_material_original_details_with_original(
    key,
    cid,
    read,
    custody_lost,
    original,
    digest~,
  )
}

///|
fn[Plan, E] read_task_material_original_details_with_original(
  key : String,
  cid : String,
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  custody_lost : E,
  original : ClientTaskMaterialsOriginal[Plan]?,
  digest? : (Bytes) -> String = @sha.hex,
  saved_wire? : String? = None,
) -> Result[(String, Array[(String, String)]), E] {
  let mut wire = ""
  let mut total = 0
  let mut ended = false
  let mut previous_length = 131072
  let mut canonical = saved_wire is Some(_)
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
        if canonical {
          canonical = task_material_maximal_chunk(previous_length, row.body)
          previous_length = row.body.length()
        }
        wire += body
        observed.push(body)
      }
    }
  }
  if original is Some(original) &&
    original.cid == cid &&
    original.wire == wire &&
    original.chunks.length() == observed.length() {
    let mut same = true
    for index in 0..<observed.length() {
      if original.chunks[index].0 != key + ":" + index.to_string() ||
        original.chunks[index].1 != observed[index] {
        same = false
      }
    }
    if same {
      return Ok((original.wire, original.chunks))
    }
  }
  // Exact validated UTF-8 and maximal chunk boundaries fix the physical
  // material wire and its canonical partition. Copy only the same bounded
  // chunk descriptors the complete validator returns, sharing the Strings.
  if canonical &&
    !observed.is_empty() &&
    valid_client_request_cid(key) &&
    saved_wire is Some(original_wire) &&
    wire == original_wire {
    let exact : Array[(String, String)] = []
    for index in 0..<observed.length() {
      exact.push((key + ":" + index.to_string(), observed[index]))
    }
    return Ok((original_wire, exact))
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

///|
// Sole production caller supplies the wire already checked under the same
// Saved snapshot inspection CID. Strict UTF-8 and exact wire equality fix
// every byte, and the original greedy boundaries fix the entire partition.
// No second backing for old chunks survives the read. On a miss, validate
// the fresh observation without replacing the first physical result.
fn[E] read_saved_task_material_original(
  key : String,
  cid : String,
  original_wire : String,
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  custody_lost : E,
  digest? : (Bytes) -> String = @sha.hex,
) -> Result[String, E] {
  let original : ClientTaskMaterialsOriginal[Unit]? = None
  read_task_material_original_details_with_original(
    key,
    cid,
    read,
    custody_lost,
    original,
    digest~,
    saved_wire=Some(original_wire),
  ).map(value => value.0)
}

///|
/// Reobserve original physical material with an existing pure codec original.
/// A foreign/changed match falls through the unchanged full validator. No
/// current, inventory, permission or physical ACK is retained in this value.
pub fn[Plan, E] read_client_task_material_with_original(
  key : String,
  cid : String,
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  custody_lost : E,
  original : ClientTaskMaterialsOriginal[Plan]?,
) -> Result[String, E] {
  read_task_material_original_details_with_original(
    key, cid, read, custody_lost, original,
  ).map(value => value.0)
}
