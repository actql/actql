///|
/// Bounded re-admission of one exact managed Relation generation for formal
/// publication. The installed representation reader supplies rows while the
/// common runtime retains the completion, schema, and occurrence authority.
struct ManagedPublicationBridge[T] {
  output : ManagedCompletedOutput[T]
  references : ManagedProducerReferences
  admitted : AdmittedOutput
  rows : Ref[AdmittedOutputRows?]
  port : TrustedOutputPort[Unit]
  live : Ref[Bool]
  mut imported_rows : Int
  mut finished : Bool
}

///|
pub fn[T] prepare_managed_publication_bridge(
  output : ManagedCompletedOutput[T],
  material : ManagedRetainedOutput[T],
  max_rows : Int,
  values : ValueLimits,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[ManagedPublicationBridge[T], ManagedProducerBridgeIssue] {
  if !managed_completed_output_available(output) ||
    !managed_completed_output_matches_material(output, material) {
    return Err(Unavailable)
  }
  let receipt = output.material.receipt
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
      completion_preparation_owner(output.preparation),
      output.target,
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
      output.preparation,
      output.target,
      max_entries,
      max_name_bytes,
      fn(_) {
        if live.val && managed_completed_output_available(output) {
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
  Ok({
    output,
    references,
    admitted,
    rows,
    port,
    live,
    imported_rows: 0,
    finished: false,
  })
}

///|
pub fn[T] append_managed_publication_bridge_wire(
  bridge : ManagedPublicationBridge[T],
  text : String,
  limits : RetainedRowDecodeLimits,
) -> Result[Unit, ManagedProducerBridgeIssue] {
  if !bridge.live.val ||
    bridge.finished ||
    !managed_completed_output_available(bridge.output) {
    return Err(Closed)
  }
  let receipt = bridge.output.material.receipt
  let decoded = match bridge.references {
    ReferenceFree => decode_retained_row(receipt.schema, text, limits)
    ExactRows => {
      guard receipt.reference_rows.get(bridge.imported_rows)
        is Some(source_references) else {
        close_managed_publication_bridge(bridge)
        return Err(Wire(InvalidShape))
      }
      decode_retained_row(
        receipt.schema,
        text,
        limits,
        reference_cells=source_references,
      )
    }
  }
  let values = match decoded {
    Ok(values) => values
    Err(issue) => {
      close_managed_publication_bridge(bridge)
      return Err(Wire(issue))
    }
  }
  match append_admitted_output(bridge.admitted, values) {
    Ok(_) => {
      bridge.imported_rows += 1
      Ok(())
    }
    Err(issue) => {
      close_managed_publication_bridge(bridge)
      Err(Admission(issue))
    }
  }
}

///|
pub fn[T] finish_managed_publication_bridge(
  bridge : ManagedPublicationBridge[T],
) -> Result[CompletedOutput, ManagedProducerBridgeIssue] {
  if !bridge.live.val ||
    bridge.finished ||
    !managed_completed_output_available(bridge.output) ||
    bridge.imported_rows != bridge.output.material.receipt.rows {
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
  match complete_trusted_output(bridge.port, ()) {
    Ok(value) => Ok(value)
    Err(issue) => {
      bridge.live.val = false
      Err(Completion(issue))
    }
  }
}

///|
pub fn[T] close_managed_publication_bridge(
  bridge : ManagedPublicationBridge[T],
) -> Unit {
  if bridge.live.val {
    bridge.live.val = false
    if !bridge.finished {
      cancel_admitted_output(bridge.admitted) |> ignore
    }
  }
}
