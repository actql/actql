///|
/// The same checked Mapping and original Result traversal remain attached to
/// every typed value. Encoding these values is not authorization to dispatch,
/// approval evidence, target identity or a physical cleanup acknowledgement.
struct CapturedEffectCheckedProposalRow {
  mut plan : CapturedEffectProposalPlan?
  mut exported : CapturedEffectLocalResultExport?
  mut original : @execution.CompletedOutputExportOriginalRow?
  mut checked : @results.EffectPlanCheckedRow?
  index : Int
}

///|
pub(all) enum CapturedEffectCheckedProposalIssue {
  NotReady
  ForeignExport
  RowOrder
  ProjectionUnavailable
  ConversionUnavailable
  OriginalRow(@execution.CompletedExportOriginalRowIssue)
  Projection(@results.EffectPlanCheckedRowIssue)
} derive(Debug)

///|
fn captured_effect_checked_proposal_plan_retained(
  plan : CapturedEffectProposalPlan,
) -> Bool {
  plan.live &&
  !plan.inputs.run.captured.stopped &&
  captured_effect_input_retained(plan.inputs, plan.member_index, plan.input) &&
  captured_effect_optional_command_key_retained(plan.input_key, plan.inputs)
}

///|
fn captured_effect_checked_proposal_plan_current(
  plan : CapturedEffectProposalPlan,
) -> Bool {
  captured_effect_checked_proposal_plan_retained(plan) &&
  captured_effect_optional_command_target_current(
    plan.published_target,
    plan.inputs,
    plan.member_index,
    plan.command,
  ) &&
  captured_effect_optional_command_key_current(
    plan.input_key,
    plan.inputs,
    plan.member_index,
    plan.command,
  ) &&
  captured_effect_input_at(plan.inputs, plan.member_index).map(input => {
    physical_equal(input, plan.input)
  }) ==
  Some(true) &&
  captured_effect_checked_proposal_plan_retained(plan)
}

///|
fn captured_effect_checked_proposal_export_matches(
  plan : CapturedEffectProposalPlan,
  exported : CapturedEffectLocalResultExport,
  original : @execution.CompletedOutputExportOriginalRow,
) -> Bool {
  captured_effect_local_result_export_retained(plan.inputs, exported) &&
  captured_effect_local_result_export_derived_retained(exported) &&
  exported.result.stage == captured_effect_input_stage(plan.input) &&
  captured_any_result_borrows_share_view(
    exported.result.borrow,
    plan.input.borrow,
  ) &&
  @execution.completed_result_export_preparation_matches_original_row(
    exported.preparation,
    original,
  ) &&
  captured_effect_local_result_export_retained(plan.inputs, exported) &&
  captured_effect_checked_proposal_plan_retained(plan)
}

///|
/// Advance only this original Mapping Plan using the row token issued by its
/// exact named-Result export. No caller supplies a CanonicalValue, field map,
/// contract or reconstructed CheckedValue through this entry.
pub fn project_captured_effect_checked_proposal_row(
  plan : CapturedEffectProposalPlan,
  exported : CapturedEffectLocalResultExport,
  original : @execution.CompletedOutputExportOriginalRow,
  max_fields : Int,
  max_work : Int,
  values : @value.Limits,
) -> Result[
  CapturedEffectCheckedProposalRow,
  CapturedEffectCheckedProposalIssue,
] {
  if !captured_effect_checked_proposal_plan_current(plan) {
    plan.live = false
    return Err(NotReady)
  }
  if !captured_effect_checked_proposal_export_matches(plan, exported, original) {
    plan.live = false
    return Err(ForeignExport)
  }
  let index = @execution.completed_output_export_original_row_index(original)
  if index != plan.next_row {
    plan.live = false
    return Err(RowOrder)
  }
  guard plan.terminal is Some(terminal) && plan.command is None else {
    // Other existing proposal paths retain their own behavior. A Command or
    // create row has not acquired this direct field projection by shape.
    plan.live = false
    return Err(ProjectionUnavailable)
  }
  let rule = @results.effect_plan_terminal_rule(terminal)
  if @environment.mapping_conversion_count(
      @results.effect_mapping_rule_conversions(rule),
    ) !=
    0 {
    // A declared conversion law is not an installed converter implementation.
    plan.live = false
    return Err(ConversionUnavailable)
  }
  let read_issue : Ref[@execution.CompletedExportOriginalRowIssue?] = Ref(None)
  let checked = match
    @results.project_effect_plan_checked_row(
      terminal,
      plan.literals,
      index,
      fn(name, remaining, limits) {
        match
          @execution.completed_output_export_original_row_checked_field_usage(
            original, name, max_fields, remaining, limits,
          ) {
          Ok(value) => Some(value)
          Err(issue) => {
            read_issue.val = Some(issue)
            None
          }
        }
      },
      max_fields,
      max_work,
      values,
    ) {
    Ok(value) => value
    Err(issue) => {
      plan.live = false
      return Err(
        match read_issue.val {
          Some(issue) => OriginalRow(issue)
          None => Projection(issue)
        },
      )
    }
  }
  if !captured_effect_checked_proposal_plan_current(plan) ||
    !captured_effect_checked_proposal_export_matches(plan, exported, original) {
    plan.live = false
    return Err(NotReady)
  }
  if plan.next_row != index {
    plan.live = false
    return Err(RowOrder)
  }
  plan.next_row += 1
  Ok({
    plan: Some(plan),
    exported: Some(exported),
    original: Some(original),
    checked: Some(checked),
    index,
  })
}

///|
pub fn captured_effect_checked_proposal_row_available(
  row : CapturedEffectCheckedProposalRow,
) -> Bool {
  guard row.plan is Some(plan) &&
    row.exported is Some(exported) &&
    row.original is Some(original) &&
    row.checked is Some(_) else {
    return false
  }
  captured_effect_checked_proposal_plan_current(plan) &&
  captured_effect_checked_proposal_export_matches(plan, exported, original) &&
  row.plan is Some(_) &&
  row.original is Some(_) &&
  row.checked is Some(_) &&
  plan.next_row > row.index &&
  plan.next_row - 1 == row.index &&
  captured_effect_checked_proposal_plan_retained(plan)
}

///|
pub fn captured_effect_checked_proposal_row_selector(
  row : CapturedEffectCheckedProposalRow,
) -> @value.CheckedValue? {
  if !captured_effect_checked_proposal_row_available(row) {
    return None
  }
  row.checked.map(value => @results.effect_plan_checked_row_selector(value))
}

///|
pub fn captured_effect_checked_proposal_row_field_count(
  row : CapturedEffectCheckedProposalRow,
) -> Int? {
  if !captured_effect_checked_proposal_row_available(row) {
    return None
  }
  row.checked.map(value => @results.effect_plan_checked_row_field_count(value))
}

///|
pub fn captured_effect_checked_proposal_row_field_at(
  row : CapturedEffectCheckedProposalRow,
  index : Int,
) -> (String, @value.CheckedValue)? {
  if !captured_effect_checked_proposal_row_available(row) {
    return None
  }
  row.checked.bind(value => {
    @results.effect_plan_checked_row_field_at(value, index)
  })
}

///|
pub fn retire_captured_effect_checked_proposal_row(
  row : CapturedEffectCheckedProposalRow,
) -> Unit {
  row.plan = None
  row.exported = None
  row.original = None
  row.checked = None
}
