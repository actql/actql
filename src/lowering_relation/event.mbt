///|
/// Checked event-Bridge and TEA parameters retained for canonical emission.
struct PreparedEvent {
  node : PreparedNode
  params : PreparedEventParams
}

///|
priv enum PreparedEventParams {
  EventBridgeParams(String, String)
  EventWatermarkParams(Double, @event.Policy)
}

///|
pub(all) enum EventIssue {
  InvalidEventLimits
  InvalidEventWiring
  EventPreparationLimit
} derive(Eq, Debug)

///|
fn prepare_event_node(
  node : PreparedNode,
  max_bindings~ : Int,
  max_name_bytes~ : Int,
  max_work~ : Int,
) -> Result[(PreparedEvent, Int, Int, Int), EventIssue] {
  if max_bindings < 0 || max_name_bytes < 0 || max_work < 0 {
    return Err(InvalidEventLimits)
  }
  guard node.payload is EventValue(checked) else {
    return Err(InvalidEventWiring)
  }
  let (params, bindings, names, work) = match @event.options(checked) {
    @event.ToEvents => {
      guard @event.output(checked) is @carrier.EventValue(output) else {
        return Err(InvalidEventWiring)
      }
      let id = @schema.reference_name(@carrier.event_identity(output).name)
      let time = @schema.reference_name(@carrier.event_time(output).name)
      (
        EventBridgeParams(id, time),
        2,
        @utf8.encode(id).length() + @utf8.encode(time).length(),
        2,
      )
    }
    @event.Watermark(value, policy) =>
      (EventWatermarkParams(value, policy), 0, 0, 2)
    @event.Dedupe(_) | @event.Session(_) => return Err(InvalidEventWiring)
  }
  if bindings > max_bindings || names > max_name_bytes || work > max_work {
    return Err(EventPreparationLimit)
  }
  Ok(({ node, params, }, bindings, names, work))
}

///|
fn emit_event_node(
  prepared : PreparedEvent,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  @encode.key(out, "id")
  @encode.string_value(out, prepared.node.id)
  @encode.key(out, "in")
  @encode.begin_array(out)
  for input in prepared.node.inputs {
    @encode.string_value(out, input)
  }
  @encode.end_array(out)
  @encode.key(out, "op")
  @encode.string_value(out, operation(prepared.node))
  @encode.key(out, "params")
  @encode.begin_object(out)
  match prepared.params {
    EventBridgeParams(id, time) => {
      @encode.key(out, "id")
      @encode.string_value(out, id)
      @encode.key(out, "time")
      @encode.string_value(out, time)
    }
    EventWatermarkParams(value, policy) => {
      @encode.key(out, "policy")
      @encode.string_value(
        out,
        match policy {
          @event.Drop => "drop"
          @event.Mark => "mark"
        },
      )
      @encode.key(out, "watermark_ms")
      @encode.number_value(out, value)
    }
  }
  @encode.end_object(out)
  @encode.end_object(out)
}
