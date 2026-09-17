///|
/// Representation-neutral, scoped bridge from one exact managed producer use
/// to the ordinary checked Local reader. A registered provider supplies values;
/// this type never interprets a path, backend name, or provider payload.
struct ManagedProducerBridge[T] {
  input : ManagedProducerRead[T]
  admitted : AdmittedOutput
  rows : Ref[AdmittedOutputRows?]
  port : TrustedOutputPort[Unit]
  live : Ref[Bool]
  mut finished : Bool
}

///|
pub(all) enum ManagedProducerBridgeIssue {
  Unavailable
  Admission(CaptureIssue)
  Wire(RetainedRowDecodeIssue)
  Completion(TrustedOutputIssue)
  Binding(ProducerBindingIssue)
  View(ProducerReadIssue)
  Closed
}

///|
/// Opening the bridge allocates only the bounded Local admission buffer. The
/// representation provider must separately pin and authorize the exact payload
/// for the whole scope through finish and the final Local read.
pub fn[T] prepare_managed_producer_bridge(
  input : ManagedProducerRead[T],
  max_rows : Int,
  values : ValueLimits,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[ManagedProducerBridge[T], ManagedProducerBridgeIssue] {
  if !managed_producer_read_available(input) {
    return Err(Unavailable)
  }
  let source = input.output
  let admitted = match
    prepare_admitted_output(
      completion_preparation_owner(source.preparation),
      source.target,
      max_rows,
      values,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Admission(issue))
  }
  let rows : Ref[AdmittedOutputRows?] = Ref(None)
  let live = Ref(true)
  let port = match
    prepare_trusted_output_port(
      source.preparation,
      source.target,
      max_entries,
      max_name_bytes,
      fn(_) {
        if live.val && managed_producer_read_available(input) {
          rows.val
        } else {
          None
        }
      },
    ) {
    Ok(value) => value
    Err(issue) => {
      cancel_admitted_output(admitted) |> ignore
      return Err(Completion(issue))
    }
  }
  Ok({ input, admitted, rows, port, live, finished: false, })
}

///|
/// A provider may use any registered physical reader, but it must submit every
/// ordered row through this checked schema admission boundary.
pub fn[T] append_managed_producer_bridge_wire(
  bridge : ManagedProducerBridge[T],
  text : String,
  limits : RetainedRowDecodeLimits,
) -> Result[Unit, ManagedProducerBridgeIssue] {
  if !bridge.live.val || bridge.finished {
    return Err(Closed)
  }
  if !managed_producer_read_available(bridge.input) {
    close_managed_producer_bridge(bridge)
    return Err(Unavailable)
  }
  let schema = bridge.input.output.material.receipt.schema
  let values = match decode_retained_row(schema, text, limits) {
    Ok(values) => values
    Err(issue) => {
      close_managed_producer_bridge(bridge)
      return Err(Wire(issue))
    }
  }
  match append_admitted_output(bridge.admitted, values) {
    Ok(_) => Ok(())
    Err(issue) => {
      close_managed_producer_bridge(bridge)
      Err(Admission(issue))
    }
  }
}

///|
/// Seal the imported values and bind them to the exact checked receiving port.
/// The returned ProducerRead remains unusable after this bridge is closed even
/// if a caller retained the opaque value.
pub fn[T] finish_managed_producer_bridge(
  bridge : ManagedProducerBridge[T],
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[ProducerRead, ManagedProducerBridgeIssue] {
  if !bridge.live.val ||
    bridge.finished ||
    !managed_producer_read_available(bridge.input) {
    return Err(Closed)
  }
  bridge.finished = true
  let rows = match finish_admitted_output(bridge.admitted) {
    Ok(value) => value
    Err(issue) => {
      bridge.live.val = false
      return Err(Admission(issue))
    }
  }
  bridge.rows.val = Some(rows)
  let output = match complete_trusted_output(bridge.port, ()) {
    Ok(value) => value
    Err(issue) => {
      bridge.live.val = false
      return Err(Completion(issue))
    }
  }
  let input = bridge.input
  let bound = match
    bind_completed_input(
      input.receiver,
      input.input_index,
      completion_preparation_owner(input.output.preparation),
      output,
    ) {
    Ok(value) => value
    Err(issue) => {
      bridge.live.val = false
      return Err(Binding(issue))
    }
  }
  prepare_producer_read(input.receiver, bound, max_entries, max_name_bytes).map_err(issue => {
      View(issue)
    },
  )
}

///|
/// End the provider use scope. This revokes every ProducerRead issued by the
/// bridge; representation pin release must happen after this call returns.
pub fn[T] close_managed_producer_bridge(
  bridge : ManagedProducerBridge[T],
) -> Unit {
  if bridge.live.val {
    bridge.live.val = false
    if !bridge.finished {
      cancel_admitted_output(bridge.admitted) |> ignore
    }
  }
}
