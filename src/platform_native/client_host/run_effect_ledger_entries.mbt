///|
let effect_ledger_entry_table = "client_effect_ledger_entries"

///|
// All components are admitted same-Run SHA-256 CIDs. The ordered entry CIDs
// live in the Checkpoint body and are independently confirmed by custody.
fn native_effect_ledger_entry_key(
  scope : String,
  checkpoint : String,
  entry : String,
) -> String {
  scope + "/" + checkpoint + "/" + entry
}

///|
fn prepare_native_effect_ledger_entry_key(
  reserve : ((Int64, Int64, Int64) -> Result[Unit, NativeClientRunJournalIssue])?,
) -> Result[Unit, NativeClientRunJournalIssue] {
  guard @execution.preparation_representation_cost({
      record_headers: 6L,
      reference_slots: 4L,
      scalar_words: 4L,
      // Prefix plus completed key, including the two separators in each.
      owned_utf16_units: 2L * (3L * 71L + 2L),
      owned_wire_bytes: 0L,
    })
    is Some(peak) else {
    return Err(CapacityExceeded)
  }
  match reserve {
    Some(quote) => quote(0L, peak, 8L + 2L * (3L * 71L + 3L))
    None => Ok(())
  }
}

///|
// Same bounded original admission, including invalid wires. The UTF-8 Bytes,
// returned entry/Strings, normalizing Source parse, CanonicalValue and text
// and hash emission are charged under the single existing Read.
fn native_effect_ledger_entry_admission_quote(
  bytes : Int,
  limits : @checkpoint.WireLimits,
) -> (Int64, Int64, Int64)? {
  if bytes <= 0 || bytes > limits.max_wire_bytes {
    return None
  }
  let n = limits.max_nodes
  let d = limits.max_depth
  guard @source.json_construction_extent(bytes, n, d, normalize_keys=true)
    is Some(parser) &&
    @canonical.source_conversion_construction_extent(n, n, n, n, d, bytes)
    is Some(tree) &&
    @encode.text_writer_construction_inventory(bytes, n, d) is Some(text) &&
    @encode.hash_writer_construction_inventory(n, d) is Some(hash) &&
    @execution.preparation_representation_cost({
      record_headers: 23L,
      reference_slots: 20L,
      scalar_words: 4L,
      owned_utf16_units: 2L * bytes.to_int64(),
      owned_wire_bytes: 0L,
    })
    is Some(retained) &&
    @execution.preparation_representation_cost({
      record_headers: parser.record_headers +
      tree.retained.record_headers +
      tree.scratch.record_headers +
      text.record_headers +
      hash.record_headers +
      4L * n.to_int64() +
      12L,
      reference_slots: parser.reference_slots +
      tree.retained.reference_slots +
      tree.scratch.reference_slots +
      text.reference_slots +
      hash.reference_slots +
      4L * n.to_int64() +
      12L,
      scalar_words: parser.scalar_words +
      tree.retained.scalar_words +
      tree.scratch.scalar_words +
      text.scalar_words +
      hash.scalar_words +
      4L * n.to_int64() +
      12L,
      owned_utf16_units: parser.owned_utf16_units +
      tree.retained_utf16_units +
      tree.scratch_utf16_units +
      text.owned_utf16_units +
      hash.owned_utf16_units,
      owned_wire_bytes: bytes.to_int64() + hash.owned_wire_bytes,
    })
    is Some(scratch) else {
    return None
  }
  let (header, unit, terminator, array_header, pointer) = @bootstrap.native_managed_value_layout()
  if header <= 0L || unit != 2L || terminator != unit || pointer < 4L {
    return None
  }
  let mut text_backing = 1L
  while text_backing < 4L * bytes.to_int64() {
    text_backing *= 2L
  }
  let raw = Int64::max(
    header + (text_backing + 1L) * unit,
    array_header +
    Int64::max(12L + 12L * bytes.to_int64(), 18L + 11L * n.to_int64()) * pointer,
  )
  Some((retained, retained + scratch, raw))
}

