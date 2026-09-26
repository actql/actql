///|
/// Indexed parent-major nest over two managed reads, with the semantics of
/// `evaluate_nest_rows`: NULL keys never match, parent duplicates stay
/// separate occurrences, and each parent's items follow the resolved child
/// order. Admission, name resolution, the child index sort, every key
/// comparison unit, match collection, item construction, envelope
/// measurement and output cells advance one bounded step at a time. One
/// parent's nested array is measured in one step, bounded by the required
/// per-parent item limit and the output value limits.
priv enum BoundedNestPhase {
  ChargeInput
  ResolveKey
  ResolveOrder
  ResolveField
  ResolveOutput
  SeedChild
  SortChild
  InitGrouped
  BeginParent
  CheckNull
  SearchChild
  MatchChild
  ChargeRow
  BuildItem
  MeasureNested
  CheckAttached
  BuildCell
  CommitRow
  FinishOutput
  Terminal
}

///|
priv struct BoundedNestState {
  parent : ProducerRead
  child : ProducerRead
  kernel : @lower.PreparedNestKernel
  output_schema : @schema.Schema
  item_limit : Int64
  grouped_limit : Int64
  attached_limit : Int64
  control : ControlBudget
  workspace : RowWorkspace
  value_output : ValueBudget
  input_scan : BoundedBinaryInputScan
  admitted_limits : @admitted.Limits
  mut output : AdmittedOutput?
  rows : Ref[AdmittedOutputRows?]
  live : Ref[Bool]
  accepted : Ref[Bool]
  port : TrustedOutputPort[Unit]
  parent_names : Array[String]
  child_names : Array[String]
  keys : Array[(Int, Int)]
  // Key terms first, then the resolved child order terms.
  terms : Array[ColumnOrder]
  term_columns : Array[Int]
  projection : Array[(String, Int)]
  names : Array[String]
  output_columns : Array[Int?]
  attachment_columns : Array[Int]
  comparison : BoundedRowComparison
  pending : PendingUnits
  mut phase : BoundedNestPhase
  mut index : Int
  mut charging : Bool
  mut seed : Array[Int]
  mut sorter : AggregateMergeSort[Int]?
  mut child_index : Array[Int]
  grouped : Array[Bool]
  mut grouped_bytes : Int64
  mut attached_bytes : Int64
  // The current parent row.
  mut parent_row : Int
  mut low : Int
  mut high : Int
  mut position : Int
  matches : Array[Int]
  mut item : Int
  mut item_column : Int
  mut entries : Array[(String, @admitted.Value)]
  items : Array[@admitted.Value]
  mut nested : Value
  mut nested_bytes : Int64
  mut column : Int
  mut checked_row : Array[@admitted.CheckedValue]
}

///|
pub(all) enum BoundedNestIssue {
  InvalidExecution
  InputLimit
  Rows(RowIssue)
  Capture(CaptureIssue)
  Completion(TrustedOutputIssue)
  Execution(@bounded.Issue)
}

///|
struct BoundedNestExecution {
  session : @bounded.Session[
    BoundedNestState,
    CompletedOutput,
    BoundedNestIssue,
  ]
  mut token : @bounded.Token?
  accepted : Ref[Bool]
  state : BoundedNestState
}

