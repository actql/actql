///|
pub(all) struct SequenceRunLimits {
  max_rows : Int
  metadata_entries : Int
  retained_entries : Int
  operation_entries : Int
  input_values : ValueLimits
  output_values : ValueLimits
}

///|
pub(all) enum SequenceRunIssue {
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
  OrderedContext(Int, OrderedLimitsIssue)
  FragmentContext(Int, FragmentRuntimeIssue)
  MissingFragmentContext(Int)
  MixedExecutionConfiguration
  UnsupportedRowComparison(Int, @schema.FieldName)
}

///|
priv enum SequenceInput {
  RawInput(CapturedRows)
  ProducerInput(BoundProducerInput)
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
  contracts : RegisteredRelationContracts,
  sequence : @lower.PreparedSequence,
  supplied : Array[CapturedRows],
  retained_ids : Array[String],
  limits : SequenceRunLimits,
  control : ControlBudget,
  produced? : Array[BoundProducerInput] = [],
  fragments? : Array[FragmentRuntimeContext]? = None,
  join_ceiling? : (Int, Int64)? = None,
  ordered? : OrderedExecution = {
    contexts: [],
    max_bytes: 0,
    max_nodes: 0,
    max_depth: 0,
  },
) -> Result[CompletedSequence, SequenceRunIssue] {
  // Bounded representation selection, before execution and never as recovery
  // from a failed row invocation. Oversized metadata follows normal admission.
  if produced.length() <= limits.metadata_entries &&
    produced.any(bound => {
      match bound.output.table {
        RowTable(_) => false
        NumberTable(_) | AdmittedTable(_) => true
      }
    }) {
    return evaluate_physical_sequence(
      contracts,
      sequence,
      supplied,
      retained_ids,
      limits,
      control,
      produced,
      fragments,
      ordered,
      join_ceiling~,
    )
  }
  let invocation = match
    prepare_sequence_invocation(
      contracts,
      sequence,
      supplied,
      retained_ids,
      limits,
      control,
      produced~,
      fragments~,
      ordered~,
    ) {
    Ok(invocation) => invocation
    Err(issue) => return Err(issue)
  }
  run_sequence_invocation(invocation, join_ceiling~)
}

///|
/// Private, invocation-local state after input admission. Neither a reusable
/// prepared plan nor successful execution evidence. All budgets are fresh per
/// invocation; no partial output is accessible through the public API.
priv struct SequenceInvocation[T] {
  contracts : RegisteredRelationContracts
  sequence : @lower.PreparedSequence
  produced : Array[BoundProducerInput]
  limits : SequenceRunLimits
  control : ControlBudget
  input_budget : ValueBudget
  output_budget : ValueBudget
  input_rows : Int
  ordered_budgets : Map[Int, LogicalBudget]
  store : TableStore[T]
}

///|
fn prepare_sequence_invocation(
  contracts : RegisteredRelationContracts,
  sequence : @lower.PreparedSequence,
  supplied : Array[CapturedRows],
  retained_ids : Array[String],
  limits : SequenceRunLimits,
  control : ControlBudget,
  produced~ : Array[BoundProducerInput],
  fragments~ : Array[FragmentRuntimeContext]?,
  ordered~ : OrderedExecution,
) -> Result[SequenceInvocation[Table], SequenceRunIssue] {
  prepare_sequence_with_importers(
    contracts,
    sequence,
    supplied,
    retained_ids,
    limits,
    control,
    fn(captured) {
      table_from_capture_bounded(captured, control, {
        limit: limits.operation_entries,
        live: 0,
        peak: 0,
      })
    },
    fn(bound, id, output_budget) {
      guard bound.output.table is RowTable(source) else {
        return Err(InvalidRows)
      }
      let adopted : Table = {
        owner: bound.receiver,
        id,
        names: source.names,
        rows: source.rows,
      }
      match bound.projection {
        None => Ok(adopted)
        Some(projection) =>
          evaluate_row_body(
            CheckedProjection(projection),
            adopted,
            id,
            limits.max_rows,
            control,
            output_budget,
            { limit: limits.operation_entries, live: 0, peak: 0, },
          )
      }
    },
    produced~,
    fragments~,
    ordered~,
  )
}

