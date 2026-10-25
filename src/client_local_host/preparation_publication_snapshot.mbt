///|
/// One tracked snapshot continuation. It owns no second grant and never exposes
/// its raw issuer. Completed/cancelled escaped handles lose their heavy issuer.
struct ClientProgramSnapshot[I] {
  publication : ClientProgramPublication[I]
  mut issuer : @publication_host.PublicationOutputSnapshotPreparation?
}

///|
/// Per original Result: wrapper(2 refs), issuer Some and publication-slot Some.
/// Distinct from the final canonical snapshot, whose layout owns row payloads.
let publication_snapshot_wrapper_units : PreparationRepresentationUnits = {
  record_headers: 3L,
  reference_slots: 4L,
  scalar_words: 2L,
  owned_utf16_units: 0L,
  owned_wire_bytes: 0L,
}

///|
let publication_snapshot_wrapper_retained : Int64 = preparation_representation_cost(
  publication_snapshot_wrapper_units,
).unwrap()

///|
fn[I] program_snapshot_slot_matches(value : ClientProgramSnapshot[I]) -> Bool {
  match value.publication.snapshot {
    Some(original) => physical_equal(original, value)
    None => false
  }
}

///|
fn[I] program_snapshot_current(value : ClientProgramSnapshot[I]) -> Bool {
  program_snapshot_slot_matches(value) && value.issuer is Some(_)
}

///|
/// Fixed scalar snapshot path. The producer's original logical hash supplies
/// exact B/N; depth3 is logical wrapper -> row array -> flat scalar row object.
/// The original schema/row plan already funded the constructor and is checked
/// again here. No caller dimensions or content/CID-equivalent substitute exist.
pub fn[I] begin_program_snapshot(
  value : ClientProgramPublication[I],
  output : @publication_host.PublicationOutputExport,
) -> Result[ClientProgramSnapshot[I], ClientClosedValuesPreparationIssue] {
  guard publication_original_body(value) is Some(_) &&
    value.run is Some(run) &&
    value.owner.source_free is Some(source_free) &&
    source_free.capacity_plan.scalar_demand is Some(demand) else {
    return Err(ForeignOriginal)
  }
  if value.snapshot_starting ||
    value.snapshot is Some(_) ||
    value.capture_started {
    return Err(WrongPhase)
  }
  let graph = @strategy.captured_dag_graph(run)
  guard @strategy.graph_result_occurrence(graph, value.next_snapshot_index)
    is Some(occurrence) else {
    return Err(WrongPhase)
  }
  let (bytes, nodes, rows) = match
    output.snapshot_original_extent(run, occurrence) {
    Ok(extent) => extent
    Err(issue) => return Err(PublicationSnapshot(issue))
  }
  if rows < 0 || rows > demand.rows || bytes < 1 || nodes < 1 {
    return Err(Policy)
  }
  // Consume the occurrence before imported currentness can reenter. Failure
  // never reopens this occurrence or authorizes a second retained row copy.
  value.snapshot_starting = true
  value.next_snapshot_index += 1
  match refresh_publication_original(value) {
    Err(issue) => {
      value.snapshot_starting = false
      return Err(issue)
    }
    Ok(_) => ()
  }
  if publication_original_body(value) is None || value.run is None {
    value.snapshot_starting = false
    return Err(ForeignOriginal)
  }
  let issuer = match output.start_captured_snapshot(bytes, nodes, 3) {
    Ok(issuer) => issuer
    Err(issue) => {
      value.snapshot_starting = false
      return Err(PublicationSnapshot(issue))
    }
  }
  let snapshot : ClientProgramSnapshot[I] = {
    publication: value,
    issuer: Some(issuer),
  }
  value.snapshot = Some(snapshot)
  value.snapshot_starting = false
  Ok(snapshot)
}

///|
pub fn[I] advance_program_snapshot(
  value : ClientProgramSnapshot[I],
  quantum : Int,
) -> Result[(Bool, Int), ClientClosedValuesPreparationIssue] {
  if !program_snapshot_current(value) {
    return Err(ForeignOriginal)
  }
  match refresh_publication_original(value.publication) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard program_snapshot_current(value) && value.issuer is Some(issuer) else {
    return Err(ForeignOriginal)
  }
  match issuer.advance(quantum) {
    Ok(progress) => Ok(progress)
    Err(issue) => Err(PublicationSnapshot(issue))
  }
}

///|
pub fn[I] finish_program_snapshot(
  value : ClientProgramSnapshot[I],
) -> Result[
  @publication.CapturedResultSnapshot,
  ClientClosedValuesPreparationIssue,
] {
  if !program_snapshot_current(value) {
    return Err(ForeignOriginal)
  }
  match refresh_publication_original(value.publication) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard program_snapshot_current(value) && value.issuer is Some(issuer) else {
    return Err(ForeignOriginal)
  }
  match issuer.finish() {
    Err(issue) => Err(PublicationSnapshot(issue))
    Ok(snapshot) => {
      value.issuer = None
      value.publication.snapshot = None
      value.publication.completed_snapshots.push(snapshot)
      Ok(snapshot)
    }
  }
}

///|
/// Cleanup is permitted after retirement, but only for the exact tracked
/// original. A stale finished handle is inert and cannot cancel its successor.
pub fn[I] cancel_program_snapshot(value : ClientProgramSnapshot[I]) -> Unit {
  if !program_snapshot_slot_matches(value) {
    return
  }
  if value.issuer is Some(issuer) {
    issuer.cancel()
  }
  value.issuer = None
  value.publication.snapshot = None
}

///|
/// Called by the original preparation owner before cutting publication/Run
/// aliases. No currentness refresh is required to discharge cleanup custody.
fn[I] cancel_active_program_snapshot(
  value : ClientProgramPublication[I],
) -> Unit {
  if value.snapshot is Some(snapshot) {
    if snapshot.issuer is Some(issuer) {
      issuer.cancel()
    }
    snapshot.issuer = None
  }
  value.snapshot = None
  value.snapshot_starting = false
}
