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
  InputRepresentationRequired(Int)
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
fn selected_step_ceiling(ceilings : Array[(Int, Int64)], step : Int) -> Int64? {
  let mut selected = None
  for (candidate, maximum) in ceilings {
    if candidate == step {
      selected = Some(
        match selected {
          Some(prior) => Int64::min(prior, maximum)
          None => maximum
        },
      )
    }
  }
  selected
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
  join_ceilings? : Array[(Int, Int64)] = [],
  expansion_ceilings? : Array[(Int, Int64)] = [],
  interval_search_ceilings? : Array[(Int, Int64)] = [],
  asof_search_ceilings? : Array[(Int, Int64)] = [],
  aggregate_outputs? : Array[SelectedAggregateOutput] = [],
  analytic_envelopes? : Array[SelectedAnalyticEnvelope] = [],
  nest_item_ceilings? : Array[(Int, Int64)] = [],
  nest_grouped_byte_ceilings? : Array[(Int, Int64)] = [],
  nest_attached_byte_ceilings? : Array[(Int, Int64)] = [],
  numeric? : NumericAggregateExecution? = None,
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
        Some(RowTable(_)) | None => false
        Some(NumberTable(_) | AdmittedTable(_) | ColumnTable(_)) => true
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
      join_ceilings~,
      expansion_ceilings~,
      interval_search_ceilings~,
      asof_search_ceilings~,
      aggregate_outputs~,
      analytic_envelopes~,
      nest_item_ceilings~,
      nest_grouped_byte_ceilings~,
      nest_attached_byte_ceilings~,
      numeric~,
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
  run_sequence_invocation(
    invocation,
    join_ceilings~,
    expansion_ceilings~,
    interval_search_ceilings~,
    asof_search_ceilings~,
    aggregate_outputs~,
    analytic_envelopes~,
    nest_item_ceilings~,
    nest_grouped_byte_ceilings~,
    nest_attached_byte_ceilings~,
    numeric~,
  )
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
      with_sequence_workspace(limits.operation_entries, workspace => {
        table_from_capture_bounded(captured, control, workspace)
      })
    },
    fn(bound, id, output_budget) {
      guard bound.output.table is Some(RowTable(source)) else {
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
          with_sequence_workspace(limits.operation_entries, workspace => {
            evaluate_row_body(
              Projection(projection),
              adopted,
              id,
              limits.max_rows,
              control,
              output_budget,
              workspace,
            )
          })
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
  let prepared = @lower.bound_preparation(owner)
  let metadata = row_workspace(limits.metadata_entries)
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
    if @lower.preparation_input_is_produced(prepared, index) {
      return Err(InputExecutionEvidencePending(index))
    }
    inputs[index] = Some(RawInput(supplied[i]))
  }
  for bound in produced {
    if !completed_output_available(bound.output) {
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
      row_workspace(limits.retained_entries),
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
          guard bound.output.table is Some(source) else {
            return Err(InputRepresentationRequired(i))
          }
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
  join_ceilings? : Array[(Int, Int64)] = [],
  expansion_ceilings? : Array[(Int, Int64)] = [],
  interval_search_ceilings? : Array[(Int, Int64)] = [],
  asof_search_ceilings? : Array[(Int, Int64)] = [],
  aggregate_outputs? : Array[SelectedAggregateOutput] = [],
  analytic_envelopes? : Array[SelectedAnalyticEnvelope] = [],
  numeric? : NumericAggregateExecution? = None,
  nest_item_ceilings? : Array[(Int, Int64)] = [],
  nest_grouped_byte_ceilings? : Array[(Int, Int64)] = [],
  nest_attached_byte_ceilings? : Array[(Int, Int64)] = [],
) -> Result[CompletedSequence, SequenceRunIssue] {
  run_completed_sequence_backend(
    invocation,
    fn(captured) {
      with_sequence_workspace(invocation.limits.operation_entries, workspace => {
        table_from_capture_bounded(captured, invocation.control, workspace)
      })
    },
    fn(kernel, input, logical) {
      with_sequence_workspace(invocation.limits.operation_entries, workspace => {
        evaluate_rows_with_workspace(
          kernel,
          input,
          selected_expansion_row_limit(
            expansion_ceilings,
            @lower.kernel_step(kernel),
            invocation.limits.max_rows,
          ),
          invocation.control,
          invocation.output_budget,
          workspace,
          ordered_budget=logical,
          aggregate_outputs=selected_aggregate_outputs_at(
            aggregate_outputs,
            @lower.kernel_step(kernel),
          ),
          analytic_envelope=selected_analytic_envelope_at(
            analytic_envelopes,
            @lower.kernel_step(kernel),
          ),
          identity_limits=Some(invocation.limits.input_values),
          numeric~,
        )
      })
    },
    store => RowStore(store),
    evaluate_window=Some((window, input) => {
      with_sequence_workspace(invocation.limits.operation_entries, workspace => {
        evaluate_window_rows(
          window,
          input,
          invocation.limits.max_rows,
          invocation.control,
          invocation.output_budget,
          workspace,
        )
      })
    }),
    evaluate_join=Some((kernel, left, right) => {
      with_sequence_workspace(invocation.limits.operation_entries, workspace => {
        evaluate_join_rows(
          kernel,
          left,
          right,
          invocation.limits.max_rows,
          invocation.control,
          invocation.output_budget,
          workspace,
          selected_ceiling=selected_join_ceiling_at(
            join_ceilings,
            @lower.join_kernel_step(kernel),
          ),
        )
      })
    }),
    evaluate_interval_join=Some((kernel, left, right) => {
      let step = @lower.interval_join_step(kernel)
      guard selected_step_ceiling(interval_search_ceilings, step)
        is Some(search_ceiling) else {
        return Err(InvalidRowLimits)
      }
      with_sequence_workspace(invocation.limits.operation_entries, workspace => {
        evaluate_interval_join_rows(
          kernel,
          left,
          right,
          invocation.limits.max_rows,
          search_ceiling,
          invocation.control,
          invocation.output_budget,
          workspace,
          selected_ceiling=selected_join_ceiling_at(join_ceilings, step),
        )
      })
    }),
    evaluate_asof_join=Some((kernel, left, right) => {
      let step = @lower.asof_join_step(kernel)
      guard selected_step_ceiling(asof_search_ceilings, step)
        is Some(search_ceiling) else {
        return Err(InvalidRowLimits)
      }
      with_sequence_workspace(invocation.limits.operation_entries, workspace => {
        evaluate_asof_join_rows(
          kernel,
          left,
          right,
          invocation.limits.max_rows,
          search_ceiling,
          invocation.control,
          invocation.output_budget,
          workspace,
          selected_ceiling=selected_join_ceiling_at(join_ceilings, step),
        )
      })
    }),
    evaluate_sequence_match=Some((kernel, input) => {
      with_sequence_workspace(invocation.limits.operation_entries, workspace => {
        evaluate_sequence_match_rows(
          kernel,
          input,
          invocation.limits.max_rows,
          invocation.control,
          invocation.output_budget,
          workspace,
        )
      })
    }),
    evaluate_cross_join=Some((kernel, left, right) => {
      with_sequence_workspace(invocation.limits.operation_entries, workspace => {
        evaluate_cross_join_rows(
          kernel,
          left,
          right,
          invocation.limits.max_rows,
          invocation.control,
          invocation.output_budget,
          workspace,
          selected_ceiling=selected_join_ceiling_at(
            join_ceilings,
            @lower.cross_join_kernel_step(kernel),
          ),
        )
      })
    }),
    evaluate_append=Some((kernel, left, right) => {
      with_sequence_workspace(invocation.limits.operation_entries, workspace => {
        evaluate_append_rows(
          kernel,
          left,
          right,
          invocation.limits.max_rows,
          invocation.control,
          invocation.output_budget,
          workspace,
        )
      })
    }),
    evaluate_set=Some((kernel, left, right) => {
      with_sequence_workspace(invocation.limits.operation_entries, workspace => {
        evaluate_set_rows(
          kernel,
          left,
          right,
          invocation.limits.max_rows,
          invocation.control,
          invocation.output_budget,
          workspace,
        )
      })
    }),
    evaluate_nest=Some((kernel, parent, child) => {
      let step = @lower.nest_kernel_step(kernel)
      with_sequence_workspace(invocation.limits.operation_entries, workspace => {
        evaluate_nest_rows(
          kernel,
          parent,
          child,
          invocation.limits.max_rows,
          invocation.control,
          invocation.output_budget,
          workspace,
          selected_item_limit=selected_step_ceiling(nest_item_ceilings, step),
          grouped_byte_limit=selected_step_ceiling(
            nest_grouped_byte_ceilings, step,
          ),
          attached_byte_limit=selected_step_ceiling(
            nest_attached_byte_ceilings, step,
          ),
        )
      })
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
  evaluate_window? : ((@lower.PreparedWindow, T) -> Result[T, RowIssue])? = None,
  evaluate_join? : ((@lower.PreparedJoinKernel, T, T) -> Result[T, RowIssue])? = None,
  evaluate_interval_join? : ((@lower.PreparedIntervalJoin, T, T) -> Result[
    T,
    RowIssue,
  ])? = None,
  evaluate_asof_join? : ((@lower.PreparedAsOfJoin, T, T) -> Result[T, RowIssue])? = None,
  evaluate_sequence_match? : ((@lower.PreparedSequenceMatch, T) -> Result[
    T,
    RowIssue,
  ])? = None,
  evaluate_cross_join? : ((@lower.PreparedCrossJoinKernel, T, T) -> Result[
    T,
    RowIssue,
  ])? = None,
  evaluate_append? : ((@lower.PreparedAppendKernel, T, T) -> Result[T, RowIssue])? = None,
  evaluate_set? : ((@lower.PreparedSetKernel, T, T) -> Result[T, RowIssue])? = None,
  evaluate_nest? : ((@lower.PreparedNestKernel, T, T) -> Result[T, RowIssue])? = None,
) -> Result[CompletedSequence, SequenceRunIssue] {
  let result = run_sequence_with_backend(
    invocation,
    import_values,
    evaluate,
    evaluate_window~,
    evaluate_join~,
    evaluate_interval_join~,
    evaluate_asof_join~,
    evaluate_sequence_match~,
    evaluate_cross_join~,
    evaluate_append~,
    evaluate_set~,
    evaluate_nest~,
  )
  if result is Err(issue) {
    return Err(issue)
  }
  Ok({
    result_identity: Ref(()),
    readmitted: false,
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
  evaluate_window? : ((@lower.PreparedWindow, T) -> Result[T, RowIssue])? = None,
  evaluate_join? : ((@lower.PreparedJoinKernel, T, T) -> Result[T, RowIssue])? = None,
  evaluate_interval_join? : ((@lower.PreparedIntervalJoin, T, T) -> Result[
    T,
    RowIssue,
  ])? = None,
  evaluate_asof_join? : ((@lower.PreparedAsOfJoin, T, T) -> Result[T, RowIssue])? = None,
  evaluate_sequence_match? : ((@lower.PreparedSequenceMatch, T) -> Result[
    T,
    RowIssue,
  ])? = None,
  evaluate_cross_join? : ((@lower.PreparedCrossJoinKernel, T, T) -> Result[
    T,
    RowIssue,
  ])? = None,
  evaluate_append? : ((@lower.PreparedAppendKernel, T, T) -> Result[T, RowIssue])? = None,
  evaluate_set? : ((@lower.PreparedSetKernel, T, T) -> Result[T, RowIssue])? = None,
  evaluate_nest? : ((@lower.PreparedNestKernel, T, T) -> Result[T, RowIssue])? = None,
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
    evaluate_window=evaluate_window.map(evaluate => {
      fn(i, window, input) {
        evaluate(window, input).map_err(issue => Rows(i, issue))
      }
    }),
    evaluate_join=evaluate_join.map(evaluate => {
      fn(i, kernel, left, right) {
        evaluate(kernel, left, right).map_err(issue => Rows(i, issue))
      }
    }),
    evaluate_interval_join=evaluate_interval_join.map(evaluate => {
      fn(i, kernel, left, right) {
        evaluate(kernel, left, right).map_err(issue => Rows(i, issue))
      }
    }),
    evaluate_asof_join=evaluate_asof_join.map(evaluate => {
      fn(i, kernel, left, right) {
        evaluate(kernel, left, right).map_err(issue => Rows(i, issue))
      }
    }),
    evaluate_sequence_match=evaluate_sequence_match.map(evaluate => {
      fn(i, kernel, input) {
        evaluate(kernel, input).map_err(issue => Rows(i, issue))
      }
    }),
    evaluate_cross_join=evaluate_cross_join.map(evaluate => {
      fn(i, kernel, left, right) {
        evaluate(kernel, left, right).map_err(issue => Rows(i, issue))
      }
    }),
    evaluate_append=evaluate_append.map(evaluate => {
      fn(i, kernel, left, right) {
        evaluate(kernel, left, right).map_err(issue => Rows(i, issue))
      }
    }),
    evaluate_set=evaluate_set.map(evaluate => {
      fn(i, kernel, left, right) {
        evaluate(kernel, left, right).map_err(issue => Rows(i, issue))
      }
    }),
    evaluate_nest=evaluate_nest.map(evaluate => {
      fn(i, kernel, parent, child) {
        evaluate(kernel, parent, child).map_err(issue => Rows(i, issue))
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
  evaluate_window? : ((Int, @lower.PreparedWindow, T) -> Result[
    T,
    SequenceRunIssue,
  ])? = None,
  evaluate_join? : ((Int, @lower.PreparedJoinKernel, T, T) -> Result[
    T,
    SequenceRunIssue,
  ])? = None,
  evaluate_interval_join? : ((Int, @lower.PreparedIntervalJoin, T, T) -> Result[
    T,
    SequenceRunIssue,
  ])? = None,
  evaluate_asof_join? : ((Int, @lower.PreparedAsOfJoin, T, T) -> Result[
    T,
    SequenceRunIssue,
  ])? = None,
  evaluate_sequence_match? : ((Int, @lower.PreparedSequenceMatch, T) -> Result[
    T,
    SequenceRunIssue,
  ])? = None,
  evaluate_cross_join? : ((Int, @lower.PreparedCrossJoinKernel, T, T) -> Result[
    T,
    SequenceRunIssue,
  ])? = None,
  evaluate_append? : ((Int, @lower.PreparedAppendKernel, T, T) -> Result[
    T,
    SequenceRunIssue,
  ])? = None,
  evaluate_set? : ((Int, @lower.PreparedSetKernel, T, T) -> Result[
    T,
    SequenceRunIssue,
  ])? = None,
  evaluate_nest? : ((Int, @lower.PreparedNestKernel, T, T) -> Result[
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
      @lower.TimeSeriesStep(_) => return Err(InputSet)
      @lower.WindowStep(window) => {
        let route = store.wiring.routes[i]
        guard route.length() == 1 &&
          evaluate_window is Some(evaluate) &&
          store.tables[route[0]] is Some(input) else {
          return Err(InputSet)
        }
        evaluate(i, window, input.table)
      }
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
      @lower.IntervalJoinStep(kernel) => {
        let route = store.wiring.routes[i]
        guard route.length() == 2 &&
          evaluate_interval_join is Some(evaluate) &&
          store.tables[route[0]] is Some(left) &&
          store.tables[route[1]] is Some(right) else {
          return Err(InputSet)
        }
        evaluate(i, kernel, left.table, right.table)
      }
      @lower.AsOfJoinStep(kernel) => {
        let route = store.wiring.routes[i]
        guard route.length() == 2 &&
          evaluate_asof_join is Some(evaluate) &&
          store.tables[route[0]] is Some(left) &&
          store.tables[route[1]] is Some(right) else {
          return Err(InputSet)
        }
        evaluate(i, kernel, left.table, right.table)
      }
      @lower.SequenceMatchStep(kernel) => {
        let route = store.wiring.routes[i]
        guard route.length() == 1 &&
          evaluate_sequence_match is Some(evaluate) &&
          store.tables[route[0]] is Some(input) else {
          return Err(InputSet)
        }
        evaluate(i, kernel, input.table)
      }
      @lower.CrossJoinStep(kernel) => {
        let route = store.wiring.routes[i]
        guard route.length() == 2 &&
          evaluate_cross_join is Some(evaluate) &&
          store.tables[route[0]] is Some(left) &&
          store.tables[route[1]] is Some(right) else {
          return Err(InputSet)
        }
        evaluate(i, kernel, left.table, right.table)
      }
      @lower.AppendStep(kernel) => {
        let route = store.wiring.routes[i]
        guard route.length() == 2 &&
          evaluate_append is Some(evaluate) &&
          store.tables[route[0]] is Some(left) &&
          store.tables[route[1]] is Some(right) else {
          return Err(InputSet)
        }
        evaluate(i, kernel, left.table, right.table)
      }
      @lower.SetStep(kernel) => {
        let route = store.wiring.routes[i]
        guard route.length() == 2 &&
          evaluate_set is Some(evaluate) &&
          store.tables[route[0]] is Some(left) &&
          store.tables[route[1]] is Some(right) else {
          return Err(InputSet)
        }
        evaluate(i, kernel, left.table, right.table)
      }
      @lower.NestStep(kernel) => {
        let route = store.wiring.routes[i]
        guard route.length() == 2 &&
          evaluate_nest is Some(evaluate) &&
          store.tables[route[0]] is Some(parent) &&
          store.tables[route[1]] is Some(child) else {
          return Err(InputSet)
        }
        evaluate(i, kernel, parent.table, child.table)
      }
      @lower.GraphUnionStep(_) => return Err(InputSet)
      @lower.GraphStructuralStep(_) => return Err(InputSet)
      @lower.GraphBasicStep(_) => return Err(InputSet)
      @lower.GraphMeanStep(_) => return Err(InputSet)
      @lower.GraphMatchStep(_) => return Err(InputSet)
      @lower.GraphReachStep(_) => return Err(InputSet)
      @lower.GraphSubgraphStep(_) => return Err(InputSet)
      @lower.GraphTraverseStep(_) => return Err(InputSet)
      @lower.GraphShortestStep(_) => return Err(InputSet)
      @lower.GraphRelationStep(_) => return Err(InputSet)
      @lower.PropertyGraphConstructionStep(_) => return Err(InputSet)
      @lower.VectorStep(_) => return Err(InputSet)
      @lower.EventStep(_) => return Err(InputSet)
      @lower.CarrierProjectionStep(_) => return Err(InputSet)
      @lower.InferBoundary(_) => return Err(InputSet)
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
