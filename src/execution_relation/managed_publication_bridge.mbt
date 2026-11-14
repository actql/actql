///|
/// Original producer re-admission dimensions. This immutable data projection
/// is not execution authority; a backend must bind it to its sealed policy and
/// exact live Run before publication borrows it. Final Result encoding and
/// ordering workspace are deliberately absent from this ingress record.
pub(all) struct ManagedPublicationBridgeLimits {
  entries : Int
  name_bytes : Int
  max_rows : Int
  values : ValueLimits
  row : RetainedRowDecodeLimits
}

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
  mut completed : CompletedOutput?
}

///|
/// Re-admission inherits the exact receiving identities already verified by
/// managed completion. It does not reacquire or require a live upstream input.
/// This private constructor cannot turn raw material into completion proof.
fn[T] prepare_managed_bridge_output_port(
  output : ManagedCompletedOutput[T],
  max_entries : Int,
  max_name_bytes : Int,
  verify : (Unit) -> AdmittedOutputRows?,
) -> Result[TrustedOutputPort[Unit], TrustedOutputIssue] {
  if max_entries < 0 || max_name_bytes < 0 {
    return Err(InvalidLimits)
  }
  if !managed_completed_output_available(output) {
    return Err(Unverified)
  }
  if output.bindings.length() > max_entries {
    return Err(Limit)
  }
  let (id, names, _) = match
    validate_trusted_output_contract(
      output.preparation,
      output.target,
      max_entries,
      max_name_bytes,
      None,
      verified_managed_inputs=true,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({
    generated: output.preparation,
    target: output.target,
    id,
    names,
    verify,
    input_bindings: output.bindings.copy(),
  })
}

///|
/// Geometry for re-admitting this already measured original. Policy ceilings
/// remain the execution checks; they are not retained row/body demand.
pub fn[T] managed_publication_bridge_import_geometry(
  output : ManagedCompletedOutput[T],
  material : ManagedRetainedOutput[T],
  max_columns : Int,
  max_row_bytes : Int,
) -> ManagedPublicationBridgeLimits? {
  if !managed_completed_output_available(output) ||
    !managed_completed_output_matches_material(output, material) {
    return None
  }
  let receipt = material.receipt
  guard managed_output_value_row_wire_bound(
      receipt,
      None,
      max_columns,
      max_row_bytes,
    )
    is Some(bytes) else {
    return None
  }
  // Cached canonical cell nodes plus row/field wrappers bound one parser
  // window. Text/wire bytes remain a separate dimension, never node demand.
  guard checked_preparation_add_product(1L, receipt.measured.2.to_int64(), 2L)
    is Some(nodes) &&
    checked_preparation_add_product(
      nodes,
      @schema.field_count(receipt.schema).to_int64(),
      2L,
    )
    is Some(nodes) &&
    nodes <= 2147483647L &&
    receipt.measured_depth <= 2147483645 else {
    return None
  }
  Some({
    entries: Int::max(
      output.bindings.length(),
      @schema.field_count(receipt.schema),
    ),
    name_bytes: bytes,
    max_rows: receipt.rows,
    values: {
      max_nodes: receipt.usage.nodes,
      max_text_bytes: receipt.usage.text_bytes,
      max_depth: receipt.measured_depth,
      max_work: receipt.usage.work,
    },
    row: {
      max_bytes: bytes,
      max_nodes: nodes.to_int(),
      max_depth: receipt.measured_depth + 2,
      max_text_bytes: bytes,
    },
  })
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
    prepare_managed_bridge_output_port(output, max_entries, max_name_bytes, fn(
      _,
    ) {
      if live.val && managed_completed_output_available(output) {
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
    output,
    references,
    admitted,
    rows,
    port,
    live,
    imported_rows: 0,
    finished: false,
    completed: None,
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
  let appended = match bridge.references {
    ReferenceFree => append_admitted_output_wire(bridge.admitted, text, limits)
    ExactRows => {
      guard receipt.reference_rows.get(bridge.imported_rows)
        is Some(source_references) else {
        close_managed_publication_bridge(bridge)
        return Err(Wire(InvalidShape))
      }
      append_admitted_output_wire_references(
        bridge.admitted,
        text,
        limits,
        reference_cells=source_references,
      )
    }
  }
  match appended {
    Ok(_) => {
      bridge.imported_rows += 1
      Ok(())
    }
    Err(Wire(issue)) => {
      close_managed_publication_bridge(bridge)
      Err(Wire(issue))
    }
    Err(Admission(issue)) => {
      close_managed_publication_bridge(bridge)
      Err(Admission(issue))
    }
  }
}

///|
/// A private Table projection still belongs to this exact completed generation.
/// It is not a public Result occurrence or publication capability.
pub fn[T] managed_publication_bridge_matches_table_input_export(
  bridge : ManagedPublicationBridge[T],
  output : ManagedCompletedOutput[T],
  preparation : CompletedTableInputRelationExportPreparation,
  occurrence : ManagedTableInputOccurrence,
) -> Bool {
  bridge.live.val &&
  managed_completed_output_available(output) &&
  managed_completed_same_occurrence(bridge.output, output) &&
  (match bridge.completed {
    Some(value) =>
      completed_table_input_export_preparation_matches_owner(
        preparation, occurrence, value,
      )
    None => false
  })
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
    Ok(value) => {
      // Only the existing full-copy rule can seal this original occurrence.
      // Keep the bridge's readmission, generation and live callback unchanged.
      let converted = match
        bridge.output.material.receipt.completed_projection {
        Some((identity, target)) if target == value.target &&
          physical_equal(
            bridge.output.material.receipt.owner,
            @lower.sequence_owner(value.completion.sequence),
          ) =>
          {
            ..value,
            completion: { ..value.completion, result_identity: identity, },
          }
        _ => value
      }
      bridge.completed = Some(converted)
      Ok(converted)
    }
    Err(issue) => {
      bridge.live.val = false
      Err(Completion(issue))
    }
  }
}

///|
/// Match the exact re-admitted output owned by this bridge, not its value or
/// logical CID. A closed bridge cannot issue new export evidence.
pub fn[T] managed_publication_bridge_matches_result_export(
  bridge : ManagedPublicationBridge[T],
  output : ManagedCompletedOutput[T],
  preparation : CompletedResultRelationExportPreparation,
  occurrence : ManagedResultOccurrence,
) -> Bool {
  bridge.live.val &&
  managed_completed_output_available(output) &&
  managed_completed_same_occurrence(bridge.output, output) &&
  (match bridge.completed {
    Some(value) =>
      completed_result_export_preparation_matches_owner(
        preparation, occurrence, value,
      )
    None => false
  })
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

///|
/// Callback-free derived-view lifetime only. It does not observe physical
/// availability, authorize a read, or acknowledge original reader cleanup.
pub fn[T] managed_publication_bridge_retained(
  bridge : ManagedPublicationBridge[T],
) -> Bool {
  bridge.live.val
}
