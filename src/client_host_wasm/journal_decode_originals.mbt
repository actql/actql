///|
// One invocation's pure codec storage under the existing journal child. This
// never stores a physical read, inventory, current decision, grant or ACK.
priv struct StoredJournalRunOriginal {
  mut row : @host.ClientJournalPhysicalRow?
  mut decoded : (@host.ClientRunJournalEncoding, String?, String?)?
  mut observation : @host.ClientRunObservationOriginals?
  capacity : @resources.CapacityReservation
  mut retention : Int64
  mut next : StoredJournalRunOriginal?
}

///|
priv struct StoredJournalDecodeFrame {
  nonce : Int64
  handle : Int
  physical : Int
  selected_key : String
  capacity : @resources.CapacityReservation
  indexed_capacity : Int64
  mut index : FixedArray[StoredJournalRunOriginal?]?
  mut indexed_rows : Int
  mut active : Bool
  mut busy : Bool
  mut issue : Int
  mut rows : StoredJournalRunOriginal?
  mut selected : StoredJournalRunOriginal?
  mut pending : @resources.CapacityReservation?
}

///|
priv enum StoredJournalObservationOutcome {
  ReservingDecode(@resources.CapacityReservation, Int)
  Decoding(StoredJournalDecodeFrame)
  Observed(
    Result[@local_run.LocalSavedSubmissionObservation, Int],
    StoredJournalDecodeFrame?
  )
}

