///|
priv enum IdentityStreamPhase {
  Begin
  Values
  End
  Finish
  Done
}

///|
/// The existing wire emitter writes at most one 64-unit string chunk (at
/// most 384 escaped bytes plus punctuation), scalar or container per poll.
/// Reference envelopes use the same bounded canonical emitter. Draining after
/// every frame bounds assembly independently of the complete identity length.
priv struct IdentityStream {
  values : Array[@value.CheckedValue]
  writer : @encode.Writer
  mut phase : IdentityStreamPhase
  mut index : Int
  mut wire : @value.WireEmitCursor?
  mut piece : String
  mut offset : Int
}

///|
priv struct IdentityComparison {
  left : IdentityStream
  right : IdentityStream
}

///|
fn identity_stream(
  builder : Builder,
  values : Array[@value.CheckedValue],
) -> IdentityStream raise @encode.EncodeFailure {
  {
    values,
    writer: @encode.buffered_hashing_writer(
      builder.limits.max_value_bytes,
      builder.limits.max_value_nodes,
      builder.limits.max_value_depth,
      512,
    ),
    phase: Begin,
    index: 0,
    wire: None,
    piece: "",
    offset: 0,
  }
}

///|
fn advance_identity_stream(
  stream : IdentityStream,
) -> Unit raise @encode.EncodeFailure {
  match stream.phase {
    Begin => {
      @encode.begin_array(stream.writer)
      stream.phase = Values
    }
    Values =>
      if stream.index == stream.values.length() {
        stream.phase = End
      } else {
        if stream.wire is None {
          stream.wire = Some(
            @value.start_wire_emit(
              stream.values[stream.index].value,
              stream.writer,
            ),
          )
        }
        if @value.advance_wire_emit(stream.wire.unwrap()) {
          stream.wire = None
          stream.index += 1
        }
      }
    End => {
      @encode.end_array(stream.writer)
      stream.phase = Finish
    }
    Finish => {
      @encode.finish_hash_metrics(stream.writer) |> ignore
      stream.phase = Done
      return
    }
    Done => return
  }
  stream.piece = @encode.drain_hash_output(stream.writer)
  stream.offset = 0
}

///|
/// Hashes only select a collision bucket. Equality is exact canonical wire
/// equality, including escaping, Unicode and reference envelope contents.
/// Each poll emits one frame or compares at most 64 UTF-16 units; fragment
/// boundaries are not part of identity and may differ between the two streams.
fn advance_identity_comparison(
  comparison : IdentityComparison,
) -> Bool? raise @encode.EncodeFailure {
  let left = comparison.left
  let right = comparison.right
  if left.offset == left.piece.length() && !(left.phase is Done) {
    advance_identity_stream(left)
    return None
  }
  if right.offset == right.piece.length() && !(right.phase is Done) {
    advance_identity_stream(right)
    return None
  }
  let left_end = left.offset == left.piece.length()
  let right_end = right.offset == right.piece.length()
  if left_end || right_end {
    return Some(left_end && right_end)
  }
  for _ in 0..<64 {
    if left.offset == left.piece.length() ||
      right.offset == right.piece.length() {
      break
    }
    if left.piece[left.offset] != right.piece[right.offset] {
      return Some(false)
    }
    left.offset += 1
    right.offset += 1
  }
  None
}

///|
fn cancel_identity_comparison(comparison : IdentityComparison) -> Unit {
  for stream in [comparison.left, comparison.right] {
    if stream.wire is Some(wire) {
      @value.cancel_wire_emit(wire)
      stream.wire = None
    }
    @encode.cancel_writer(stream.writer)
    stream.piece = ""
    stream.offset = 0
    stream.phase = Done
  }
}

///|
fn record_identity_values(
  builder : Builder,
  record : Record,
) -> Array[@value.CheckedValue] {
  let result = []
  for name in builder.identities {
    for (field, value) in record.fields {
      if @schema.reference_name(field) == name {
        result.push(value)
        break
      }
    }
  }
  result
}

///|
/// The legacy synchronous API shares exact equality with the resumed owner;
/// it does not define a second key domain or rely on digest collision freedom.
fn identity_equal(
  builder : Builder,
  left : Array[@value.CheckedValue],
  right : Array[@value.CheckedValue],
) -> Bool raise @encode.EncodeFailure {
  let comparison : IdentityComparison = {
    left: identity_stream(builder, left),
    right: identity_stream(builder, right),
  }
  errdefer cancel_identity_comparison(comparison)
  while true {
    if advance_identity_comparison(comparison) is Some(equal) {
      cancel_identity_comparison(comparison)
      return equal
    }
  } nobreak {
    false
  }
}