///|
pub enum BoundedNestPoll {
  BoundedNestContinue(progress~ : Int64, work~ : Int64)
  BoundedNestComplete(CompletedOutput, progress~ : Int64, work~ : Int64)
  BoundedNestFailed(BoundedNestIssue, progress~ : Int64, work~ : Int64)
  BoundedNestStopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
fn bounded_nest_failure(
  issue : BoundedNestIssue,
  progress : Int,
  work : Int,
) -> @bounded.KernelStep[CompletedOutput, BoundedNestIssue] {
  @bounded.Failed(issue, progress, work)
}

///|
fn cleanup_bounded_nest_state(state : BoundedNestState) -> Bool {
  cleanup_binary_input_scan(state.input_scan)
  if state.sorter is Some(sorter) {
    close_aggregate_merge_sort(sorter)
    state.sorter = None
  }
  if state.output is Some(output) {
    cancel_admitted_output(output) |> ignore
    state.output = None
  }
  state.seed = []
  state.child_index = []
  state.grouped.clear()
  state.matches.clear()
  state.items.clear()
  state.entries = []
  state.checked_row = []
  release_slots(state.workspace, state.workspace.live)
  if !state.accepted.val {
    state.rows.val = None
    state.live.val = false
  }
  true
}

///|
/// Parent rows are non-negative; child rows are encoded as `-1 - row`.
fn bounded_nest_cell(state : BoundedNestState, row : Int, term : Int) -> Value? {
  if term < state.keys.length() {
    if row >= 0 {
      producer_read_cell(state.parent, row, state.keys[term].0)
    } else {
      producer_read_cell(state.child, -1 - row, state.keys[term].1)
    }
  } else if row < 0 {
    producer_read_cell(state.child, -1 - row, state.term_columns[term])
  } else {
    None
  }
}

///|
fn bounded_nest_compare(
  state : BoundedNestState,
  left : Int,
  right : Int,
  terms : Int,
) -> Result[Int?, RowIssue] {
  bounded_row_comparison_step_with(
    state.comparison,
    state.terms,
    state.control,
    (row, term) => bounded_nest_cell(state, row, term),
    left,
    right,
    terms,
  ).map_err(ordering_row_issue)
}

///|
/// Pay previously decided units, one per advance. Returns true when paid.
fn bounded_nest_pay(state : BoundedNestState, units : Int) -> Bool? {
  if !state.charging {
    state.pending.remaining = units
    state.charging = true
  }
  match pay_pending_unit(state.pending, state.control) {
    Err(_) => None
    Ok(false) => Some(false)
    Ok(true) => {
      state.charging = false
      Some(true)
    }
  }
}

///|
fn bounded_nest_step(
  state : BoundedNestState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[CompletedOutput, BoundedNestIssue] {
  let mut used = 0
  let mut progress = 0
  let kernel = state.kernel
  let key_count = @lower.nest_kernel_key_count(kernel)
  let order_count = @lower.nest_kernel_order_count(kernel)
  let field_count = @lower.nest_kernel_field_count(kernel)
  let output_width = @schema.field_count(state.output_schema)
  let into = @lower.nest_kernel_into(kernel)
  let child_count = producer_read_row_count(state.child)
  let parent_count = producer_read_row_count(state.parent)
  let row_limit = fn(used : Int) {
    bounded_nest_failure(Rows(RowLimit), progress, used + 1)
  }
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if !producer_read_available(state.parent) ||
      !producer_read_available(state.child) {
      return bounded_nest_failure(InvalidExecution, progress, used)
    }
    match state.phase {
      ChargeInput => {
        match advance_binary_input_scan(state.input_scan) {
          Ok(true) => state.phase = ResolveKey
          Ok(false) => ()
          Err(ValueLimit) =>
            return bounded_nest_failure(InputLimit, progress, used + 1)
          Err(ControlLimit) | Err(WorkspaceLimit) => return row_limit(used)
          Err(InputUnavailable) =>
            return bounded_nest_failure(InvalidExecution, progress, used + 1)
        }
        used += 1
      }
      ResolveKey => {
        if state.index >= key_count {
          state.index = 0
          state.phase = ResolveOrder
          continue
        }
        if !reserve_slots(state.workspace, 2) ||
          !spend_control(state.control, 1) {
          return row_limit(used)
        }
        let pair = @lower.nest_kernel_key_at(kernel, state.index).unwrap()
        let left = match
          resolve_column(state.parent_names, pair.left, state.control) {
          Ok(value) => value
          Err(issue) =>
            return bounded_nest_failure(Rows(issue), progress, used + 1)
        }
        let right = match
          resolve_column(state.child_names, pair.right, state.control) {
          Ok(value) => value
          Err(issue) =>
            return bounded_nest_failure(Rows(issue), progress, used + 1)
        }
        state.keys.push((left, right))
        state.terms.push({
          column: state.terms.length(),
          descending: false,
          nulls_first: true,
        })
        state.term_columns.push(right)
        state.index += 1
        used += 1
      }
      ResolveOrder => {
        if state.index >= order_count {
          state.index = 0
          state.phase = ResolveField
          continue
        }
        if !reserve_slots(state.workspace, 1) ||
          !spend_control(state.control, 1) {
          return row_limit(used)
        }
        let term = @lower.nest_kernel_order_at(kernel, state.index).unwrap()
        let column = match
          resolve_column(state.child_names, term.field, state.control) {
          Ok(value) => value
          Err(issue) =>
            return bounded_nest_failure(Rows(issue), progress, used + 1)
        }
        state.terms.push({
          column: state.terms.length(),
          descending: term.descending,
          nulls_first: term.nulls_first,
        })
        state.term_columns.push(column)
        state.index += 1
        used += 1
      }
      ResolveField => {
        if state.index >= field_count {
          if output_width > (state.workspace.limit - state.workspace.live) / 3 ||
            !reserve_slots(state.workspace, output_width * 3) {
            return row_limit(used)
          }
          state.index = 0
          state.phase = ResolveOutput
          used += 1
          continue
        }
        if !reserve_slots(state.workspace, 2) ||
          !spend_control(state.control, 1) {
          return row_limit(used)
        }
        let field = @lower.nest_kernel_field_at(kernel, state.index).unwrap()
        let column = match
          resolve_column(state.child_names, field.input, state.control) {
          Ok(value) => value
          Err(issue) =>
            return bounded_nest_failure(Rows(issue), progress, used + 1)
        }
        state.projection.push((field.output, column))
        state.index += 1
        used += 1
      }
      ResolveOutput => {
        if state.index >= output_width {
          if !reserve_slots(state.workspace, child_count) ||
            !reserve_slots(state.workspace, child_count) ||
            !reserve_slots(state.workspace, child_count) {
            return row_limit(used)
          }
          state.phase = SeedChild
          used += 1
          continue
        }
        let output = @schema.field_at(state.output_schema, state.index).unwrap()
        let name = @schema.reference_name(output.name)
        if !spend_control_text(state.control, name) {
          return row_limit(used)
        }
        state.names.push(name)
        if output.name == @schema.Unqualified(into) {
          state.output_columns.push(None)
        } else {
          match resolve_column(state.parent_names, output.name, state.control) {
            Ok(column) => state.output_columns.push(Some(column))
            Err(issue) =>
              return bounded_nest_failure(Rows(issue), progress, used + 1)
          }
        }
        match output.contract.shape {
          @contract.Array(_, ..) | @contract.Object(_) =>
            state.attachment_columns.push(state.index)
          _ => ()
        }
        state.index += 1
        used += 1
      }
      SeedChild => {
        if state.seed.length() < child_count {
          if !spend_control(state.control, 1) {
            return row_limit(used)
          }
          state.seed.push(state.seed.length())
        } else {
          let terms = state.terms.length()
          state.sorter = Some(
            start_aggregate_merge_sort(state.seed, (a, b) => {
              bounded_nest_compare(state, -1 - a, -1 - b, terms)
            }),
          )
          state.seed = []
          state.phase = SortChild
        }
        used += 1
      }
      SortChild => {
        guard state.sorter is Some(sorter) else {
          return bounded_nest_failure(InvalidExecution, progress, used)
        }
        if !spend_control(state.control, 1) {
          return row_limit(used)
        }
        match advance_aggregate_merge_sort(sorter) {
          Err(issue) => {
            state.sorter = None
            return bounded_nest_failure(Rows(issue), progress, used + 1)
          }
          Ok(None) => ()
          Ok(Some(order)) => {
            state.sorter = None
            state.child_index = order
            state.phase = InitGrouped
          }
        }
        used += 1
      }
      InitGrouped => {
        if state.grouped.length() < child_count {
          state.grouped.push(false)
        } else {
          state.phase = BeginParent
        }
        used += 1
      }
      BeginParent => {
        if state.parent_row >= parent_count {
          state.phase = FinishOutput
          continue
        }
        if !spend_control(state.control, 1) {
          return row_limit(used)
        }
        state.matches.clear()
        state.index = 0
        state.phase = CheckNull
        used += 1
      }
      // NULL keys never match.
      CheckNull => {
        if state.index >= key_count {
          state.low = 0
          state.high = state.child_index.length()
          state.phase = SearchChild
          continue
        }
        guard producer_read_cell(
            state.parent,
            state.parent_row,
            state.keys[state.index].0,
          )
          is Some(value) else {
          return bounded_nest_failure(InvalidExecution, progress, used)
        }
        if value is Null {
          state.phase = ChargeRow
        } else {
          state.index += 1
        }
        used += 1
      }
      SearchChild => {
        if state.low == state.high {
          state.position = state.low
          state.phase = MatchChild
          continue
        }
        let middle = state.low + (state.high - state.low) / 2
        match
          bounded_nest_compare(
            state,
            state.parent_row,
            -1 - state.child_index[middle],
            key_count,
          ) {
          Err(issue) =>
            return bounded_nest_failure(Rows(issue), progress, used + 1)
          Ok(None) => ()
          Ok(Some(order)) =>
            if order > 0 {
              state.low = middle + 1
            } else {
              state.high = middle
            }
        }
        used += 1
      }
      MatchChild => {
        if state.position >= state.child_index.length() {
          state.phase = ChargeRow
          continue
        }
        let child = state.child_index[state.position]
        match
          bounded_nest_compare(state, state.parent_row, -1 - child, key_count) {
          Err(issue) =>
            return bounded_nest_failure(Rows(issue), progress, used + 1)
          Ok(None) => ()
          Ok(Some(0)) => {
            if (state.matches.length() + 1).to_int64() > state.item_limit {
              return bounded_nest_failure(
                Rows(NestItemLimit(state.parent_row)),
                progress,
                used + 1,
              )
            }
            if !reserve_slots(state.workspace, 1) {
              return row_limit(used)
            }
            state.matches.push(child)
            state.position += 1
          }
          Ok(Some(_)) => state.phase = ChargeRow
        }
        used += 1
      }
      ChargeRow => {
        let count = state.matches.length()
        guard checked_row_slots_add(count, state.names.length())
          is Some(entries) &&
          checked_row_slots_add(entries, 1) is Some(row_work) else {
          return row_limit(used)
        }
        match bounded_nest_pay(state, row_work) {
          None => return row_limit(used)
          Some(false) => ()
          Some(true) => {
            if !reserve_slots(state.workspace, state.names.length()) ||
              !reserve_slots(state.workspace, 1) {
              return row_limit(used)
            }
            state.items.clear()
            state.item = 0
            state.item_column = -1
            state.phase = BuildItem
          }
        }
        used += 1
      }
      BuildItem => {
        if state.item >= state.matches.length() {
          state.nested = Captured(@admitted.array_value(state.items.copy()))
          state.phase = MeasureNested
          continue
        }
        // Entry: reserve the projected entries and pay one unit each.
        if state.item_column < 0 {
          if !state.charging &&
            !reserve_slots(state.workspace, state.projection.length()) {
            return row_limit(used)
          }
          match bounded_nest_pay(state, state.projection.length()) {
            None => return row_limit(used)
            Some(false) => ()
            Some(true) => {
              state.entries = []
              state.item_column = 0
            }
          }
          used += 1
          continue
        }
        if state.item_column < state.projection.length() {
          let (name, column) = state.projection[state.item_column]
          guard producer_read_cell(
              state.child,
              state.matches[state.item],
              column,
            )
            is Some(cell) else {
            return bounded_nest_failure(InvalidExecution, progress, used)
          }
          match admitted_nest_value(cell, state.control) {
            Ok(value) => state.entries.push((name, value))
            Err(issue) =>
              return bounded_nest_failure(Rows(issue), progress, used + 1)
          }
          state.item_column += 1
          used += 1
          continue
        }
        guard @admitted.object_value(state.entries) is Some(object) else {
          return bounded_nest_failure(Rows(InvalidRows), progress, used + 1)
        }
        state.items.push(object)
        state.entries = []
        state.item += 1
        state.item_column = -1
        used += 1
      }
      MeasureNested => {
        let bytes = match
          measure_nest_value(
            state.nested,
            Int64::max(state.grouped_limit, state.attached_limit),
            0L,
            state.control,
            state.value_output,
          ) {
          Ok(value) => value
          Err(issue) =>
            return bounded_nest_failure(Rows(issue), progress, used + 1)
        }
        state.nested_bytes = bytes
        if state.matches.length() > 0 {
          let group = state.matches[0]
          if !state.grouped[group] {
            if bytes > state.grouped_limit - state.grouped_bytes {
              return bounded_nest_failure(
                Rows(NestEnvelope(GroupedBytes)),
                progress,
                used + 1,
              )
            }
            state.grouped_bytes += bytes
            state.grouped[group] = true
          }
        }
        state.index = 0
        state.phase = CheckAttached
        used += 1
      }
      CheckAttached => {
        if state.index >= state.attachment_columns.length() {
          state.column = 0
          state.checked_row = []
          state.phase = BuildCell
          continue
        }
        let column = state.attachment_columns[state.index]
        let bytes = match state.output_columns[column] {
          None => state.nested_bytes
          Some(source) => {
            guard producer_read_cell(state.parent, state.parent_row, source)
              is Some(value) else {
              return bounded_nest_failure(InvalidExecution, progress, used)
            }
            match
              measure_nest_value(
                value,
                state.attached_limit,
                state.attached_bytes,
                state.control,
                state.value_output,
              ) {
              Ok(value) => value
              Err(issue) =>
                return bounded_nest_failure(Rows(issue), progress, used + 1)
            }
          }
        }
        if bytes > state.attached_limit - state.attached_bytes {
          return bounded_nest_failure(
            Rows(NestEnvelope(AttachedBytes)),
            progress,
            used + 1,
          )
        }
        state.attached_bytes += bytes
        state.index += 1
        used += 1
      }
      BuildCell => {
        if state.column >= output_width {
          state.phase = CommitRow
          continue
        }
        let value = match state.output_columns[state.column] {
          None => state.nested
          Some(source) =>
            match producer_read_cell(state.parent, state.parent_row, source) {
              Some(value) => value
              None =>
                return bounded_nest_failure(InvalidExecution, progress, used)
            }
        }
        guard @schema.field_at(state.output_schema, state.column) is Some(field) &&
          checked_ordered_output_value(
            value,
            field.contract,
            state.admitted_limits,
          )
          is Some(checked) else {
          return bounded_nest_failure(Rows(InputMismatch), progress, used + 1)
        }
        state.checked_row.push(checked)
        state.column += 1
        used += 1
      }
      CommitRow => {
        guard state.output is Some(output) else {
          return bounded_nest_failure(InvalidExecution, progress, used)
        }
        match append_admitted_output(output, state.checked_row) {
          Err(issue) =>
            return bounded_nest_failure(Capture(issue), progress, used + 1)
          Ok(_) => ()
        }
        state.checked_row = []
        state.items.clear()
        state.nested = Null
        state.parent_row += 1
        state.phase = BeginParent
        progress += 1
        used += 1
      }
      FinishOutput => {
        guard state.output is Some(output) else {
          return bounded_nest_failure(InvalidExecution, progress, used)
        }
        state.output = None
        let rows = match finish_admitted_output(output) {
          Ok(value) => value
          Err(issue) =>
            return bounded_nest_failure(Capture(issue), progress, used + 1)
        }
        state.rows.val = Some(rows)
        state.phase = Terminal
        used += 1
        return match complete_trusted_output(state.port, ()) {
          Ok(value) => @bounded.Complete(value, progress, used)
          Err(issue) => bounded_nest_failure(Completion(issue), progress, used)
        }
      }
      Terminal => return bounded_nest_failure(InvalidExecution, progress, used)
    }
  }
  @bounded.Continue(progress, used)
}

///|
pub fn start_bounded_nest(
  engine : @bounded.Control,
  generated : GeneratedSequence,
  parent : ProducerRead,
  child : ProducerRead,
  max_rows : Int,
  input_values : ValueLimits,
  output_values : ValueLimits,
  max_work : Int,
  max_frames : Int,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[BoundedNestExecution, BoundedNestIssue] {
  if max_rows < 0 ||
    max_work < 0 ||
    max_frames < 0 ||
    max_entries < 0 ||
    max_name_bytes < 0 {
    return Err(InvalidExecution)
  }
  let owner = @lower.sequence_owner(generated.sequence)
  guard generated_sequence_step_index_at(generated, 0) is Some(step) &&
    generated_sequence_step_index_at(generated, 1) is None &&
    @lower.sequence_step(generated.sequence, step)
    is Some(@lower.NestStep(kernel)) &&
    producer_read_matches_operation_input(parent, owner, step, 0) &&
    producer_read_matches_operation_input(child, owner, step, 1) &&
    producer_read_has_cell_access(parent) &&
    producer_read_has_cell_access(child) &&
    @lower.preparation_schema_at(
      @lower.bound_preparation(owner),
      @pipeline.Step(step),
    )
    is Some(output_schema) else {
    return Err(InvalidExecution)
  }
  if producer_read_row_count(parent) > max_rows ||
    producer_read_row_count(child) > max_rows {
    return Err(Rows(RowLimit))
  }
  let item_limit = match
    (
      @lower.nest_kernel_item_limit(kernel),
      selected_step_ceiling(generated.nest_item_ceilings, step),
    ) {
    (Some(left), Some(right)) => Int64::min(left, right)
    (Some(value), None) | (None, Some(value)) => value
    (None, None) => return Err(Rows(NestItemLimitRequired))
  }
  guard selected_step_ceiling(generated.nest_grouped_byte_ceilings, step)
    is Some(grouped_limit) &&
    selected_step_ceiling(generated.nest_attached_byte_ceilings, step)
    is Some(attached_limit) else {
    return Err(Rows(NestEnvelope(Measurement)))
  }
  if item_limit < 0L || grouped_limit < 0L || attached_limit < 0L {
    return Err(Rows(InvalidRowLimits))
  }
  let value_output = match value_budget(output_values) {
    Ok(value) => value
    Err(_) => return Err(InvalidExecution)
  }
  let workspace = row_workspace(max_entries)
  let control : ControlBudget = { remaining: max_work, max_frames, }
  guard binary_input_scan(parent, child, input_values, control, workspace)
    is Some(input_scan) else {
    return Err(InvalidExecution)
  }
  let output = match
    prepare_admitted_output(
      owner,
      @pipeline.Step(step),
      max_rows,
      output_values,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Capture(issue))
  }
  let rows : Ref[AdmittedOutputRows?] = Ref(None)
  let live = Ref(true)
  let accepted = Ref(false)
  let port = match
    prepare_trusted_output_port(
      generated_completion_preparation(generated),
      @pipeline.Step(step),
      max_entries,
      max_name_bytes,
      fn(_) { if live.val { rows.val } else { None } },
      inputs=[parent, child],
    ) {
    Ok(value) => value
    Err(issue) => {
      cancel_admitted_output(output) |> ignore
      return Err(Completion(issue))
    }
  }
  let names_of = (read : ProducerRead) => {
    let schema = producer_read_schema(read)
    Array::makei(@schema.field_count(schema), i => {
      @schema.reference_name(@schema.field_at(schema, i).unwrap().name)
    })
  }
  let state : BoundedNestState = {
    parent,
    child,
    kernel,
    output_schema,
    item_limit,
    grouped_limit,
    attached_limit,
    control,
    workspace,
    value_output,
    input_scan,
    admitted_limits: {
      max_nodes: output_values.max_nodes,
      max_depth: output_values.max_depth,
      max_text_bytes: output_values.max_text_bytes,
    },
    output: Some(output),
    rows,
    live,
    accepted,
    port,
    parent_names: names_of(parent),
    child_names: names_of(child),
    keys: [],
    terms: [],
    term_columns: [],
    projection: [],
    names: [],
    output_columns: [],
    attachment_columns: [],
    comparison: {
      left: -1,
      right: -1,
      terms: 0,
      term: 0,
      phase: -1,
      offset: 0,
      charge: { offset: 0, next: 0, remaining: 0, },
    },
    pending: { remaining: 0, },
    phase: ChargeInput,
    index: 0,
    charging: false,
    seed: [],
    sorter: None,
    child_index: [],
    grouped: [],
    grouped_bytes: 0L,
    attached_bytes: 0L,
    parent_row: 0,
    low: 0,
    high: 0,
    position: 0,
    matches: [],
    item: 0,
    item_column: -1,
    entries: [],
    items: [],
    nested: Null,
    nested_bytes: 0L,
    column: 0,
    checked_row: [],
  }
  let (session, token) = @bounded.start(
    engine,
    state,
    bounded_nest_step,
    cleanup_bounded_nest_state,
    _ => {
      state.live.val = false
      true
    },
  )
  Ok({ session, token: Some(token), accepted, state, })
}

///|
pub fn advance_bounded_nest(
  value : BoundedNestExecution,
  quantum : Int,
) -> Result[BoundedNestPoll, BoundedNestIssue] {
  guard value.token is Some(token) else {
    return Err(Execution(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(Execution(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(BoundedNestContinue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      value.accepted.val = true
      Ok(BoundedNestComplete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(BoundedNestFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(BoundedNestStopped(reason, progress~, work~))
    }
  }
}

///|
pub fn cleanup_bounded_nest(
  value : BoundedNestExecution,
) -> Result[Bool, BoundedNestIssue] {
  let changed = match @bounded.cleanup(value.session) {
    Ok(changed) => changed
    Err(issue) => return Err(Execution(issue))
  }
  if !@bounded.cleanup_pending(value.session) &&
    (
      value.state.input_scan.frames.length() != 0 ||
      value.state.workspace.live != 0
    ) {
    return Err(InvalidExecution)
  }
  Ok(changed)
}
