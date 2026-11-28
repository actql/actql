///|
// Row DATA belongs to this capture and its existing Plan. Member order and
// per-member source row order are independent of the Result inventory order.
priv struct InstalledEffectResultProposals {
  owner : ClientInstalledManagedRun
  plan : ClientInstalledEffectManagedPlan
  max_fields : Int
  max_work : Int
  values : @admitted.Limits
  row_limit : Int
  members : Array[InstalledEffectResultProposalMember]
}

///|
priv struct InstalledEffectResultProposalMember {
  index : Int
  plan : @strategy.CapturedEffectProposalPlan
  changes : Int
  rows : Array[InstalledEffectResultProposal]
}

///|
/// Read-only access to one typed proposal on the original capture. Its
/// source and write authority remain with the separate Effect owners.
struct InstalledEffectResultProposal {
  row : @stage_results.EffectPlanCheckedRow
}

///|
pub fn InstalledEffectResultProposal::selector(
  self : InstalledEffectResultProposal,
) -> @admitted.CheckedValue {
  @stage_results.effect_plan_checked_row_selector(self.row)
}

///|
pub fn InstalledEffectResultProposal::field_at(
  self : InstalledEffectResultProposal,
  index : Int,
) -> (String, @admitted.CheckedValue)? {
  @stage_results.effect_plan_checked_row_field_at(self.row, index)
}

///|
fn InstalledEffectResultProposals::current(
  self : InstalledEffectResultProposals,
) -> Bool {
  effect_unit_publication_body(self.owner, self.plan, self.plan.request)
  is Ok(_)
}

