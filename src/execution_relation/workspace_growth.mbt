///|
/// An attempt-local attachment to the existing task's workspace reservation.
/// It owns no capacity or execution permission. The caller must grow that SAME
/// reservation before returning success; the original task owns all cleanup.
priv struct WorkspaceGrowth {
  initial_slots : Int
  initial_live : Int64
  live_ceiling : Int64
  reserve : (Int64) -> Result[Unit, WorkspaceGrowthIssue]
  reserve_retained : ((Int64, Int64) -> Result[Unit, WorkspaceGrowthIssue])?
  output_origin : OutputWorkspaceOriginal?
  mut slots : Int
  mut logical : Int64
  mut text : Int64
  mut text_peak : Int64
  mut slot_peak : Int
  mut logical_peak : Int64
  mut funded : Int64
  mut used : Int64
  mut retained_funded : Int64
  // None preserves the full prepaid output recipe. Some meters cumulative
  // retained output DATA on this same task, without returning prior charges.
  mut retained_outputs : Int64?
  mut busy : Bool
  mut failed : Bool
}

///|
pub(all) enum WorkspaceGrowthIssue {
  WorkspaceUnavailable
  // Only a pre-mutation byte-budget refusal may permit a smaller request.
  WorkspaceBudgetUnavailable
} derive(Eq, Debug)

///|
fn grow_workspace(
  growth : WorkspaceGrowth,
  slots : Int,
  logical : Int64,
  text? : Int64? = None,
  retained? : Int64? = None,
) -> Bool {
  let text = text.unwrap_or(growth.text)
  let retained = retained.unwrap_or(growth.retained_outputs.unwrap_or(0L))
  if growth.failed ||
    growth.busy ||
    slots < 0 ||
    logical < 0L ||
    text < 0L ||
    retained < growth.retained_outputs.unwrap_or(0L) {
    growth.failed = true
    return false
  }
  let slot_peak = Int::max(growth.slot_peak, slots)
  let logical_peak = Int64::max(growth.logical_peak, logical)
  let text_peak = Int64::max(growth.text_peak, text)
  if slot_peak == growth.slot_peak &&
    logical_peak == growth.logical_peak &&
    text_peak == growth.text_peak &&
    growth.retained_outputs is Some(original_retained) &&
    original_retained == retained &&
    growth.used <= growth.funded &&
    (growth.reserve_retained is None || retained <= growth.retained_funded) {
    // The same metered output total and workspace peaks already own this exact
    // quote, including direct output charges within its funded page. Releases
    // change live extents, never that quote. Unmetered callers may supply an
    // explicit retained amount, so None always keeps the full checked recipe.
    growth.slots = slots
    growth.logical = logical
    growth.text = text
    return true
  }
  guard execution_capacity_inventory_add(
      0L,
      CursorRootSlots,
      Int::max(0, slot_peak - growth.initial_slots).to_int64(),
      1,
    )
    is Some(slots_bytes) &&
    execution_capacity_inventory_add(
      slots_bytes,
      ValueNodeSlots,
      Int64::max(0L, logical_peak - growth.initial_live),
      1,
    )
    is Some(values_bytes) &&
    execution_capacity_inventory_add(
      values_bytes,
      CanonicalWireBytes,
      Int64::max(0L, logical_peak - growth.initial_live),
      1,
    )
    is Some(generic) &&
    execution_capacity_inventory_add(generic, QuotedBytes, text_peak, 1)
    is Some(transient) &&
    execution_capacity_inventory_add(transient, QuotedBytes, retained, 1)
    is Some(extra) else {
    growth.failed = true
    return false
  }
  if extra > growth.funded ||
    (growth.reserve_retained is Some(_) && retained > growth.retained_funded) {
    // Fund a bounded page, not every small row. This is spare backing on the
    // same original task, not extra semantic permission or spent usage.
    let remainder = extra % 16384L
    let spare = if growth.retained_outputs is Some(_) &&
      remainder != 0L &&
      extra < growth.live_ceiling {
      Int64::min(16384L - remainder, growth.live_ceiling - extra)
    } else {
      0L
    }
    let minimum = Int64::max(extra, growth.funded)
    let preferred = Int64::max(extra + spare, minimum)
    let minimum_retained = Int64::max(retained, growth.retained_funded)
    let remainder = minimum_retained % 16384L
    let preferred_retained = if growth.reserve_retained is Some(_) &&
      remainder != 0L &&
      minimum_retained <= 9223372036854775807L - (16384L - remainder) {
      minimum_retained + 16384L - remainder
    } else {
      minimum_retained
    }
    let reserve = fn(bytes, retained_bytes) {
      match growth.reserve_retained {
        Some(reserve) => reserve(bytes, retained_bytes)
        None => (growth.reserve)(bytes)
      }
    }
    growth.busy = true
    let result = reserve(preferred, preferred_retained)
    let (result, funded, retained_funded) = if result
      is Err(WorkspaceBudgetUnavailable) &&
      (preferred > minimum || preferred_retained > minimum_retained) &&
      !growth.failed {
      // The callback promises no reservation/current/resource mutation for
      // this specific refusal. Every other error is terminal, never retried.
      (reserve(minimum, minimum_retained), minimum, minimum_retained)
    } else {
      (result, preferred, preferred_retained)
    }
    growth.busy = false
    if result is Err(_) || growth.failed {
      growth.failed = true
      return false
    }
    growth.funded = funded
    growth.retained_funded = retained_funded
  }
  growth.used = extra
  if growth.retained_outputs is Some(_) {
    growth.retained_outputs = Some(retained)
  }
  growth.slots = slots
  growth.logical = logical
  growth.text = text
  growth.text_peak = text_peak
  growth.slot_peak = slot_peak
  growth.logical_peak = logical_peak
  true
}

