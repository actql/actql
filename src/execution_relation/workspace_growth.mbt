///|
/// An attempt-local attachment to the existing task's workspace reservation.
/// It owns no capacity or execution permission. The caller must grow that SAME
/// reservation before returning success; the original task owns all cleanup.
priv struct WorkspaceGrowth {
  initial_slots : Int
  initial_live : Int64
  live_ceiling : Int64
  reserve : (Int64) -> Result[Unit, WorkspaceGrowthIssue]
  mut slots : Int
  mut logical : Int64
  mut text : Int64
  mut text_peak : Int64
  mut slot_peak : Int
  mut logical_peak : Int64
  mut funded : Int64
  mut used : Int64
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
  if extra > growth.funded {
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
    let preferred = extra + spare
    growth.busy = true
    let result = (growth.reserve)(preferred)
    let (result, funded) = if result is Err(WorkspaceBudgetUnavailable) &&
      preferred > extra &&
      !growth.failed {
      // The callback promises no reservation/current/resource mutation for
      // this specific refusal. Every other error is terminal, never retried.
      ((growth.reserve)(extra), extra)
    } else {
      (result, preferred)
    }
    growth.busy = false
    if result is Err(_) || growth.failed {
      growth.failed = true
      return false
    }
    growth.funded = funded
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
/// The immutable fragment Request remains the finite semantic ceiling. Its
/// smaller runtime window is prepaid; this attachment funds actual growth,
/// rather than reserving every declared maximum before any value is evaluated.
pub fn bind_generated_workspace_growth(
  generated : GeneratedSequence,
  limits : SequenceExecutionLimits,
  live_ceiling : Int64,
  reserve : (Int64) -> Result[Unit, WorkspaceGrowthIssue],
  meter_retained_outputs? : Bool = false,
) -> Result[GeneratedSequence, SequenceRunIssue] {
  let initial_slots = limits.rows.operation_entries
  if initial_slots < 0 || live_ceiling < 0L || generated.working is Some(_) {
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
      slots: 0,
      logical: 0L,
      text: 0L,
      text_peak: 0L,
      slot_peak: 0,
      logical_peak: 0L,
      funded: 0L,
      used: 0L,
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
fn working_row_workspace(
  generated : GeneratedSequence,
  initial : Int,
) -> RowWorkspace {
  let mut maximum = initial
  if generated.working is Some(_) {
    for context in generated.contexts {
      let (_, bytes) = @lower.fragment_request_ceilings(
        context.fragment.candidate.material.request.request,
      )
      if bytes <= (2147483647 - initial).to_int64() {
        maximum = Int::max(maximum, initial + bytes.to_int())
      }
    }
  }
  { ..row_workspace(maximum), growth: generated.working, }
}

///|
// Existing output budgets supply complete cumulative usage before a row is
// transferred into persistent storage. Each budget retains its funded peak;
// all buffers compose on the same task attachment through original cleanup.
fn fund_output_retention(budget : ValueBudget, nodes : Int, text : Int) -> Bool {
  guard budget.retention is Some(growth) &&
    growth.retained_outputs is Some(total) else {
    return true
  }
  guard !growth.failed &&
    !growth.busy &&
    execution_capacity_inventory_add(0L, ValueNodeSlots, nodes.to_int64(), 1)
    is Some(node_bytes) &&
    execution_capacity_inventory_add(
      node_bytes,
      DecodedTextBytes,
      text.to_int64(),
      1,
    )
    is Some(required) &&
    required >= budget.retention_funded &&
    required - budget.retention_funded <= 9223372036854775807L - total else {
    growth.failed = true
    return false
  }
  let delta = required - budget.retention_funded
  let next = total + delta
  if growth.used <= growth.funded && delta <= growth.funded - growth.used {
    // Already funded: no reservation callback, inventory allocation, provider
    // call or current observer for each row. The buffer still checks liveness
    // immediately before its original commit.
    growth.used += delta
    growth.retained_outputs = Some(next)
    budget.retention_funded = required
    return true
  }
  if !grow_workspace(growth, growth.slots, growth.logical, retained=Some(next)) {
    return false
  }
  budget.retention_funded = required
  true
}
