///|
priv suberror PropertySnapshotStop {
  PropertySnapshotStop(Issue)
}

///|
fn snapshot_charge(
  builder : Builder,
  work : Int,
) -> Unit raise PropertySnapshotStop {
  if work < 0 || work > builder.limits.max_work - builder.work {
    raise PropertySnapshotStop(WorkLimit)
  }
  builder.work += work
}

///|
fn snapshot_object(
  input : @decode.Cursor,
  names : Array[String],
) -> @decode.ObjectView raise PropertySnapshotStop {
  guard @decode.object_length(input) == Some(names.length()) &&
    @decode.closed_object(input, names) is Ok(object) else {
    raise PropertySnapshotStop(InvalidIdentity)
  }
  object
}

///|
fn append_property_snapshot_record(
  builder : Builder,
  input : @decode.Cursor,
  edge : Bool,
  reference_issuer : @value.ReferenceIssuer?,
) -> Result[Unit, Issue] {
  let preparation = match
    start_property_snapshot_append(builder, input, edge~, reference_issuer~) {
    Ok(preparation) => preparation
    Err(issue) => return Err(issue)
  }
  while true {
    match advance_property_snapshot_append(preparation, 64) {
      PropertySnapshotAppendContinue(work~) => ignore(work)
      PropertySnapshotAppendComplete(work~) => {
        ignore(work)
        cleanup_property_snapshot_append(preparation)
        return Ok(())
      }
      PropertySnapshotAppendFailed(issue, work~) => {
        ignore(work)
        cleanup_property_snapshot_append(preparation)
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
  append_property_snapshot_record(builder, input, false, reference_issuer)
}

///|
pub fn append_snapshot_edge(
  builder : Builder,
  input : @decode.Cursor,
  reference_issuer? : @value.ReferenceIssuer? = None,
) -> Result[Unit, Issue] {
  append_property_snapshot_record(builder, input, true, reference_issuer)
}