///|
/// Attach only at actual task start, after original current/claim admission.
/// Explicit execution limits remain enforcement ceilings. This attachment
/// funds actual logical values, Text and output growth on the same Task; it
/// does not turn a selected structural workspace limit into a prepaid hint.
pub fn bind_generated_workspace_growth(
  generated : GeneratedSequence,
  limits : SequenceExecutionLimits,
  live_ceiling : Int64,
  reserve : (Int64) -> Result[Unit, WorkspaceGrowthIssue],
  meter_retained_outputs? : Bool = false,
  reserve_retained? : ((Int64, Int64) -> Result[Unit, WorkspaceGrowthIssue])? = None,
  prepaid_operation_slots? : Int? = None,
  track_output_origin? : Bool = false,
) -> Result[GeneratedSequence, SequenceRunIssue] {
  let initial_slots = prepaid_operation_slots.unwrap_or(
    limits.rows.operation_entries,
  )
  if initial_slots < 0 ||
    initial_slots > limits.rows.operation_entries ||
    live_ceiling < 0L ||
    generated.working is Some(_) ||
    (reserve_retained is Some(_) && !meter_retained_outputs) {
    return Err(InvalidLimits)
  }
  let mut initial_live = 0L
  for context in generated.contexts {
    if !capacity_uses_fragment_step(
        generated,
        @lower.kernel_step(context.kernel),
      ) {
      continue
    }
    let selected = select_generated_sequence_step(
      generated,
      @lower.kernel_step(context.kernel),
    )
    if selected
      .map(selected => {
        bounded_leaf_fragment_capacity(selected, context, limits) is None
      })
      .unwrap_or(true) {
      initial_live = Int64::max(
        initial_live,
        context.limits.max_live_value_bytes,
      )
    }
  }
  Ok({
    ..generated,
    working: Some({
      initial_slots,
      initial_live,
      live_ceiling,
      reserve,
      reserve_retained,
      output_origin: if track_output_origin {
        Some({ token: Ref(()), })
      } else {
        None
      },
      slots: 0,
      logical: 0L,
      text: 0L,
      text_peak: 0L,
      slot_peak: 0,
      logical_peak: 0L,
      funded: 0L,
      used: 0L,
      retained_funded: 0L,
      retained_outputs: if meter_retained_outputs {
        Some(0L)
      } else {
        None
      },
      busy: false,
      failed: false,
    }),
  })
}

///|
/// Project a checked component segment onto the current task sequence. The
/// selected task supplies its own narrowed limits, numeric ports, and
/// workspace attachment. The previously checked segment supplies only its
/// original contained coordinates and output selection.
pub fn borrow_generated_component_workspace(
  current : GeneratedSequence,
  segment : GeneratedSequence,
  prepaid_model_prefix? : Bool = false,
) -> GeneratedSequence? {
  let owner = generated_sequence_owner(current)
  let count = generated_sequence_step_count(segment)
  guard current.working is Some(_) &&
    segment.working is None &&
    physical_equal(owner, generated_sequence_owner(segment)) &&
    physical_equal(current.contracts, segment.contracts) &&
    physical_equal(current.query_time, segment.query_time) &&
    count > 0 else {
    return None
  }
  let prefix_end = if segment.selected_steps is None &&
    segment.selected_prefix_end is None {
    // The compiler can lower the Model input only to its last Relation
    // step. It then needs no GeneratedSequence selector of its own. Bind
    // that form only at the adjacent checked Infer boundary of this Task.
    guard @lower.sequence_step(current.sequence, count)
      is Some(@lower.InferBoundary(boundary)) &&
      boundary == count &&
      @lower.node_at(@lower.bound_preparation(owner), count - 1)
      is Some(terminal) &&
      segment.retained_ids.length() == 1 &&
      segment.retained_ids[0] == @lower.node_id(terminal) else {
      return None
    }
    Some(count - 1)
  } else {
    segment.selected_prefix_end
  }
  // The separately quoted literal Model prefix paid its complete output
  // retention and working peak at Task entry. Keep the metered attachment on
  // the whole Task for Model output. Seeing a prefix alone grants no backing.
  if prepaid_model_prefix {
    guard segment.selected_steps is None &&
      prefix_end == Some(count - 1) &&
      @lower.sequence_step(current.sequence, count)
      is Some(@lower.InferBoundary(boundary)) &&
      boundary == count else {
      return None
    }
  }
  // Both selectors expose the original step coordinates in increasing
  // order. Match them without re-generating or renumbering the sequence.
  let mut selected = 0
  for index in 0..<generated_sequence_step_count(current) {
    if generated_sequence_step_index_at(current, index) ==
      generated_sequence_step_index_at(segment, selected) {
      selected += 1
      if selected == count {
        return Some({
          ..current,
          selected_steps: segment.selected_steps,
          selected_prefix_end: prefix_end,
          retained_ids: segment.retained_ids,
          working: if prepaid_model_prefix {
            None
          } else {
            current.working
          },
        })
      }
    }
  }
  None
}

