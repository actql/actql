///|
priv enum CapturedTableInputKind {
  Cells(CapturedOutputPin)
  Resident(CapturedResidentGenerationPin)
}

///|
/// Private closed Table input on the existing task's physical custody. It has
/// no public Result port, row-Effect grant or independent allocation ledger.
struct CapturedTableInputBorrow {
  occurrence : @execution.ManagedTableInputOccurrence
  kind : CapturedTableInputKind
}

///|
struct CapturedTableInputOutputSet {
  borrows : Array[CapturedTableInputBorrow]
  mut live : Bool
}

///|
pub fn borrow_captured_table_input_output(
  run : CapturedDAG,
  task : Int,
  occurrence : @execution.ManagedTableInputOccurrence,
  max_pins : Int,
) -> Result[CapturedTableInputBorrow, RunIssue] {
  let owner = @execution.managed_table_input_occurrence_owner(occurrence)
  let target = @ports.table_input_target(
    @execution.managed_table_input_occurrence_definition(occurrence),
  )
  match resident_generation_borrow_ready(run, task, owner, target, max_pins) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match run.outputs[task] {
    Some(Materialized(_)) => {
      let pin = match
        pin_captured_task_completion_internal(
          run, task, target, max_pins, false,
        ) {
        Ok(pin) => pin
        Err(issue) => return Err(issue)
      }
      if !@execution.completed_output_matches_port(pin.output, owner, target) {
        release_captured_output_pin(pin) |> ignore
        return Err(ForeignCandidate)
      }
      Ok({ occurrence, kind: Cells(pin), })
    }
    Some(Managed(_)) =>
      acquire_captured_resident_generation_pin(run, task, max_pins).map(pin => {
        occurrence,
        kind: Resident(pin),
      })
    Some(CarrierManaged(_)) => Err(UnsupportedGraph)
    None => Err(NotReady)
  }
}

///|
pub fn captured_table_input_borrow_occurrence(
  value : CapturedTableInputBorrow,
) -> @execution.ManagedTableInputOccurrence {
  value.occurrence
}

///|
pub fn captured_table_input_borrow_available(
  value : CapturedTableInputBorrow,
) -> Bool {
  match value.kind {
    Cells(pin) =>
      @execution.completed_output_available(
        captured_output_pin_materialized(pin),
      )
    Resident(pin) => captured_resident_generation_pin_available(pin)
  }
}

///|
fn captured_table_input_borrow_retained(
  value : CapturedTableInputBorrow,
) -> Bool {
  match value.kind {
    Cells(pin) => pin.live
    Resident(pin) => pin.live
  }
}

///|
/// Semantic inventory may name a private input once, but every consumer still
/// owns its own pin. Equal content or names cannot substitute another task,
/// checked declaration, Run or retained generation.
pub fn captured_table_input_borrows_share_view(
  first : CapturedTableInputBorrow,
  second : CapturedTableInputBorrow,
) -> Bool {
  if !captured_table_input_borrow_available(first) ||
    !captured_table_input_borrow_available(second) {
    return false
  }
  let same_producer = match (first.kind, second.kind) {
    (Cells(a), Cells(b)) =>
      physical_equal(a.run, b.run) &&
      a.task == b.task &&
      physical_equal(a.output, b.output)
    (Resident(a), Resident(b)) =>
      physical_equal(a.run, b.run) &&
      a.task == b.task &&
      (match (a.reference, b.reference) {
        (Managed(first), Managed(second)) => physical_equal(first, second)
        (Carrier(first), Carrier(second)) => physical_equal(first, second)
        _ => false
      })
    _ => false
  }
  same_producer &&
  physical_equal(
    @execution.managed_table_input_occurrence_owner(first.occurrence),
    @execution.managed_table_input_occurrence_owner(second.occurrence),
  ) &&
  physical_equal(
    @execution.managed_table_input_occurrence_definition(first.occurrence),
    @execution.managed_table_input_occurrence_definition(second.occurrence),
  )
}

