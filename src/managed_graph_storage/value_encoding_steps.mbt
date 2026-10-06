///|
priv enum ValueEncodingPhase {
  ResolveValueEncoding
  BeginValueEncoding
  NextValueEncoding
  EmitValueEncoding
  EndValueEncoding
  FinishValueEncoding
  ValueEncodingFinished
} derive(Eq)

///|
/// A staged operation of this Storage owner's existing bounded wire sink.
/// Input values are borrowed, immutable admitted leaves/trees. The handle owns
/// only its emission frames and writer; cleanup never clears the input array.
priv struct ValueEncoding {
  builder : Builder
  mut values : Array[@value.CheckedValue]?
  pending_bytes : Int
  pending_work : Int
  mut phase : ValueEncodingPhase
  mut node_limit : Int
  mut cap : Int
  mut index : Int
  mut writer : @encode.Writer?
  mut emission : @value.WireEmitCursor?
  identity_body : Bool
}

///|
priv enum ValueEncodingPoll {
  ValueEncodingContinue(work~ : Int)
  ValueEncodingComplete(String, bytes~ : Int, nodes~ : Int, work~ : Int)
  ValueEncodingFailed(Issue, work~ : Int)
}

///|
fn start_value_encoding(
  builder : Builder,
  values : Array[@value.CheckedValue],
  pending_bytes : Int,
  pending_work : Int,
  identity_body? : Bool = false,
) -> ValueEncoding {
  {
    builder,
    values: Some(values),
    pending_bytes,
    pending_work,
    phase: ResolveValueEncoding,
    node_limit: 0,
    cap: 0,
    index: 0,
    writer: None,
    emission: None,
    identity_body,
  }
}

///|
fn value_encoding_issue(value : ValueEncoding) -> Issue {
  if value.node_limit < value.builder.limits.max_value_nodes {
    WorkLimit
  } else {
    ValueLimit
  }
}

///|
fn value_encoding_failed(
  value : ValueEncoding,
  issue : Issue,
  work : Int,
) -> ValueEncodingPoll {
  value.phase = ValueEncodingFinished
  ValueEncodingFailed(issue, work~)
}

///|
fn advance_value_encoding(
  value : ValueEncoding,
  quantum : Int,
) -> ValueEncodingPoll {
  if quantum < 1 {
    return ValueEncodingFailed(InvalidLimits, work=0)
  }
  if value.phase == ValueEncodingFinished {
    return ValueEncodingFailed(Closed, work=0)
  }
  let mut used = 0
  while used < quantum {
    used += 1
    match value.phase {
      ResolveValueEncoding => {
        let limits = value.builder.limits
        if value.pending_work < 0 || value.pending_bytes < 0 {
          return value_encoding_failed(value, InvalidLimits, used)
        }
        if value.pending_work > limits.max_work - value.builder.work {
          return value_encoding_failed(value, WorkLimit, used)
        }
        value.node_limit = Int::min(
          limits.max_value_nodes,
          limits.max_work - value.builder.work - value.pending_work,
        )
        if value.node_limit < 1 {
          return value_encoding_failed(value, WorkLimit, used)
        }
        if value.pending_bytes >
          limits.max_total_value_bytes - value.builder.value_bytes {
          return value_encoding_failed(value, ValueLimit, used)
        }
        value.cap = Int::min(
          limits.max_value_bytes,
          limits.max_total_value_bytes -
          value.builder.value_bytes -
          value.pending_bytes,
        )
        value.writer = Some(
          @encode.writer(value.cap, value.node_limit, limits.max_value_depth) catch {
            _ =>
              return value_encoding_failed(
                value,
                value_encoding_issue(value),
                used,
              )
          },
        )
        value.phase = BeginValueEncoding
      }
      BeginValueEncoding => {
        @encode.begin_array(value.writer.unwrap()) catch {
          _ =>
            return value_encoding_failed(
              value,
              value_encoding_issue(value),
              used,
            )
        }
        value.phase = NextValueEncoding
      }
      NextValueEncoding => {
        guard value.values is Some(values) else {
          return value_encoding_failed(value, Closed, used)
        }
        if values.get(value.index) is Some(checked) {
          let payload = if value.identity_body {
            guard @value.json_payload(checked.value) is Some(payload) else {
              return value_encoding_failed(value, InvalidIdentity, used)
            }
            payload
          } else {
            checked.value
          }
          value.emission = Some(
            @value.start_wire_emit(payload, value.writer.unwrap()),
          )
          value.phase = EmitValueEncoding
        } else {
          value.values = None
          value.phase = EndValueEncoding
        }
      }
      EmitValueEncoding => {
        let complete = @value.advance_wire_emit(value.emission.unwrap()) catch {
          _ =>
            return value_encoding_failed(
              value,
              value_encoding_issue(value),
              used,
            )
        }
        if complete {
          value.emission = None
          value.index += 1
          value.phase = NextValueEncoding
        }
      }
      EndValueEncoding => {
        @encode.end_array(value.writer.unwrap()) catch {
          _ =>
            return value_encoding_failed(
              value,
              value_encoding_issue(value),
              used,
            )
        }
        value.phase = FinishValueEncoding
      }
      FinishValueEncoding => {
        let (text, bytes, nodes, _) = @encode.finish_text_usage(
          value.writer.unwrap(),
        ) catch {
          _ =>
            return value_encoding_failed(
              value,
              value_encoding_issue(value),
              used,
            )
        }
        value.writer = None
        value.phase = ValueEncodingFinished
        return ValueEncodingComplete(text, bytes~, nodes~, work=used)
      }
      ValueEncodingFinished => return ValueEncodingFailed(Closed, work=used)
    }
  }
  ValueEncodingContinue(work=used)
}

///|
fn cleanup_value_encoding(value : ValueEncoding) -> Unit {
  if value.emission is Some(emission) {
    @value.cancel_wire_emit(emission)
  }
  if value.writer is Some(writer) {
    @encode.cancel_writer(writer)
  }
  value.emission = None
  value.writer = None
  value.values = None
  value.phase = ValueEncodingFinished
}
