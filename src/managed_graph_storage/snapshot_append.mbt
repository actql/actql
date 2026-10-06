///|
priv suberror GraphSnapshotStop {
  GraphSnapshotStop(Issue)
}

///|
fn snapshot_charge(
  builder : Builder,
  work : Int,
) -> Unit raise GraphSnapshotStop {
  if work < 0 || work > builder.limits.max_work - builder.work {
    raise GraphSnapshotStop(WorkLimit)
  }
  builder.work += work
}

///|
fn snapshot_object(
  input : @decode.Cursor,
  names : Array[String],
) -> @decode.ObjectView raise GraphSnapshotStop {
  guard @decode.object_length(input) == Some(names.length()) &&
    @decode.closed_object(input, names) is Ok(object) else {
    raise GraphSnapshotStop(InvalidIdentity)
  }
  object
}

///|
fn append_graph_snapshot_record(
  builder : Builder,
  input : @decode.Cursor,
  edge : Bool,
  reference_issuer : @value.ReferenceIssuer?,
) -> Result[Unit, Issue] {
  let preparation = match
    start_graph_snapshot_append(builder, input, edge~, reference_issuer~) {
    Ok(preparation) => preparation
    Err(issue) => return Err(issue)
  }
  while true {
    match advance_graph_snapshot_append(preparation, 64) {
      GraphSnapshotAppendContinue(work~) => ignore(work)
      GraphSnapshotAppendComplete(work~) => {
        ignore(work)
        cleanup_graph_snapshot_append(preparation)
        return Ok(())
      }
      GraphSnapshotAppendFailed(issue, work~) => {
        ignore(work)
        cleanup_graph_snapshot_append(preparation)
        return Err(issue)
      }
    }
  } nobreak {
    Err(Closed)
  }
}

///|
/// Snapshot admission is strict: no NULL-key or missing-endpoint exclusion is
/// permitted. Synchronous callers drain the same operation as managed callers.
pub fn append_snapshot_node(
  builder : Builder,
  input : @decode.Cursor,
  reference_issuer? : @value.ReferenceIssuer? = None,
) -> Result[Unit, Issue] {
  append_graph_snapshot_record(builder, input, false, reference_issuer)
}

///|
pub fn append_snapshot_edge(
  builder : Builder,
  input : @decode.Cursor,
  reference_issuer? : @value.ReferenceIssuer? = None,
) -> Result[Unit, Issue] {
  append_graph_snapshot_record(builder, input, true, reference_issuer)
}