///|
pub fn[T] captured_table_input_borrow_matches_managed(
  value : CapturedTableInputBorrow,
  output : @execution.ManagedCompletedOutput[T],
) -> Bool {
  guard value.kind is Resident(pin) && pin.reference is Managed(reference) else {
    return false
  }
  captured_table_input_borrow_available(value) &&
  @execution.managed_completed_reference_matches(reference, output) &&
  @execution.managed_completed_output_matches_port(
    output,
    @execution.managed_table_input_occurrence_owner(value.occurrence),
    @ports.table_input_target(
      @execution.managed_table_input_occurrence_definition(value.occurrence),
    ),
  )
}

///|
pub fn captured_table_input_borrow_cell_output(
  value : CapturedTableInputBorrow,
) -> @execution.CompletedOutput? {
  match value.kind {
    Cells(pin) if captured_table_input_borrow_available(value) =>
      Some(captured_output_pin_materialized(pin))
    _ => None
  }
}

///|
/// Read the same retained generation's verified inventory, never its rows.
pub fn captured_table_input_borrow_row_count(
  value : CapturedTableInputBorrow,
) -> Int? {
  match value.kind {
    Cells(pin) if pin.live =>
      if @execution.completed_output_available(pin.output) {
        Some(@execution.completed_row_count(pin.output))
      } else {
        None
      }
    Resident(pin) if pin.live =>
      match pin.reference {
        Managed(reference) =>
          @execution.managed_completed_reference_row_count(reference)
        Carrier(_) => None
      }
    _ => None
  }
}

///|
pub fn release_captured_table_input_borrow(
  value : CapturedTableInputBorrow,
) -> Bool {
  match value.kind {
    Cells(pin) => release_captured_output_pin(pin)
    Resident(pin) => release_captured_resident_generation_pin(pin)
  }
}

///|
pub fn start_captured_table_input_borrow_export(
  value : CapturedTableInputBorrow,
  view_limits : @execution.CompletedResultViewLimits,
  max_rows : Int,
  values : @execution.ValueLimits,
  payload_wire : @execution.RowWireLimits,
  logical_wire : @execution.RowWireLimits,
  schema_limits : @execution.RelationSchemaIdentityLimits,
  max_batch_bytes : Int,
) -> Result[
  @execution.CompletedTableInputRelationExportPreparation,
  @execution.CompletedExportIssue,
] {
  guard captured_table_input_borrow_cell_output(value) is Some(source) else {
    return Err(NotCellRepresentation)
  }
  @execution.start_completed_table_input_relation_export(
    source,
    value.occurrence,
    view_limits,
    max_rows,
    values,
    payload_wire,
    logical_wire,
    schema_limits,
    max_batch_bytes,
  )
}

///|
/// Atomic acquisition shares the same per-task pin ceiling with all existing
/// Result consumers. Rollback releases only these newly acquired pins.
pub fn pin_captured_table_input_output_set(
  run : CapturedDAG,
  requests : Array[(Int, @execution.ManagedTableInputOccurrence)],
  max_pins : Int,
) -> Result[CapturedTableInputOutputSet, RunIssue] {
  let borrows = []
  for (task, occurrence) in requests {
    match borrow_captured_table_input_output(run, task, occurrence, max_pins) {
      Ok(borrow) => borrows.push(borrow)
      Err(issue) => {
        for borrow in borrows {
          release_captured_table_input_borrow(borrow) |> ignore
        }
        return Err(issue)
      }
    }
  }
  Ok({ borrows, live: true, })
}

///|
pub fn captured_table_input_output_set_borrow_at(
  value : CapturedTableInputOutputSet,
  index : Int,
) -> CapturedTableInputBorrow? {
  if value.live {
    value.borrows.get(index)
  } else {
    None
  }
}

///|
pub fn release_captured_table_input_output_set(
  value : CapturedTableInputOutputSet,
) -> Bool {
  if !value.live {
    return false
  }
  value.live = false
  for borrow in value.borrows {
    release_captured_table_input_borrow(borrow) |> ignore
  }
  true
}
