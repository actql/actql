///|
/// Reserve traversal custody before calling the existing wire emitter. This
/// borrows a cell, not a row-sized serialization or another encoding format.
priv struct SteppedRuntimeWire {
  cursor : IdentityWireCursor
  workspace : RowWorkspace
  handles : Int
  mut reserved : Int
  mut closed : Bool
}

///|
priv enum SteppedRuntimeWireIssue {
  Workspace
  Encoding(@encode.EncodeFailure)
}

///|
fn start_stepped_runtime_wire(
  value : Value,
  writer : @encode.Writer,
  workspace : RowWorkspace,
) -> Result[SteppedRuntimeWire, SteppedRuntimeWireIssue] {
  // Wrapper, admitted cursor, and a possible Text cursor overlap. A raw Text
  // only needs the wrapper and Text cursor; a scalar only needs the wrapper.
  let handles = match value {
    Captured(_) => 3
    Text(text) if text.length() > 64 => 2
    _ => 1
  }
  if !reserve_slots(workspace, handles + 1) {
    return Err(Workspace)
  }
  let cursor = identity_scan_emit(value, writer) catch {
    issue => {
      release_slots(workspace, handles + 1)
      return Err(Encoding(issue))
    }
  }
  Ok({ cursor, workspace, handles, reserved: handles + 1, closed: false, })
}

///|
fn close_stepped_runtime_wire(value : SteppedRuntimeWire) -> Unit {
  if !value.closed {
    cancel_identity_wire(value.cursor)
    release_slots(value.workspace, value.reserved)
    value.reserved = 0
    value.closed = true
  }
}

///|
fn advance_stepped_runtime_wire(
  value : SteppedRuntimeWire,
) -> Result[Bool, SteppedRuntimeWireIssue] {
  if value.closed {
    return Err(Encoding(@encode.ClosedWriter))
  }
  if value.cursor is CapturedWire(_) {
    // A container continuation can replace its popped frame with two
    // frames. Reserve that possible extra frame before either is allocated.
    if !reserve_slots(value.workspace, 1) {
      return Err(Workspace)
    }
    value.reserved += 1
  }
  let done = advance_identity_wire(value.cursor) catch {
    issue => return Err(Encoding(issue))
  }
  if done {
    close_stepped_runtime_wire(value)
  } else {
    let frames = match value.cursor {
      CapturedWire(cursor) => @admitted.wire_emit_pending_frames(cursor)
      TextWire(_) | ScalarWire(_, _) => 1
    }
    let retained = value.handles + frames
    release_slots(value.workspace, value.reserved - retained)
    value.reserved = retained
  }
  Ok(done)
}
