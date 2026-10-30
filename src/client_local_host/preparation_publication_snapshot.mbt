///|
/// One tracked snapshot continuation. It owns no second grant and never exposes
/// its raw issuer. Completed/cancelled escaped handles lose their heavy issuer.
struct ClientProgramSnapshot {
  publication : ClientProgramPublication
  mut issuer : @publication_host.PublicationOutputSnapshotPreparation?
}

///|
fn program_snapshot_slot_matches(value : ClientProgramSnapshot) -> Bool {
  match value.publication.snapshot {
    Some(original) => physical_equal(original, value)
    None => false
  }
}

///|
fn program_snapshot_current(value : ClientProgramSnapshot) -> Bool {
  program_snapshot_slot_matches(value) && value.issuer is Some(_)
}

///|
/// The producer's original finished writer supplies exact B/N/depth. Flat
/// snapshots were prequoted from their original schema; recursive snapshots
/// grow the SAME body reservation before their constructor. No caller can
/// supply dimensions or substitute an equal-content Result.
pub fn begin_program_snapshot(
  value : ClientProgramPublication,
  output : @publication_host.PublicationOutputExport,
) -> Result[ClientProgramSnapshot, ClientClosedValuesPreparationIssue] {
  guard publication_original_body(value) is Some(_) &&
    value.run is Some(run) &&
    value.row_bound is Some(row_bound) else {
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
  let (bytes, nodes, rows, depth) = match
    output.snapshot_original_extent(run, occurrence) {
    Ok(extent) => extent
    Err(issue) => return Err(PublicationSnapshot(issue))
  }
  if rows < 0 || rows > row_bound || bytes < 1 || nodes < 1 {
    return Err(Policy)
  }
  // Consume the occurrence before imported currentness can reenter. Failure
  // never reopens this occurrence or authorizes a second retained row copy.
  value.snapshot_starting = true
  value.next_snapshot_index += 1
  let reservation = if value.snapshot_prequoted {
    refresh_publication_original(value).map(_ => ())
  } else {
    let schema = @results.port_schema(
      @execution.managed_result_occurrence_port(occurrence),
    )
    match
      recursive_snapshot_layout(
        bytes,
        nodes,
        depth,
        @schema.field_count(schema),
        @schema.field_reference_name_bytes(schema),
      ) {
      None => Err(Policy)
      Some(layout) =>
        match
          (
            @execution.preparation_representation_cost(layout.retained),
            @execution.preparation_representation_cost(layout.temporary),
          ) {
          (Some(r), Some(e)) if r <= 9223372036854775807L - 96L =>
            reserve_publication_constructor(value, r + 96L, e)
          _ => Err(Policy)
        }
    }
  }
  match reservation {
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
  let issuer = match output.start_captured_snapshot(bytes, nodes, depth) {
    Ok(issuer) => issuer
    Err(issue) => {
      value.snapshot_starting = false
      return Err(PublicationSnapshot(issue))
    }
  }
  let snapshot : ClientProgramSnapshot = {
    publication: value,
    issuer: Some(issuer),
  }
  value.snapshot = Some(snapshot)
  value.snapshot_starting = false
  Ok(snapshot)
}

///|
pub fn advance_program_snapshot(
  value : ClientProgramSnapshot,
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
pub fn finish_program_snapshot(
  value : ClientProgramSnapshot,
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
pub fn cancel_program_snapshot(value : ClientProgramSnapshot) -> Unit {
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
fn cancel_active_program_snapshot(value : ClientProgramPublication) -> Unit {
  if value.snapshot is Some(snapshot) {
    if snapshot.issuer is Some(issuer) {
      issuer.cancel()
    }
    snapshot.issuer = None
  }
  value.snapshot = None
  value.snapshot_starting = false
}