///|
fn read_native_client_effect_ledger_entry(
  database : @sqlite.Database,
  scope : String,
  checkpoint : String,
  entry : String,
  reads : NativeClientJournalReadAccess?,
) -> Result[@effect.EffectLedgerEntry, NativeClientRunJournalIssue] {
  let reserve = run_metadata_construction(database, reads)
  match prepare_native_effect_ledger_entry_key(reserve) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let key = native_effect_ledger_entry_key(scope, checkpoint, entry)
  let limits = native_client_effect_ledger_limits()
  let stored = match reads {
    None => {
      let extent = match
        database.observe_body_extent(effect_ledger_entry_table, key) {
        Ok(value) => value
        Err(issue) => return effect_ledger_entry_read_issue(issue)
      }
      if extent.body_bytes <= 0L ||
        extent.body_bytes > limits.max_wire_bytes.to_int64() {
        return Err(CustodyLost)
      }
      database.read_exact_body_extent(effect_ledger_entry_table, key, extent)
    }
    Some(_) =>
      read_client_journal_value(database, effect_ledger_entry_table, key, reads)
  }
  let body = match stored {
    Ok(value) if value.revision == 0L => value.body
    Ok(_) => return Err(CustodyLost)
    Err(issue) => return effect_ledger_entry_read_issue(issue)
  }
  guard native_effect_ledger_entry_admission_quote(body.length(), limits)
    is Some((retained, execution, raw)) else {
    return Err(CustodyLost)
  }
  if reserve is Some(before) {
    match before(retained, execution, raw) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  let wire = @utf8.decode(body) catch { _ => return Err(CustodyLost) }
  match
    @effect.admit_effect_ledger_entry(
      wire,
      // Canonical equality cannot require more than this exact input.
      body.length(),
      limits.max_nodes,
      limits.max_depth,
    ) {
    Ok(original) if @effect.effect_ledger_entry_cid(original) == entry &&
      @effect.effect_ledger_entry_scope_cid(original) == scope => Ok(original)
    _ => Err(CustodyLost)
  }
}

///|
fn[T] effect_ledger_entry_read_issue(
  issue : @sqlite.NativeSqliteIssue,
) -> Result[T, NativeClientRunJournalIssue] {
  match issue {
    @sqlite.NotFound | @sqlite.BodyTooLarge | @sqlite.Collision =>
      Err(CustodyLost)
    _ => Err(Physical(issue))
  }
}

///|
// The original complete inventory has already authenticated every referenced
// entry in the SQLite snapshot. Cardinality rejects additional physical rows
// without a second map of keys or parsing any unreferenced payload.
fn confirm_native_effect_ledger_entry_inventory(
  database : @sqlite.Database,
  reads : NativeClientJournalReadAccess?,
  expected : Int64,
) -> Result[Unit, NativeClientRunJournalIssue] {
  let reserve = run_metadata_construction(database, reads)
  let maximum = native_client_effect_ledger_limits().max_wire_bytes.to_int64()
  let mut key = ""
  let mut observed = 0L
  while true {
    if reserve is Some(before) {
      // Header scanning returns a physical key of at most 512 bytes, even for
      // unrelated rows. Fund the old cursor, new cursor, UTF-8 input/output,
      // adapter key and the two scalar extent carriers before the query.
      guard @execution.preparation_representation_cost({
          record_headers: 10L,
          reference_slots: 8L,
          scalar_words: 12L,
          owned_utf16_units: 2L * 512L,
          owned_wire_bytes: 4L * 512L,
        })
        is Some(peak) else {
        return Err(CapacityExceeded)
      }
      let (header, unit, terminator, _, _) = @bootstrap.native_managed_value_layout()
      match before(0L, peak, header + 512L * unit + terminator) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
    }
    let header = match reads {
      None => database.observe_scan_body_extent(effect_ledger_entry_table, key)
      Some(original) if physical_equal(database, original.database) =>
        (original.observe_scan_body_extent)(effect_ledger_entry_table, key)
      Some(_) => return Err(CustodyLost)
    }
    match header {
      Err(@sqlite.NotFound) =>
        return if observed == expected { Ok(()) } else { Err(CustodyLost) }
      Err(issue) => return effect_ledger_entry_read_issue(issue)
      Ok((next, extent)) if observed < expected &&
        extent.revision == 0L &&
        extent.body_bytes > 0L &&
        extent.body_bytes <= maximum => {
        observed += 1L
        key = next
      }
      Ok(_) => return Err(CustodyLost)
    }
  }
  Ok(())
}

///|
// Only the suffix to the exact admitted original is inserted. Upgrading an
// inline row copies its existing originals in order in the same transaction.
// The caller validates the next independent witness before this call and owns
// the Run CAS, rollback and uncertain COMMIT. No result here permits a send.
fn persist_native_client_effect_ledger_entries(
  database : @sqlite.Database,
  before : NativeClientRunRecord,
  next : NativeClientRunRecord,
  operations : NativeClientJournalOperationAccess?,
) -> Result[Bool, NativeClientRunJournalIssue] {
  guard next.checkpoint is Some(checkpoint) &&
    !checkpoint.effect_ledger.is_empty() else {
    return if before.checkpoint_companion {
      Err(CustodyLost)
    } else {
      Ok(false)
    }
  }
  let entries = checkpoint.effect_ledger
  let scope = @host.client_request_scope_cid(next.request)
  let checkpoint_cid = checkpoint.artifact.checkpoint_cid
  if entries.length() > 128 ||
    scope != @host.client_request_scope_cid(before.request) ||
    @publication.publication_contract_identity(next.definition) !=
    @publication.publication_contract_identity(before.definition) {
    return Err(CustodyLost)
  }
  guard before.checkpoint is Some(prior) &&
    prior.artifact.checkpoint_cid == checkpoint_cid &&
    prior.effect_ledger.length() <= entries.length() else {
    return Err(CustodyLost)
  }
  for index in 0..<prior.effect_ledger.length() {
    if @effect.effect_ledger_entry_cid(prior.effect_ledger[index]) !=
      @effect.effect_ledger_entry_cid(entries[index]) {
      return Err(CustodyLost)
    }
  }
  let start = if before.checkpoint_companion {
    prior.effect_ledger.length()
  } else {
    0
  }
  let limits = native_client_effect_ledger_limits()
  let reserve = run_metadata_construction(
    database,
    operations.map(original => original.reads),
  )
  for index in start..<entries.length() {
    let original = entries[index]
    if @effect.effect_ledger_entry_scope_cid(original) != scope {
      return Err(CustodyLost)
    }
    let wire = @effect.effect_ledger_entry_wire(original)
    guard @scalar.admit_utf8_length(wire, limits.max_wire_bytes) is Ok(bytes) else {
      return Err(CapacityExceeded)
    }
    // The wire itself is borrowed. Keep the encoded Bytes, adapter copy and
    // SQLite input live together, alongside the derived key and its prefix.
    if reserve is Some(quote) {
      let contiguous = bytes.to_int64() + 16L
      let key_and_control = 2L * (3L * 71L + 2L) * 2L + 256L
      match
        quote(
          0L,
          3L * contiguous + key_and_control,
          Int64::max(contiguous, 448L),
        ) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
    }
    let key = native_effect_ledger_entry_key(
      scope,
      checkpoint_cid,
      @effect.effect_ledger_entry_cid(original),
    )
    match
      insert_client_journal_value(
        database,
        effect_ledger_entry_table,
        key,
        @utf8.encode(wire),
        operations,
      ) {
      Ok(0L) => ()
      Ok(_) | Err(@sqlite.Collision) => return Err(CustodyLost)
      Err(issue) => return Err(Physical(issue))
    }
  }
  Ok(true)
}