///|
// Import callbacks own only physical representation. Owner/origin, evidence,
// key validation and receiver input budgets are enforced before each callback.
fn[T : RelationRows] prepare_sequence_with_importers(
  contracts : RegisteredRelationContracts,
  sequence : @lower.PreparedSequence,
  supplied : Array[CapturedRows],
  retained_ids : Array[String],
  limits : SequenceRunLimits,
  control : ControlBudget,
  import_raw : (CapturedRows) -> Result[T, RowIssue],
  import_producer : (BoundProducerInput, String, ValueBudget) -> Result[
    T,
    RowIssue,
  ],
  release_table? : (T) -> Unit = fn(_table) { () },
  reserve_storage? : ((T, RowWorkspace, ControlBudget) -> Bool)? = None,
  produced~ : Array[BoundProducerInput],
  fragments~ : Array[FragmentRuntimeContext]?,
  ordered~ : OrderedExecution,
) -> Result[SequenceInvocation[T], SequenceRunIssue] {
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
  let metadata = { limit: limits.metadata_entries, live: 0, peak: 0, }
  let wiring = match prepare_wiring(owner, retained_ids, control, metadata) {
    Ok(v) => v
    Err(e) => return Err(Wiring(e))
  }
  let ordered_budgets : Map[Int, LogicalBudget] = match fragments {
    None =>
      match
        prepare_ordered_budgets(contracts, sequence, ordered, control, metadata) {
        Ok(budgets) => budgets
        Err(e) => return Err(e)
      }
    Some(_) => {
      if !ordered.contexts.is_empty() ||
        ordered.max_bytes != 0 ||
        ordered.max_nodes != 0 ||
        ordered.max_depth != 0 {
        return Err(MixedExecutionConfiguration)
      }
      Map([])
    }
  }
  match fragments {
    Some(contexts) =>
      match
        attach_fragment_budgets(
          contracts, sequence, contexts, ordered_budgets, control, metadata,
        ) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
    None => () // Component-only calls do not claim fragment admission.
  }
  if supplied.length() > wiring.input_count ||
    produced.length() != wiring.input_count - supplied.length() {
    return Err(InputSet)
  }
  if !reserve_slots(metadata, wiring.input_count) ||
    !reserve_slots(metadata, produced.length()) {
    return Err(InputLimit)
  }
  let inputs : Array[SequenceInput?] = Array::make(wiring.input_count, None)
  // All supplied owner/origin identities are checked before computation.
  // Input position is physical input ordinal, not an author alias.
  for i = 0; i < supplied.length(); i = i + 1 {
    if !spend_control(control, 1) {
      return Err(InputLimit)
    }
    if !physical_equal(supplied[i].owner, owner) {
      return Err(InputOwnership)
    }
    guard supplied[i].origin is SuppliedInput(index) else {
      return Err(InputSet)
    }
    if index < 0 || index >= inputs.length() || inputs[index] is Some(_) {
      return Err(InputSet)
    }
    // CapturedRows proves schema/value ownership, not that an upstream producer
    // successfully computed these exact rows. Never launder conditional producer
    // evidence through a raw capture, even when counts and keys happen to agree.
    if @pipeline.input_producer(pipeline, index) is Some(_) {
      return Err(InputExecutionEvidencePending(index))
    }
    inputs[index] = Some(RawInput(supplied[i]))
  }
  for bound in produced {
    if !completion_is_live(bound.output.completion) {
      return Err(InputOwnership)
    }
    if !spend_control(control, 1) {
      return Err(InputLimit)
    }
    if !physical_equal(bound.receiver, owner) {
      return Err(InputOwnership)
    }
    let index = bound.input_index
    if index < 0 || index >= inputs.length() || inputs[index] is Some(_) {
      return Err(InputSet)
    }
    if bound.output.completion.contracts.registry_cid != contracts.registry_cid ||
      bound.output.completion.contracts.values_contract_cid !=
      contracts.values_contract_cid {
      return Err(InputOwnership)
    }
    inputs[index] = Some(ProducerInput(bound))
  }
  let store = match
    table_store(
      wiring,
      { limit: limits.retained_entries, live: 0, peak: 0, },
      release=release_table,
      reserve_storage~,
    ) {
    Ok(v) => v
    Err(e) => return Err(Store(e))
  }
  let import_inputs = fn() -> Result[Int, SequenceRunIssue] {
    let mut input_rows = 0
    for i = 0; i < inputs.length(); i = i + 1 {
      guard inputs[i] is Some(input) else { return Err(InputSet) }
      let table = match input {
        RawInput(captured) => {
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
          match import_raw(captured) {
            Ok(v) => v
            Err(e) => return Err(Rows(i, e))
          }
        }
        ProducerInput(bound) => {
          let source = bound.output.table
          if !charge_completed_rows(
              source,
              limits.max_rows - input_rows,
              control,
              input_budget,
            ) {
            return Err(InputLimit)
          }
          input_rows += IndexedRows::row_count(source)
          match import_producer(bound, wiring.ids[i], output_budget) {
            Ok(v) => v
            Err(e) => return Err(Rows(i, e))
          }
        }
      }
      match install_table_input(store, i, table, control) {
        Ok(_) => ()
        Err(e) => {
          (store.release)(table)
          return Err(Store(e))
        }
      }
    }
    Ok(input_rows)
  }
  let input_rows = match import_inputs() {
    Ok(count) => count
    Err(issue) => {
      clear_table_store(store)
      return Err(issue)
    }
  }
  Ok({
    contracts,
    sequence,
    produced,
    limits,
    control,
    input_budget,
    output_budget,
    input_rows,
    ordered_budgets,
    store,
  })
}

