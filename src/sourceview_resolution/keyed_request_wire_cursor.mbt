///|
/// One selected original request's wire continuation. No fragment grants
/// provider access or forms a completed request. The caller owns resources,
/// retained fragment storage, final concatenation and cancellation ordering.
struct KeyedRequestWireCursor {
  request : KeyedRowRequest
  writer : @encode.Writer
  max_bytes : Int
  mut field : Int
  mut phase : Int
  mut active : @value.WireEmitCursor?
  mut generation : Int64
  mut fragment_peak_utf16 : Int
  mut closed : Bool
}

///|
pub(all) struct KeyedRequestWireInventory {
  generation : Int64
  fragment_bytes : Int
  record_headers : Int64
  reference_slots : Int64
  scalar_words : Int64
  owned_utf16_units : Int64
} derive(Eq, Debug)

///|
pub enum KeyedRequestWirePoll {
  WireContinue
  WireFragment(String)
  WireComplete(Int, Int, Int)
  WireFailed(RequestWireIssue)
}

///|
fn keyed_request_wire_inventory(
  generation : Int64,
  fragment : Int,
  writer : @encode.BufferedWriterConstructionInventory,
  typed : @value.WireEmitConstructionInventory?,
) -> KeyedRequestWireInventory {
  // Cursor1H3R6W; active Some1H1R1W; fragment/result/failure/inventory
  // carriers remain live across the return. This inventory owns no input
  // Strings, accumulated prior fragments, or final concat backing.
  let (h, r, w, u) = match typed {
    Some(v) =>
      (v.record_headers, v.reference_slots, v.scalar_words, v.owned_utf16_units)
    None => (0L, 0L, 0L, 0L)
  }
  {
    generation,
    fragment_bytes: fragment,
    record_headers: writer.record_headers + h + 8L,
    reference_slots: writer.reference_slots + r + 9L,
    scalar_words: writer.scalar_words + w + 21L,
    owned_utf16_units: writer.owned_utf16_units + u,
  }
}

///|
/// Reserve these fixed empty controls before constructing a cursor. Aggregate
/// policy ceilings are scalar limits, not allocated output or node buffers.
pub fn keyed_request_wire_start_inventory() -> KeyedRequestWireInventory {
  keyed_request_wire_inventory(
    0L,
    0,
    @encode.buffered_writer_start_construction_inventory(),
    None,
  )
}