///|
fn working_row_workspace(
  generated : GeneratedSequence,
  initial : Int,
) -> RowWorkspace {
  // A Fragment's value-byte ceiling has a different subject and unit. It
  // cannot enlarge the caller's explicit per-operation entry ceiling.
  { ..row_workspace(initial), growth: generated.working, }
}

///|
// Existing output budgets supply complete cumulative usage before a row is
// transferred into persistent storage. Each budget retains its funded peak;
// all buffers compose on the same task attachment through original cleanup.
fn output_retention_required_bytes(nodes : Int, text : Int) -> Int64? {
  execution_capacity_inventory_add(0L, ValueNodeSlots, nodes.to_int64(), 1).bind(node_bytes => {
      execution_capacity_inventory_add(
        node_bytes,
        DecodedTextBytes,
        text.to_int64(),
        1,
      )
    },
  )
}

///|
fn fund_output_retention(budget : ValueBudget, nodes : Int, text : Int) -> Bool {
  guard budget.retention is Some(growth) &&
    growth.retained_outputs is Some(total) else {
    return true
  }
  let (nodes, text, copies) = match budget.row_scratch_start {
    None => (nodes, text, 1L)
    Some((start_nodes, start_text)) =>
      (
        nodes - start_nodes,
        text - start_text,
        if start_nodes == 0 && start_text == 0 {
          1L
        } else {
          2L
        },
      )
  }
  // The first row has no previous admission-owned backing. After that,
  // Array.clear may retain the previous Native row: keep TWO largest rows,
  // including a large first row followed by a smaller one. Original producer
  // and import charges stay separate; no funded peak is returned or reset.
  guard output_retention_required_bytes(nodes, text) is Some(row_bytes) else {
    growth.failed = true
    return false
  }
  let peak = if budget.row_scratch_start is Some(_) {
    Int64::max(row_bytes, budget.row_scratch_peak)
  } else {
    row_bytes
  }
  guard checked_preparation_add_product(0L, peak, copies) is Some(required) else {
    growth.failed = true
    return false
  }
  let required = if budget.row_scratch_start is Some(_) {
    Int64::max(required, budget.retention_funded)
  } else {
    required
  }
  guard !growth.failed &&
    !growth.busy &&
    required >= budget.retention_funded &&
    required - budget.retention_funded <= 9223372036854775807L - total else {
    growth.failed = true
    return false
  }
  let delta = required - budget.retention_funded
  let next = total + delta
  if growth.used <= growth.funded &&
    delta <= growth.funded - growth.used &&
    (growth.reserve_retained is None || next <= growth.retained_funded) {
    // Already funded: no reservation callback, inventory allocation, provider
    // call or current observer for each row. The buffer still checks liveness
    // immediately before its original commit.
    growth.used += delta
    growth.retained_outputs = Some(next)
    budget.retention_funded = required
    budget.row_scratch_peak = peak
    return true
  }
  if !grow_workspace(growth, growth.slots, growth.logical, retained=Some(next)) {
    return false
  }
  budget.retention_funded = required
  budget.row_scratch_peak = peak
  true
}

///|
/// Identity of the exact metered output attachment. No resource handle or
/// callback is retained by this witness.
struct OutputWorkspaceOriginal {
  token : Ref[Unit]
}

///|
pub fn generated_output_workspace_original(
  sequence : GeneratedSequence,
) -> OutputWorkspaceOriginal? {
  sequence.working.bind(growth => growth.output_origin)
}

///|
pub fn same_output_workspace_original(
  left : OutputWorkspaceOriginal,
  right : OutputWorkspaceOriginal,
) -> Bool {
  physical_equal(left.token, right.token)
}