///|
fn run_sequence_invocation(
  invocation : SequenceInvocation[Table],
  join_ceiling? : (Int, Int64)? = None,
) -> Result[CompletedSequence, SequenceRunIssue] {
  run_completed_sequence_backend(
    invocation,
    fn(captured) {
      table_from_capture_bounded(captured, invocation.control, {
        limit: invocation.limits.operation_entries,
        live: 0,
        peak: 0,
      })
    },
    fn(kernel, input, logical) {
      evaluate_rows_with_workspace(
        kernel,
        input,
        invocation.limits.max_rows,
        invocation.control,
        invocation.output_budget,
        { limit: invocation.limits.operation_entries, live: 0, peak: 0, },
        ordered_budget=logical,
      )
    },
    store => RowStore(store),
    evaluate_join=Some((kernel, left, right) => {
      evaluate_join_rows(
        kernel,
        left,
        right,
        invocation.limits.max_rows,
        invocation.control,
        invocation.output_budget,
        { limit: invocation.limits.operation_entries, live: 0, peak: 0, },
        selected_ceiling=join_ceiling,
      )
    }),
  )
}

///|
// The only success constructor: physical wrapping cannot bypass the ordered
// driver, cleanup or final cumulative-budget check.
fn[T : RelationRows] run_completed_sequence_backend(
  invocation : SequenceInvocation[T],
  import_values : (CapturedRows) -> Result[T, RowIssue],
  evaluate : (@lower.PreparedKernel, T, LogicalBudget?) -> Result[T, RowIssue],
  wrap : (TableStore[T]) -> CompletedStore,
  evaluate_join? : ((@lower.PreparedJoinKernel, T, T) -> Result[T, RowIssue])? = None,
) -> Result[CompletedSequence, SequenceRunIssue] {
  let result = run_sequence_with_backend(
    invocation,
    import_values,
    evaluate,
    evaluate_join~,
  )
  if result is Err(issue) {
    return Err(issue)
  }
  Ok({
    contracts: invocation.contracts,
    sequence: invocation.sequence,
    store: wrap(invocation.store),
    _producer_inputs: invocation.produced.copy(),
    input_bindings: invocation.produced.map(input => input.identity),
    live: None,
  })
}