///|
pub fn start_keyed_request_wire(
  request : KeyedRowRequest,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[KeyedRequestWireCursor, RequestWireIssue] {
  let writer = @encode.buffered_writer(
    max_bytes, max_nodes, max_depth, max_bytes,
  ) catch {
    issue => return Err(Encoding(issue))
  }
  Ok({
    request,
    writer,
    max_bytes,
    field: 0,
    phase: 0,
    active: None,
    generation: 0L,
    fragment_peak_utf16: 0,
    closed: false,
  })
}

///|
pub fn keyed_request_wire_owner(
  cursor : KeyedRequestWireCursor,
) -> KeyedRowRequest {
  cursor.request
}

///|
/// DATA snapshot, not authority. The same cursor's generation changes on every
/// advance/cancel, including steps with no emitted bytes. After a reservation
/// callback the caller must recheck it before mutating this continuation.
pub fn keyed_request_wire_progress(
  cursor : KeyedRequestWireCursor,
) -> (Int64, Int, Int, Int) {
  let (bytes, nodes, depth) = @encode.observed_writer_usage(cursor.writer)
  (cursor.generation, bytes, nodes, depth)
}

///|
pub fn keyed_request_wire_next_inventory(
  cursor : KeyedRequestWireCursor,
) -> KeyedRequestWireInventory? {
  if cursor.closed || cursor.generation == 9007199254740991L {
    return None
  }
  let (_, bytes, _, _) = keyed_request_wire_progress(cursor)
  let remaining = cursor.max_bytes - bytes
  let bound = match cursor.phase {
    0 => 1L
    1 =>
      if cursor.field == cursor.request.fields.length() {
        1L
      } else {
        // Same authored order and duplicate checks as the synchronous writer.
        // A complete current name is bounded from its retained UTF16 length,
        // never from a request-wide configured text ceiling.
        6L * cursor.request.fields[cursor.field].0.length().to_int64() + 4L
      }
    3 => @value.wire_emit_fragment_byte_bound().to_int64()
    _ => 0L
  }
  let fragment = if bound > remaining.to_int64() {
    remaining
  } else {
    bound.to_int()
  }
  guard @encode.buffered_writer_next_construction_inventory(
      cursor.writer,
      fragment,
      cursor.fragment_peak_utf16,
    )
    is Some(writer) else {
    return None
  }
  let typed = match cursor.active {
    Some(active) =>
      match @value.wire_emit_next_construction_inventory(active) {
        Some(value) => Some(value)
        None => return None
      }
    None =>
      if cursor.phase == 2 {
        Some(@value.wire_emit_start_construction_inventory())
      } else {
        None
      }
  }
  Some(keyed_request_wire_inventory(cursor.generation, fragment, writer, typed))
}

///|
pub fn cancel_keyed_request_wire(cursor : KeyedRequestWireCursor) -> Unit {
  if !cursor.closed {
    if cursor.active is Some(active) {
      @value.cancel_wire_emit(active)
    }
    cursor.active = None
    @encode.cancel_writer(cursor.writer)
    cursor.closed = true
    if cursor.generation < 9007199254740991L {
      cursor.generation += 1L
    }
  }
}

///|
/// The caller funds next_inventory before entry and rechecks progress after
/// callbacks. Exactly one existing emission step runs, then drains its same
/// buffer. No measuring serialization or second Value/Source walk occurs.
pub fn advance_keyed_request_wire(
  cursor : KeyedRequestWireCursor,
) -> KeyedRequestWirePoll {
  if cursor.closed {
    return WireFailed(Encoding(@encode.ClosedWriter))
  }
  if cursor.generation == 9007199254740991L {
    cancel_keyed_request_wire(cursor)
    return WireFailed(Encoding(@encode.OutputLimit))
  }
  cursor.generation += 1L
  let before_bytes = @encode.observed_writer_usage(cursor.writer).0
  try {
    match cursor.phase {
      0 => {
        @encode.begin_object(cursor.writer)
        cursor.phase = 1
      }
      1 =>
        if cursor.field == cursor.request.fields.length() {
          @encode.end_object(cursor.writer)
          cursor.phase = 4
        } else {
          @encode.key(cursor.writer, cursor.request.fields[cursor.field].0)
          cursor.phase = 2
        }
      2 => {
        cursor.active = Some(
          @value.start_wire_emit(
            cursor.request.fields[cursor.field].1.value,
            cursor.writer,
          ),
        )
        cursor.phase = 3
      }
      3 =>
        if @value.advance_wire_emit(cursor.active.unwrap()) {
          cursor.active = None
          cursor.field += 1
          cursor.phase = 1
        }
      4 => {
        let (bytes, nodes, depth) = @encode.finish_buffered_usage(cursor.writer)
        cursor.closed = true
        return WireComplete(bytes, nodes, depth)
      }
      _ => raise @encode.InvalidStructure
    }
    // No output means no buffer transfer or replacement is needed.
    if @encode.observed_writer_usage(cursor.writer).0 == before_bytes {
      return WireContinue
    }
    let fragment = @encode.drain_buffered_output(cursor.writer)
    cursor.fragment_peak_utf16 = Int::max(
      cursor.fragment_peak_utf16,
      fragment.length(),
    )
    if fragment.is_empty() {
      WireContinue
    } else {
      WireFragment(fragment)
    }
  } catch {
    issue => {
      cancel_keyed_request_wire(cursor)
      WireFailed(Encoding(issue))
    }
  }
}