///|
fn journal_decode_frame_capacity(indexed? : Bool = false) -> Int64? {
  // Include the new optional index slot and the two fixed accounting words in
  // either phase. Active indexing additionally pays a FixedArray and its Some,
  // one Some(cell) per admitted entry, one replacement Some, and a probe pair.
  // The index borrows the row keys and cells kept by the separate cleanup list.
  let entries = if indexed { journal_decode_index_limit.to_int64() } else { 0L }
  @execution.preparation_representation_cost({
    record_headers: 6L + (if indexed { entries + 4L } else { 0L }),
    reference_slots: 14L +
    (if indexed {
      journal_decode_index_slots.to_int64() + entries + 2L
    } else {
      0L
    }),
    scalar_words: 11L + (if indexed { entries + 5L } else { 0L }),
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
}

///|
let journal_decode_index_limit = 1024

///|
let journal_decode_index_slots = 2048

///|
// The index has no deletions while active and uses at most half the slots.
// The fast probe is capped even for an unfavorable key set. An exhausted
// probe does not establish absence from the separate original-cell list.
fn journal_decode_index_probe(
  index : FixedArray[StoredJournalRunOriginal?],
  key : String,
) -> (Int, Int) {
  if key.length() > 4096 {
    return (-1, 0)
  }
  let mask = journal_decode_index_slots - 1
  let start = Hash::hash(key) & mask
  for probe in 0..<32 {
    let slot = (start + probe) & mask
    match index[slot] {
      None => return (slot, probe + 1)
      Some(cell) =>
        if cell.row is Some(original) && original.key == key {
          return (slot, probe + 1)
        }
    }
  }
  (-1, 32)
}

///|
fn journal_decode_cell_matches(
  cell : StoredJournalRunOriginal,
  row : @host.ClientJournalPhysicalRow,
) -> Bool {
  cell.row is Some(original) &&
  original.key == row.key &&
  original.revision == row.revision &&
  original.body == row.body &&
  cell.decoded is Some(_)
}

///|
// An unindexed original remains admissible under its own token. This path
// only handles exhausted probes, full backing or a replaced same-key entry.
fn journal_decode_original_from_list(
  rows : StoredJournalRunOriginal?,
  row : @host.ClientJournalPhysicalRow,
) -> StoredJournalRunOriginal? {
  let mut cursor = rows
  while cursor is Some(cell) {
    if journal_decode_cell_matches(cell, row) {
      return cursor
    }
    cursor = cell.next
  }
  None
}

///|
fn journal_decode_row_capacity(
  row : @host.ClientJournalPhysicalRow,
) -> (Int64, Int64)? {
  let bytes = row.body.length()
  if bytes < 1 || bytes > 131072 || row.key.length() > 4096 {
    return None
  }
  guard @host.client_run_journal_decode_construction(
      @host.RunJournalRetained(bytes, 2L * bytes.to_int64(), 32, 4),
    )
    is Some((retained, _)) &&
    // The unchanged unobserved decoder uses its full131072-byte profile.
    @host.client_run_journal_decode_construction(
      @host.RunJournalCanonical(131072, 262144L, 32, 4),
    )
    is Some((_, execution)) &&
    @execution.preparation_representation_cost({
      // Linked cell, inspection projection, row/Option/Result carriers. The
      // actual request/Definition backing is in the shared codec quote above.
      record_headers: 8L,
      // One extra optional metadata reference exists even while it is None.
      reference_slots: 25L,
      scalar_words: 5L,
      owned_utf16_units: 2L * row.key.length().to_int64(),
      // An exact-hit selected snapshot keeps a DISTINCT fresh physical body
      // beside the retained codec body. Admit that overlap before retention.
      owned_wire_bytes: bytes.to_int64(),
    })
    is Some(cell) &&
    @execution.checked_preparation_add_product(retained, cell, 1L)
    is Some(retained) &&
    @execution.checked_preparation_add_product(execution, cell, 1L)
    is Some(execution) else {
    return None
  }
  Some((retained, execution))
}

///|
fn open_journal_decode_frame(
  value : Instance,
  handle : Int,
  child : StoredJournalObservation,
  selected_key : String,
) -> StoredJournalDecodeFrame? {
  guard journal_decode_frame_capacity(indexed=true) is Some(bytes) else {
    return None
  }
  let capacity = match @resources.reserve_capacity(value.root, bytes, bytes) {
    Ok(capacity) => capacity
    // Optimization admission is optional. Keep the previous full validator
    // when additional retention cannot fit;1024 records is never funding.
    Err(_) => return None
  }
  // Make the exact token reachable before constructing the frame.
  child.outcome = Some(ReservingDecode(capacity, 0))
  let frame : StoredJournalDecodeFrame = {
    nonce: value.nonce,
    handle,
    physical: child.physical,
    selected_key,
    capacity,
    indexed_capacity: bytes,
    index: Some(FixedArray::make(journal_decode_index_slots, None)),
    indexed_rows: 0,
    active: true,
    busy: false,
    issue: 0,
    rows: None,
    selected: None,
    pending: None,
  }
  child.outcome = Some(Decoding(frame))
  Some(frame)
}

///|
fn journal_decode_frame_current(
  value : Instance,
  child : StoredJournalObservation,
  frame : StoredJournalDecodeFrame,
) -> Bool {
  frame.active &&
  !child.closing &&
  frame.nonce == value.nonce &&
  frame.physical == child.physical &&
  value.journal_observations
  .get(frame.handle)
  .map(original => physical_equal(original, child))
  .unwrap_or(false) &&
  child.outcome is Some(Decoding(original)) &&
  physical_equal(original, frame)
}

///|
fn journal_inspect_run_with_observation(
  value : Instance,
  cell : StoredJournalRunOriginal?,
  row : @host.ClientJournalPhysicalRow,
  decoded : (@host.ClientRunJournalEncoding, String?, String?),
  before_observation : (() -> Unit)?,
) -> Result[@host.ClientRunJournalInspection, Int] {
  let retained = cell.bind(cell => cell.observation)
  let admitted = if retained is Some(_) || decoded.2 is None {
    false
  } else {
    match
      (
        cell,
        journal_observation_construction_capacity(),
        journal_decode_row_capacity(row),
      ) {
      (Some(cell), Some((retention, execution)), Some((base, outer))) =>
        match
          (
            @execution.checked_preparation_add_product(base, retention, 1L),
            @execution.checked_preparation_add_product(outer, execution, 1L),
          ) {
          (Some(retention), Some(execution)) =>
            @resources.grow_capacity_reservation(
              value.root,
              cell.capacity,
              retention,
              execution,
            )
            is Ok(_)
          _ => false
        }
      _ => false
    }
  }
  let capture : ((@host.ClientRunObservationOriginals) -> Unit)? = if admitted &&
    cell is Some(cell) {
    Some(original => cell.observation = Some(original))
  } else {
    None
  }
  let record = match
    validate_sdk_run_row_decoded(
      Ok(decoded),
      observation_original=retained,
      retain_observation=capture,
      // Prefix Policy/unsupported checks keep their original order. A refused
      // SAME-cell quote must stop BEFORE the nested constructor, not silently
      // execute it under the unrelated outer-row reservation.
      observation_construction_issue=if decoded.2 is Some(_) &&
        retained is None &&
        !admitted {
        -4
      } else {
        0
      },
      before_observation~,
    ) {
    Ok(record) => record
    Err(code) => return Err(code)
  }
  if admitted && cell is Some(cell) && cell.observation is Some(original) {
    // Both outputs and this extent walk remain funded by the original peak.
    // No shrink occurs until this helper and its constructor stack return.
    guard journal_observation_retention(original) is Some(retention) &&
      journal_decode_row_capacity(row) is Some((base, _)) &&
      @execution.checked_preparation_add_product(base, retention, 1L)
      is Some(total) else {
      return Err(-4)
    }
    cell.retention = total
  }
  Ok({
    request: record.request,
    definition: record.definition,
    checkpoint: None,
    task_materials_cid: record.task_materials_cid,
  })
}

///|
fn journal_drop_observation(cell : StoredJournalRunOriginal) -> Unit {
  cell.observation = None
}

///|
fn journal_decode_run_inspection(
  value : Instance,
  child : StoredJournalObservation,
  frame : StoredJournalDecodeFrame,
  row : @host.ClientJournalPhysicalRow,
  before_construction? : ((@host.ClientRunJournalConstruction) -> Result[
    Unit,
    @host.ClientJournalDecodingIssue,
  ])? = None,
  before_observation? : (() -> Unit)? = None,
) -> Result[@host.ClientRunJournalInspection, Int] {
  if !journal_decode_frame_current(value, child, frame) {
    return Err(-2)
  }
  if frame.busy {
    frame.issue = -33
    return Err(-33)
  }
  if frame.issue != 0 {
    return Err(frame.issue)
  }
  guard frame.index is Some(index) &&
    @resources.capacity_reservation_covers(
      value.root,
      frame.capacity,
      frame.indexed_capacity,
      frame.indexed_capacity,
    ) else {
    return Err(-4)
  }
  let (slot, _) = journal_decode_index_probe(index, row.key)
  let indexed = if slot >= 0 { index[slot] } else { None }
  let original = match indexed {
    Some(cell) if journal_decode_cell_matches(cell, row) => indexed
    None if slot >= 0 && frame.indexed_rows < journal_decode_index_limit => None
    _ => journal_decode_original_from_list(frame.rows, row)
  }
  if original is Some(cell) && cell.decoded is Some(decoded) {
    if !@resources.capacity_reservation_covers(
        value.root,
        cell.capacity,
        cell.retention,
        0L,
      ) {
      return Err(-4)
    }
    // The original SDK/Definition/unsupported/current checks still run.
    frame.busy = true
    let inspected = journal_inspect_run_with_observation(
      value,
      Some(cell),
      row,
      decoded,
      before_observation,
    )
    frame.busy = false
    if frame.issue != 0 {
      return Err(frame.issue)
    }
    if !journal_decode_frame_current(value, child, frame) {
      return Err(-2)
    }
    match inspected {
      Err(code) => {
        frame.issue = code
        return Err(code)
      }
      Ok(_) => ()
    }
    // The constructor/measurement helper returned before workspace return.
    if @resources.shrink_capacity_reservation(
        value.root,
        cell.capacity,
        cell.retention,
        0L,
      )
      is Err(_) {
      frame.issue = -4
      return Err(-4)
    }
    if row.key == frame.selected_key {
      frame.selected = Some(cell)
    }
    return inspected
  }
  if row.key == frame.selected_key {
    frame.selected = None
  }
  let quoted = journal_decode_row_capacity(row)
  let capacity = match quoted {
    None => None
    Some((retention, execution)) =>
      @resources.reserve_capacity(value.root, retention, execution).to_option()
  }
  let cell = match (capacity, quoted) {
    (Some(capacity), Some((retention, _))) => {
      frame.pending = Some(capacity)
      let cell : StoredJournalRunOriginal = {
        row: Some(row),
        decoded: None,
        observation: None,
        capacity,
        retention,
        next: frame.rows,
      }
      frame.rows = Some(cell)
      frame.pending = None
      Some(cell)
    }
    _ => None
  }
  frame.busy = true
  // Fixed decoder kind: complete outer SDK Run row with original metadata.
  // No arbitrary/effectful validate_run callback is stored or bypassed.
  let decoded = @host.decode_client_run_journal_row_with_observation_originals(
    row.body,
    before_construction~,
  ).map_err(_ => -31)
  let inspected = decoded.bind(decoded => {
    journal_inspect_run_with_observation(
      value, cell, row, decoded, before_observation,
    )
  })
  frame.busy = false
  if frame.issue != 0 {
    return Err(frame.issue)
  }
  if !journal_decode_frame_current(value, child, frame) {
    return Err(-2)
  }
  match inspected {
    Err(code) => {
      frame.issue = code
      Err(code)
    }
    Ok(inspected) => {
      if cell is Some(cell) && quoted is Some(_) && decoded is Ok(decoded) {
        match
          @resources.shrink_capacity_reservation(
            value.root,
            cell.capacity,
            cell.retention,
            0L,
          ) {
          Err(_) => {
            frame.issue = -4
            return Err(-4)
          }
          Ok(_) => ()
        }
        cell.decoded = Some(decoded)
        if slot >= 0 {
          if index[slot] is Some(_) {
            index[slot] = Some(cell)
          } else if frame.indexed_rows < journal_decode_index_limit {
            index[slot] = Some(cell)
            frame.indexed_rows += 1
          }
        }
        if row.key == frame.selected_key {
          frame.selected = Some(cell)
        }
      }
      Ok(inspected)
    }
  }
}

///|
// Only original byte tokens already reachable from THIS journal child enter
// this close-only port. The trusted settlement checks SAME Ledger identity
// before ClosedReservation; the opaque token must also actually be spent.
// Neither a false coverage Bool nor a foreign/other refusal is an ACK.
fn settle_journal_decode_original(
  value : Instance,
  capacity : @resources.CapacityReservation,
) -> Int {
  match @resources.settle_capacity(value.root, capacity) {
    Ok(_) => 0
    Err(@resources.ClosedReservation) if !@resources.capacity_reservation_open(
        capacity,
      ) => 0
    Err(_) => -4
  }
}

///|
fn dispose_journal_decode_rows(
  value : Instance,
  frame : StoredJournalDecodeFrame,
  keep_selected : Bool,
) -> Int {
  frame.active = false
  // Drop all index aliases under the original frame token before any cell can
  // settle. A failed cell close still has its original link and token.
  frame.index = None
  frame.indexed_rows = 0
  if frame.pending is Some(capacity) {
    let code = settle_journal_decode_original(value, capacity)
    if code != 0 {
      return code
    }
    frame.pending = None
  }
  let selected = if keep_selected { frame.selected } else { None }
  let mut previous : StoredJournalRunOriginal? = None
  let mut cursor = frame.rows
  while cursor is Some(cell) {
    let next = cell.next
    let had_observation = cell.observation is Some(_)
    journal_drop_observation(cell)
    // The drop helper returned without any nested metadata loan. The selected
    // outer snapshot still owns its original request/Definition/body backing.
    if selected is Some(original) && physical_equal(original, cell) {
      if had_observation {
        guard cell.row is Some(row) &&
          journal_decode_row_capacity(row) is Some((retention, _)) else {
          return -4
        }
        if @resources.shrink_capacity_reservation(
            value.root,
            cell.capacity,
            retention,
            0L,
          )
          is Err(_) {
          return -4
        }
        cell.retention = retention
      }
      previous = Some(cell)
    } else {
      cell.decoded = None
      cell.row = None
      if frame.selected is Some(original) && physical_equal(original, cell) {
        frame.selected = None
      }
      let code = settle_journal_decode_original(value, cell.capacity)
      if code != 0 {
        return code
      }
      // Remove only the actually settled cell. A failed later settlement
      // therefore retries only the SAME still-pending tokens.
      match previous {
        None => frame.rows = next
        Some(original) => original.next = next
      }
    }
    cursor = next
  }
  frame.selected = selected

  0
}