///|
fn prepare_installed_effect_result_proposals(
  owner : ClientInstalledManagedRun,
  plan : ClientInstalledEffectManagedPlan,
  inputs : @strategy.CapturedEffectInputs,
  result_index : Int,
  borrow : @strategy.CapturedAnyResultBorrow,
  max_fields : Int,
) -> Result[InstalledEffectResultProposals?, InstalledEffectResultCaptureIssue] {
  let count = @strategy.captured_effect_inputs_count(inputs)
  let mut members = 0
  for index in 0..<count {
    if @strategy.captured_effect_local_result_matches_member(
        inputs, result_index, index,
      ) {
      members += 1
    }
  }
  if members == 0 {
    return Ok(None)
  }
  let effects = @publication_host.client_standard_effect_computation_limits().effects
  guard count <= effects.max_members &&
    max_fields >= 0 &&
    @strategy.captured_any_result_borrow_row_count(borrow) is Some(rows) &&
    rows >= 0 else {
    return Err(Unit(Run(InsufficientCapacity)))
  }
  let m = members.to_int64()
  let pairs = m * max_fields.to_int64()
  // One member inventory, one field-map builder and one row array per
  // selected member. Text and checked input bodies remain original borrows.
  guard @execution.preparation_array_representation(
      1L + 2L * m,
      m + pairs + m * rows.to_int64(),
      true,
    )
    is Some(array) &&
    @execution.preparation_representation_cost({
      record_headers: array.record_headers + 12L + 16L * m + pairs,
      reference_slots: array.reference_slots + 20L + 31L * m + 2L * pairs,
      scalar_words: array.scalar_words + 12L + 16L * m,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(bytes) &&
    @execution.execution_capacity(bytes, bytes) is Some(capacity) else {
    return Err(Unit(Run(InsufficientCapacity)))
  }
  match
    reserve_effect_unit_publication_capacity(
      owner,
      plan,
      plan.request,
      capacity,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Unit(Run(issue)))
  }
  let selected : Array[InstalledEffectResultProposalMember] = Array(
    capacity=members,
  )
  for index in 0..<count {
    if !@strategy.captured_effect_local_result_matches_member(
        inputs, result_index, index,
      ) {
      continue
    }
    let original = match
      @strategy.prepare_captured_effect_proposal_plan(
        inputs,
        index,
        max_fields,
        effects.max_work,
      ) {
      Ok(original) => original
      Err(issue) => return Err(ProposalPlan(issue))
    }
    guard @strategy.captured_effect_checked_proposal_change_count(original)
      is Some(changes) else {
      return Err(ProposalRow(ProjectionUnavailable))
    }
    selected.push({
      index,
      plan: original,
      changes,
      rows: Array(capacity=rows),
    })
  }
  guard selected.length() == members else {
    return Err(Unit(Run(ForeignOriginal)))
  }
  Ok(
    Some({
      owner,
      plan,
      max_fields,
      max_work: effects.max_work,
      values: {
        max_nodes: effects.max_admission_nodes,
        max_depth: effects.max_admission_depth,
        max_text_bytes: effects.max_admission_text_bytes,
      },
      row_limit: rows,
      members: selected,
    }),
  )
}

///|
fn installed_effect_result_proposal_row_capacity(
  changes : Int,
  depth : Int,
) -> @execution.ExecutionCapacity? {
  let count = changes.to_int64()
  let frames = depth.to_int64() + 1L
  guard @execution.preparation_array_representation(1L, count, true)
    is Some(array) else {
    return None
  }
  // Selector and mapped field CheckedValues borrow their input data. Count
  // the row, field pairs and value wrappers as retained, with one bounded
  // sort and recursive value recheck live per projected selected.
  @execution.preparation_execution_capacity({
    retained: {
      record_headers: array.record_headers + 6L + 3L * count,
      reference_slots: array.reference_slots + 11L + 5L * count,
      scalar_words: array.scalar_words + 4L + 2L * count,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
    workspace: {
      record_headers: array.record_headers + 36L + 12L * frames,
      reference_slots: array.reference_slots + 64L + 32L * frames,
      scalar_words: array.scalar_words + 30L + 16L * frames,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  })
}

///|
fn InstalledEffectResultProposals::collect(
  self : InstalledEffectResultProposals,
  exported : @strategy.CapturedEffectLocalResultExport,
  original : @execution.CompletedOutputExportOriginalRow,
) -> Result[Unit, InstalledEffectResultCaptureIssue] {
  let row_index = @execution.completed_output_export_original_row_index(
    original,
  )
  guard row_index >= 0 && row_index < self.row_limit else {
    return Err(ProposalRow(RowOrder))
  }
  for selected in self.members {
    if selected.rows.length() != row_index {
      return Err(ProposalRow(RowOrder))
    }
    guard installed_effect_result_proposal_row_capacity(
        selected.changes,
        self.values.max_depth,
      )
      is Some(capacity) else {
      return Err(Unit(Run(InsufficientCapacity)))
    }
    match
      reserve_effect_unit_publication_capacity(
        self.owner,
        self.plan,
        self.plan.request,
        capacity,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(Unit(Run(issue)))
    }
    let row = match
      @strategy.project_captured_effect_checked_proposal_row(
        selected.plan,
        exported,
        original,
        self.max_fields,
        self.max_work,
        self.values,
      ) {
      Ok(row) => row
      Err(issue) => return Err(ProposalRow(issue))
    }
    defer @strategy.retire_captured_effect_checked_proposal_row(row)
    guard @strategy.captured_effect_checked_proposal_row_data(row) is Some(data) else {
      return Err(ProposalRow(NotReady))
    }
    if !self.current() {
      return Err(Unit(Run(ForeignOriginal)))
    }
    selected.rows.push({ row: data, })
  }
  Ok(())
}

///|
fn InstalledEffectResultProposals::finish(
  self : InstalledEffectResultProposals,
  rows : Int,
) -> Result[Unit, InstalledEffectResultCaptureIssue] {
  if !self.current() {
    return Err(Unit(Run(ForeignOriginal)))
  }
  if rows != self.row_limit {
    return Err(ProposalPlan(RowCountMismatch))
  }
  for selected in self.members {
    if selected.rows.length() != rows {
      return Err(ProposalPlan(RowCountMismatch))
    }
    match @strategy.finish_captured_effect_proposal_plan(selected.plan, rows) {
      Ok(_) => ()
      Err(issue) => return Err(ProposalPlan(issue))
    }
  }
  if !self.current() {
    return Err(Unit(Run(ForeignOriginal)))
  }
  Ok(())
}

///|
fn InstalledEffectResultProposals::retire(
  self : InstalledEffectResultProposals,
) -> Unit {
  for selected in self.members {
    @strategy.cancel_captured_effect_proposal_plan(selected.plan)
  }
  self.members.clear()
}

///|
/// Count the original member's completed proposals before allocating its
/// target evidence. A foreign member has no row count.
pub fn InstalledEffectResultCapture::proposal_row_count(
  self : InstalledEffectResultCapture,
  member_index : Int,
) -> Int? {
  guard self.proposals is Some(proposals) &&
    self.original() is Some(_) &&
    proposals.current() else {
    return None
  }
  for selected in proposals.members {
    if selected.index == member_index {
      return Some(selected.rows.length())
    }
  }
  None
}

///|
/// The exact export must have completed before the Checkpoint preparation
/// can borrow one member's row DATA. The original capture owns the backing.
pub fn InstalledEffectResultCapture::proposal_row(
  self : InstalledEffectResultCapture,
  member_index : Int,
  row_index : Int,
) -> InstalledEffectResultProposal? {
  guard self.proposals is Some(proposals) &&
    self.original() is Some(_) &&
    proposals.current() else {
    return None
  }
  for selected in proposals.members {
    if selected.index == member_index {
      return selected.rows.get(row_index)
    }
  }
  None
}
