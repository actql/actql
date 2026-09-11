///|
priv struct SequenceRunLimits {
  max_rows : Int
  metadata_entries : Int
  retained_entries : Int
  operation_entries : Int
  input_values : ValueLimits
  output_values : ValueLimits
}

///|
priv enum SequenceRunIssue {
  InvalidLimits
  InputOwnership
  InputSet
  InputExecutionEvidencePending(Int)
  InputLimit
  InputKey(Int, InputKeyIssue)
  Wiring(WiringIssue)
  Capture(Int, CaptureIssue)
  Rows(Int, RowIssue)
  Store(StoreIssue)
}

///|
fn charge_capture_rows(input : CapturedRows, budget : ValueBudget) -> Bool {
  for row in input.rows {
    if !charge_node(budget, 1) {
      return false
    }
    for j = 0; j < row.length(); j = j + 1 {
      let name = @schema.reference_name(
        @schema.field_at(input.schema, j).unwrap().name,
      )
      if !charge_text(budget, name) || !measure(row[j], 2, budget) {
        return false
      }
    }
  }
  true
}

///|
/// Internal component driver only. Its future caller must discharge registry,
/// input key/order/capacity and runtime obligations before offering execution.
/// It never accepts arbitrary JSON, skips a prepared operation or returns a
/// partial store. This is the single driver for these row-evaluation components.
fn evaluate_sequence_components(
  _contracts : RegisteredRelationContracts,
  sequence : @lower.PreparedSequence,
  supplied : Array[CapturedRows],
  retained_ids : Array[String],
  limits : SequenceRunLimits,
  control : ControlBudget,
) -> Result[TableStore, SequenceRunIssue] {
  if limits.max_rows < 0 ||
    limits.metadata_entries < 0 ||
    limits.retained_entries < 0 ||
    limits.operation_entries < 0 ||
    control.remaining < 0 ||
    control.max_frames < 0 {
    return Err(InvalidLimits)
  }
  let input_budget = match value_budget(limits.input_values) {
    Ok(v) => v
    Err(_) => return Err(InvalidLimits)
  }
  let output_budget = match value_budget(limits.output_values) {
    Ok(v) => v
    Err(_) => return Err(InvalidLimits)
  }
  let owner = @lower.sequence_owner(sequence)
  let pipeline = @lower.pipeline(@lower.bound_preparation(owner))
  let wiring = match
    prepare_wiring(owner, retained_ids, control, {
      limit: limits.metadata_entries,
      live: 0,
      peak: 0,
    }) {
    Ok(v) => v
    Err(e) => return Err(Wiring(e))
  }
  if supplied.length() != wiring.input_count {
    return Err(InputSet)
  }
  // All supplied owner/origin identities are checked before computation.
  // Input position is physical input ordinal, not an author alias.
  for i = 0; i < supplied.length(); i = i + 1 {
    if !spend_control(control, 1) {
      return Err(InputLimit)
    }
    if !physical_equal(supplied[i].owner, owner) {
      return Err(InputOwnership)
    }
    if supplied[i].origin != SuppliedInput(i) {
      return Err(InputSet)
    }
    // CapturedRows proves schema/value ownership, not that an upstream producer
    // successfully computed these exact rows. Never launder conditional producer
    // evidence through a raw capture, even when counts and keys happen to agree.
    if @pipeline.input_producer(pipeline, i) is Some(_) {
      return Err(InputExecutionEvidencePending(i))
    }
  }
  let store = match
    table_store(wiring, { limit: limits.retained_entries, live: 0, peak: 0, }) {
    Ok(v) => v
    Err(e) => return Err(Store(e))
  }
  let mut input_rows = 0
  for i = 0; i < supplied.length(); i = i + 1 {
    let captured = supplied[i]
    if captured.rows.length() > limits.max_rows - input_rows ||
      !charge_capture_rows(captured, input_budget) {
      return Err(InputLimit)
    }
    input_rows += captured.rows.length()
    match
      validate_captured_keys(captured, control, {
        limit: limits.operation_entries,
        live: 0,
        peak: 0,
      }) {
      Ok(_) => ()
      Err(e) => return Err(InputKey(i, e))
    }
    let table = match
      table_from_capture_bounded(captured, control, {
        limit: limits.operation_entries,
        live: 0,
        peak: 0,
      }) {
      Ok(v) => v
      Err(e) => return Err(Rows(i, e))
    }
    match install_table_input(store, i, table, control) {
      Ok(_) => ()
      Err(e) => return Err(Store(e))
    }
  }
  for i = 0; i < @lower.sequence_count(sequence); i = i + 1 {
    let table = match @lower.sequence_step(sequence, i).unwrap() {
      @lower.ValuesStep(_) => {
        let remaining = {
          ..limits.input_values,
          max_nodes: limits.input_values.max_nodes - input_budget.nodes,
          max_text_bytes: limits.input_values.max_text_bytes - input_budget.text,
          max_work: limits.input_values.max_work - input_budget.work,
        }
        let captured = match
          capture_values(
            owner,
            i,
            max_rows=limits.max_rows - input_rows,
            remaining,
          ) {
          Ok(v) => v
          Err(e) => return Err(Capture(i, e))
        }
        input_rows += captured.rows.length()
        input_budget.nodes += captured.usage.nodes
        input_budget.text += captured.usage.text_bytes
        input_budget.work += captured.usage.work
        match
          table_from_capture_bounded(captured, control, {
            limit: limits.operation_entries,
            live: 0,
            peak: 0,
          }) {
          Ok(v) => v
          Err(e) => return Err(Rows(i, e))
        }
      }
      @lower.RowStep(kernel) => {
        let route = wiring.routes[i]
        if route.length() != 1 {
          return Err(InputSet)
        }
        guard store.tables[route[0]] is Some(input) else {
          return Err(InputSet)
        }
        match
          evaluate_rows_with_workspace(
            kernel,
            input.table,
            limits.max_rows,
            control,
            output_budget,
            { limit: limits.operation_entries, live: 0, peak: 0, },
          ) {
          Ok(v) => v
          Err(e) => return Err(Rows(i, e))
        }
      }
    }
    match commit_table(store, i, table, control) {
      Ok(_) => ()
      Err(e) => return Err(Store(e))
    }
  }
  Ok(store)
}