///|
// Values capture, cumulative budgets, operation order and final success checks
// are common to physical layouts. This never manufactures completion evidence.
fn[T : RelationRows] run_sequence_with_backend(
  invocation : SequenceInvocation[T],
  import_values : (CapturedRows) -> Result[T, RowIssue],
  evaluate : (@lower.PreparedKernel, T, LogicalBudget?) -> Result[T, RowIssue],
  evaluate_join? : ((@lower.PreparedJoinKernel, T, T) -> Result[T, RowIssue])? = None,
) -> Result[Unit, SequenceRunIssue] {
  let {
    sequence,
    produced,
    limits,
    control,
    input_budget,
    ordered_budgets,
    store,
    ..
  } = invocation
  let owner = @lower.sequence_owner(sequence)
  let mut input_rows = invocation.input_rows
  let result = run_sequence_steps(
    sequence,
    store,
    control,
    fn(i) {
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
      match import_values(captured) {
        Ok(v) => Ok(v)
        Err(e) => return Err(Rows(i, e))
      }
    },
    fn(i, kernel, input) {
      match evaluate(kernel, input, ordered_budgets.get(i)) {
        Ok(v) => Ok(v)
        Err(e) => return Err(Rows(i, e))
      }
    },
    evaluate_join=evaluate_join.map(evaluate => {
      fn(i, kernel, left, right) {
        evaluate(kernel, left, right).map_err(issue => Rows(i, issue))
      }
    }),
  )
  if result is Err(issue) {
    clear_table_store(store)
    return Err(issue)
  }
  if !spend_control(control, produced.length()) {
    clear_table_store(store)
    return Err(InputLimit)
  }
  Ok(())
}

///|
/// The sole ordered routing/commit loop. Physical callbacks do not choose the
/// next operation, skip unused operations, or publish a partially filled store.
/// Input admission and final completion evidence remain the caller's duties.
fn[T : RelationRows] run_sequence_steps(
  sequence : @lower.PreparedSequence,
  store : TableStore[T],
  control : ControlBudget,
  import_values : (Int) -> Result[T, SequenceRunIssue],
  evaluate : (Int, @lower.PreparedKernel, T) -> Result[T, SequenceRunIssue],
  evaluate_join? : ((Int, @lower.PreparedJoinKernel, T, T) -> Result[
    T,
    SequenceRunIssue,
  ])? = None,
) -> Result[Unit, SequenceRunIssue] {
  if !physical_equal(@lower.sequence_owner(sequence), store.wiring.owner) {
    return Err(InputOwnership)
  }
  if store.next != 0 ||
    store.wiring.routes.length() != @lower.sequence_count(sequence) {
    return Err(Store(InvalidState))
  }
  for i = 0; i < @lower.sequence_count(sequence); i = i + 1 {
    let result = match @lower.sequence_step(sequence, i).unwrap() {
      @lower.ValuesStep(_) => import_values(i)
      @lower.JoinStep(kernel) => {
        let route = store.wiring.routes[i]
        guard route.length() == 2 &&
          evaluate_join is Some(evaluate) &&
          store.tables[route[0]] is Some(left) &&
          store.tables[route[1]] is Some(right) else {
          return Err(InputSet)
        }
        evaluate(i, kernel, left.table, right.table)
      }
      @lower.RowStep(kernel) => {
        let route = store.wiring.routes[i]
        if route.length() != 1 {
          return Err(InputSet)
        }
        guard store.tables[route[0]] is Some(input) else {
          return Err(InputSet)
        }
        evaluate(i, kernel, input.table)
      }
    }
    let table = match result {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    match commit_table(store, i, table, control) {
      Ok(_) => ()
      Err(e) => {
        (store.release)(table)
        return Err(Store(e))
      }
    }
  }
  Ok(())
}
