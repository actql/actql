///|
/// Representation-neutral, scoped bridge from one exact managed producer use
/// to the ordinary checked Local reader. A registered provider supplies values;
/// this type never interprets a path, backend name, or provider payload.
struct ManagedProducerBridge[T] {
  input : ManagedProducerRead[T]
  references : ManagedProducerReferences
  admitted : AdmittedOutput
  rows : Ref[AdmittedOutputRows?]
  port : TrustedOutputPort[Unit]
  live : Ref[Bool]
  mut imported_rows : Int
  mut finished : Bool
  mut handed_off : Bool
}

///|
priv enum ManagedProducerReferences {
  ExactRows
  ReferenceFree
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
/// A summary-backed managed view can omit a row-sized reference table only
/// when its complete schema cannot contain opaque reference values.
fn managed_schema_reference_free(
  schema : @schema.Schema,
  max_nodes : Int,
  reserve? : ((Int) -> Bool)? = None,
) -> Bool? {
  if max_nodes < 0 {
    return None
  }
  let pending = []
  let push = fn(contract) {
    if reserve is Some(reserve) && !reserve(pending.length() + 1) {
      false
    } else {
      pending.push(contract)
      true
    }
  }
  for index in 0..<@schema.field_count(schema) {
    if !push(@schema.field_at(schema, index).unwrap().contract) {
      return None
    }
  }
  let mut remaining = max_nodes
  while pending.pop() is Some(contract) {
    if remaining == 0 {
      return None
    }
    remaining -= 1
    match contract.shape {
      @contract.ResourceRef(..) | @contract.ContentRef(..) => return Some(false)
      @contract.Array(item, ..) => if !push(item) { return None }
      @contract.Object(fields) =>
        for index in 0..<@contract.field_count(fields) {
          if !push(@contract.field_at(fields, index).unwrap().contract) {
            return None
          }
        }
      _ => ()
    }
  }
  Some(true)
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
  deferred_reclamation? : Bool = false,
) -> Result[ManagedProducerBridge[T], ManagedProducerBridgeIssue] {
  if !managed_producer_read_available(input) {
    return Err(Unavailable)
  }
  let source = input.output
  let receipt = source.material.receipt
  let references = if receipt.reference_rows.length() == receipt.rows {
    ExactRows
  } else if receipt.reference_rows.length() == 0 &&
    managed_schema_reference_free(receipt.schema, max_entries) == Some(true) {
    ReferenceFree
  } else {
    return Err(Wire(InvalidShape))
  }
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
  admitted.buffer.deferred_reclamation = deferred_reclamation
  let rows : Ref[AdmittedOutputRows?] = Ref(None)
  let live = Ref(true)
  let port = match
    prepare_managed_bridge_output_port(source, max_entries, max_name_bytes, fn(
      _,
    ) {
      if live.val && managed_producer_read_available(input) {
        rows.val
      } else {
        None
      }
    }) {
    Ok(value) => value
    Err(issue) => {
      cancel_admitted_output(admitted) |> ignore
      return Err(Completion(issue))
    }
  }
  Ok({
    input,
    references,
    admitted,
    rows,
    port,
    live,
    imported_rows: 0,
    finished: false,
    handed_off: false,
  })
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
  let decoded = match bridge.references {
    ReferenceFree => decode_retained_presence_cells(schema, text, limits)
    ExactRows => {
      guard bridge.input.output.material.receipt.reference_rows.get(
          bridge.imported_rows,
        )
        is Some(source_references) else {
        close_managed_producer_bridge(bridge)
        return Err(Wire(InvalidShape))
      }
      decode_retained_presence_cells(
        schema,
        text,
        limits,
        reference_cells=source_references,
      )
    }
  }
  let values = match decoded {
    Ok(values) => values
    Err(issue) => {
      close_managed_producer_bridge(bridge)
      return Err(Wire(issue))
    }
  }
  let appended = if @schema.all_fields_required(schema) {
    append_admitted_output(bridge.admitted, values.map(value => value.unwrap()))
  } else {
    let row = match
      admit_relation_row(schema, values, bridge.admitted.buffer.budget.limits) {
      Ok(row) => row
      Err(issue) => {
        close_managed_producer_bridge(bridge)
        return Err(Wire(Presence(issue)))
      }
    }
    append_admitted_output_presence(bridge.admitted, row)
  }
  match appended {
    Ok(_) => {
      bridge.imported_rows += 1
      Ok(())
    }
    Err(issue) => {
      close_managed_producer_bridge(bridge)
      Err(Admission(issue))
    }
  }
}

///|
/// Completed admission quantities from this same live import buffer. Parser
/// workspace must already be funded before append; this DATA is neither a
/// refund nor permission to read a producer. The original append/current
/// boundary supplies authority; this quantity read invokes no current port.
pub fn[T] managed_producer_bridge_import_usage(
  bridge : ManagedProducerBridge[T],
) -> ValueUsage? {
  if !bridge.live.val ||
    bridge.finished ||
    !bridge.admitted.buffer.open ||
    bridge.admitted.buffer.reading {
    return None
  }
  let budget = bridge.admitted.buffer.budget
  Some({ nodes: budget.nodes, text_bytes: budget.text, work: budget.work, })
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
    !managed_producer_read_available(bridge.input) ||
    bridge.imported_rows != bridge.input.output.material.receipt.rows {
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
  let binding = match input.consumer_step {
    Some(step) =>
      bind_completed_operation_input(
        input.receiver,
        step,
        input.input_index,
        completion_preparation_owner(input.output.preparation),
        output,
      )
    None =>
      bind_completed_input(
        input.receiver,
        input.input_index,
        completion_preparation_owner(input.output.preparation),
        output,
      )
  }
  let bound = match binding {
    Ok(value) => value
    Err(issue) => {
      bridge.live.val = false
      return Err(Binding(issue))
    }
  }
  match
    prepare_producer_read(input.receiver, bound, max_entries, max_name_bytes) {
    Ok(read) => {
      bridge.handed_off = true
      Ok(read)
    }
    Err(issue) => Err(View(issue))
  }
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
      revoke_admitted_buffer(bridge.admitted.buffer)
    }
  }
}

///|
/// Revoke the use scope immediately; retain private unfinished rows until
/// sliced reclamation finishes. A handed-off reader owns immutable sealed rows.
pub fn[T] advance_close_managed_producer_bridge(
  bridge : ManagedProducerBridge[T],
  quantum : Int,
) -> Bool {
  bridge.admitted.buffer.deferred_reclamation = true
  close_managed_producer_bridge(bridge)
  if bridge.handed_off {
    return true
  }
  if quantum <= 0 || bridge.admitted.buffer.reading {
    return false
  }
  bridge.rows.val = None
  if bridge.admitted.buffer.open ||
    !bridge.admitted.buffer.rows.is_empty() ||
    !bridge.admitted.buffer.presence_rows.is_empty() {
    revoke_admitted_buffer(bridge.admitted.buffer)
  }
  advance_admitted_buffer_reclamation(bridge.admitted.buffer, quantum)
}
