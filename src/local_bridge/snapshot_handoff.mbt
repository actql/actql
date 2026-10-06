///|
priv enum GraphSnapshotHandoffPhase {
  Saving
  Saved
  Released
  Reloading
  Restored
  Taken
  Rejected
  Closed
} derive(Eq)

///|
/// An operation on the existing Graph retention owner. The trusted checked
/// port is captured before receiving any persisted bytes; a snapshot header
/// cannot select another definition, domain, or producer occurrence.
struct GraphSnapshotHandoff {
  owner : @lower.BoundPrepared
  target : @pipeline.Target
  control : @bounded.Control
  storage_limits : @graph_storage.Limits
  snapshot_limits : @snapshot.Limits
  storage_bytes : Int64
  max_workspace_slots : Int
  available : () -> Bool
  mut source : @graph.Completed?
  mut saving : @snapshot.Preparation?
  save_session : @bounded.Session[
    @snapshot.Preparation,
    String,
    GraphBridgeIssue,
  ]
  mut save_token : @bounded.Token?
  mut saved_cid : String?
  mut reload : RowsToGraphExecution?
  mut restored : @graph.Completed?
  mut phase : GraphSnapshotHandoffPhase
}

///|
pub enum GraphSnapshotSavePoll {
  Saving(progress~ : Int64, work~ : Int64)
  Saved(String, progress~ : Int64, work~ : Int64)
  SaveFailed(GraphBridgeIssue, progress~ : Int64, work~ : Int64)
  SaveStopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
/// Begin bounded serialization of one exact completed Graph. This does not
/// commit a file, release Site capacity, or publish the resulting bytes.
pub fn prepare_graph_snapshot_handoff(
  control : @bounded.Control,
  owner : @lower.BoundPrepared,
  target : @pipeline.Target,
  source : @graph.Completed,
  storage_limits : @graph_storage.Limits,
  snapshot_limits : @snapshot.Limits,
  max_workspace_slots : Int,
  available : () -> Bool,
) -> Result[GraphSnapshotHandoff, GraphBridgeIssue] {
  guard @lifecycle.completion_reference_matches_port(
      @graph.completed_carrier_reference(source),
      owner,
      target,
    ) &&
    @graph.completed_storage(source) is Some(storage) &&
    @graph.completed_storage_bytes(source) is Some(storage_bytes) else {
    return Err(GraphInputUnavailable)
  }
  if !available() || max_workspace_slots < 0 {
    return Err(GraphInputUnavailable)
  }
  let saving = match @snapshot.prepare(storage, "", snapshot_limits) {
    Ok(saving) => saving
    Err(issue) => return Err(GraphSnapshot(issue))
  }
  let (save_session, save_token) = @bounded.start(
    control,
    saving,
    fn(saving, quantum, reader) {
      if @bounded.stop_requested(reader) is Some(reason) {
        return @bounded.Stopped(reason, 0, 0)
      }
      if !available() || !@graph.completed_available(source) {
        return @bounded.Failed(GraphInputUnavailable, 0, 0)
      }
      match @snapshot.advance(saving, quantum) {
        Err(issue) => @bounded.Failed(GraphSnapshot(issue), 0, 0)
        Ok(@snapshot.Continue(progress~, work~)) =>
          @bounded.Continue(progress.to_int(), work.to_int())
        Ok(@snapshot.Complete(snapshot, progress~, work~)) => {
          let cid = @snapshot.cid(snapshot)
          @snapshot.cleanup(snapshot) |> ignore
          @bounded.Complete(cid, progress.to_int(), work.to_int())
        }
      }
    },
    @snapshot.cancel,
    fn(_) { true },
  )
  Ok({
    owner,
    target,
    control,
    storage_limits,
    snapshot_limits,
    storage_bytes,
    max_workspace_slots,
    available,
    source: Some(source),
    saving: Some(saving),
    save_session,
    save_token: Some(save_token),
    saved_cid: None,
    reload: None,
    restored: None,
    phase: Saving,
  })
}

///|
pub fn advance_graph_snapshot_save(
  value : GraphSnapshotHandoff,
  quantum : Int,
) -> Result[GraphSnapshotSavePoll, GraphBridgeIssue] {
  guard value.phase == Saving && value.save_token is Some(token) else {
    return Err(GraphInputUnavailable)
  }
  match @bounded.advance(value.save_session, token, quantum) {
    Err(issue) => Err(GraphExecution(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.save_token = Some(next)
      Ok(Saving(progress~, work~))
    }
    Ok(@bounded.Completed(cid, progress~, work~)) => {
      value.save_token = None
      value.saved_cid = Some(cid)
      value.phase = Saved
      Ok(Saved(cid, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.save_token = None
      value.phase = Rejected
      Ok(SaveFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.save_token = None
      value.phase = Rejected
      Ok(SaveStopped(reason, progress~, work~))
    }
  }
}

///|
/// Drain provisional bytes into the Host's existing Store writer. Saved does
/// not authorize source reclamation until that writer has actually finalized.
pub fn take_graph_snapshot_save_output(
  value : GraphSnapshotHandoff,
) -> Result[String, GraphBridgeIssue] {
  guard (value.phase == Saving || value.phase == Saved) &&
    value.saving is Some(saving) else {
    return Err(GraphInputUnavailable)
  }
  @snapshot.take_output(saving).map_err(issue => GraphSnapshot(issue))
}

///|
/// The Store caller invokes this only after sealing and verifying the file.
/// The source generation is made unavailable before any restored Graph can
/// exist, so a consumer cannot silently keep reading the pre-save material.
pub fn release_graph_snapshot_source(
  value : GraphSnapshotHandoff,
  persisted_cid : String,
) -> Result[Unit, GraphBridgeIssue] {
  guard value.phase == Saved &&
    value.saved_cid is Some(expected) &&
    persisted_cid == expected &&
    value.source is Some(source) else {
    return Err(GraphSnapshot(@snapshot.SnapshotIdentityMismatch))
  }
  if !@graph.discard_completed(source) {
    return Err(GraphInputUnavailable)
  }
  value.source = None
  match @bounded.cleanup(value.save_session) {
    Err(issue) => return Err(GraphExecution(issue))
    Ok(_) => ()
  }
  value.saving = None
  value.phase = Released
  Ok(())
}

///|
pub fn start_graph_snapshot_handoff_reload(
  value : GraphSnapshotHandoff,
  input : @decode.Cursor,
  input_available : () -> Bool,
  reference_issuer? : @value.ReferenceIssuer? = None,
  control_work_limit? : Int? = None,
) -> Result[Unit, GraphBridgeIssue] {
  guard value.phase == Released && value.saved_cid is Some(expected) else {
    return Err(GraphInputUnavailable)
  }
  let reload = match
    start_graph_snapshot_reload(
      value.control,
      value.owner,
      value.target,
      input,
      expected,
      value.storage_limits,
      value.snapshot_limits,
      value.storage_bytes,
      value.max_workspace_slots,
      input_available,
      value.available,
      reference_issuer~,
      control_work_limit~,
    ) {
    Ok(reload) => reload
    Err(issue) => return Err(issue)
  }
  value.reload = Some(reload)
  value.phase = Reloading
  Ok(())
}

///|
/// The existing bounded reload owns validation, work, stop, and cleanup. Its
/// cumulative work convention is unchanged, as is the save session's. The
/// Host accounts differences once rather than adding repeated cumulative reads.
pub fn advance_graph_snapshot_handoff_reload(
  value : GraphSnapshotHandoff,
  quantum : Int,
) -> Result[RowsToGraphPoll, GraphBridgeIssue] {
  guard value.phase == Reloading && value.reload is Some(reload) else {
    return Err(GraphInputUnavailable)
  }
  advance_rows_to_graph(reload, quantum).map(poll => {
    match poll {
      Complete(output, ..) => {
        value.restored = Some(output)
        value.phase = Restored
      }
      _ => ()
    }
    poll
  })
}

///|
/// Transfer completion custody once, before the physical task is committed.
/// Equal schema/CID does not make this the old generation's completion token.
pub fn take_graph_snapshot_restored(
  value : GraphSnapshotHandoff,
) -> Result[@graph.Completed, GraphBridgeIssue] {
  guard value.phase == Restored &&
    value.restored is Some(output) &&
    @graph.completed_available(output) else {
    return Err(GraphInputUnavailable)
  }
  value.restored = None
  value.phase = Taken
  Ok(output)
}

///|
pub fn cleanup_graph_snapshot_handoff(
  value : GraphSnapshotHandoff,
) -> Result[Bool, GraphBridgeIssue] {
  if value.phase == Closed {
    return Ok(false)
  }
  if value.save_token is Some(_) {
    @bounded.request_cancel(value.control) |> ignore
    advance_graph_snapshot_save(value, 1) |> ignore
  }
  match @bounded.cleanup(value.save_session) {
    Err(issue) => return Err(GraphExecution(issue))
    Ok(_) => ()
  }
  value.saving = None
  if value.reload is Some(reload) {
    if reload.token is Some(_) {
      @bounded.request_cancel(value.control) |> ignore
      advance_rows_to_graph(reload, 1) |> ignore
    }
    match cleanup_rows_to_graph(reload) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    if rows_to_graph_cleanup_pending(reload) {
      return Ok(false)
    }
    value.reload = None
  }
  if value.restored is Some(output) {
    @graph.discard_completed(output) |> ignore
    value.restored = None
  }
  if value.source is Some(source) {
    @graph.discard_completed(source) |> ignore
    value.source = None
  }
  value.phase = Closed
  Ok(true)
}

///|
pub fn graph_snapshot_handoff_cleanup_pending(
  value : GraphSnapshotHandoff,
) -> Bool {
  value.phase != Closed
}
