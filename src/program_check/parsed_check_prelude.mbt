///|
/// Completed original support/declaration scans, NOT a complete check or Allow.
/// The original input and SAME remaining semantic budget stay private. The next
/// Catalog/Context/Unit constructor requires its own complete funded overlap.
pub struct ParsedCheckPrelude {
  priv original : ParsedCheckInput
  priv budget : IdentityBudget
  priv declaration_work : Int
  priv mut available : Bool
}

///|
pub(all) enum ParsedCheckPreludeIssue {
  AlreadyConsumed
} derive(Eq, Debug)

///|
/// Actual remaining semantic-work restriction, after original evidence binding.
/// It is work DATA, never a representation-size or physical-memory quotation.
pub fn parsed_check_input_semantic_work(original : ParsedCheckInput) -> Int {
  original.limits.work - @context.capacity_inputs_work(original.inputs)
}

///|
/// Caller funds this phase BEFORE entry. Work is observed from the SAME budget
/// and audit cell, including partial typed refusal; no second scan is run.
pub fn observe_parsed_check_prelude(
  original : ParsedCheckInput,
) -> (Result[ParsedCheckPrelude, LocalConstructionFailure], Int) {
  let maximum = parsed_check_input_semantic_work(original)
  let limits = original.limits.artifacts
  let budget = IdentityBudget::{
    work: maximum,
    bytes: limits.bytes,
    nodes: limits.nodes,
    depth: limits.depth,
  }
  let audit = DeclarationAuditWork::{ declaration_remaining: maximum, }
  let mut audit_started = false
  let result = try {
    if maximum < 0 || limits.bytes < 0 || limits.nodes < 0 || limits.depth < 0 {
      raise LocalConstructionFailure::InvalidLimits
    }
    check_supported_source(original.program, budget)
    audit.declaration_remaining = budget.work
    audit_started = true
    audit_declarations_owned(
      original.program,
      audit,
      effect_headers=original.effect_headers,
    ) catch {
      issue => raise LocalConstructionFailure::Source(issue)
    }
    Ok({
      original,
      budget,
      declaration_work: budget.work - audit.declaration_remaining,
      available: true,
    })
  } catch {
    issue => Err(issue)
  }
  let spent = if maximum < 0 {
    0
  } else if audit_started {
    maximum - audit.declaration_remaining
  } else {
    maximum - budget.work
  }
  (result, spent)
}

///|
/// Original remaining work for the next semantic receipt. Reading this DATA
/// neither enters that constructor nor issues capacity or a reusable verdict.
pub fn parsed_check_prelude_remaining_work(
  prepared : ParsedCheckPrelude,
) -> Result[Int, ParsedCheckPreludeIssue] {
  if !prepared.available {
    return Err(AlreadyConsumed)
  }
  Ok(prepared.budget.work - prepared.declaration_work)
}

///|
/// Consume this original once. The actual Catalog branch, typed missing inputs,
/// full checker and error projection are unchanged. The caller must fund all
/// of those constructors before invoking this continuation.
pub fn finish_parsed_check_prelude(
  prepared : ParsedCheckPrelude,
) -> Result[CheckOutcome, ParsedCheckPreludeIssue] {
  if !prepared.available {
    return Err(AlreadyConsumed)
  }
  prepared.available = false
  let original = prepared.original
  let {
    program,
    environment,
    supplied,
    effect_headers,
    inputs,
    limits,
    source_catalog,
    source_preparation,
  } = original
  Ok(
    checking_outcome(program, environment, () => {
      check_after_prelude(
        program,
        environment.wire,
        supplied,
        [],
        environment.expressions,
        environment.operations,
        compile_source_limits(limits),
        prepared.budget,
        prepared.declaration_work,
        has_effects=effect_headers is Some(_),
        numeric_profile=environment.numeric,
        calendar=environment.calendar,
        text_rank=environment.text_rank,
        capacity_inputs=Some(inputs),
        graph=environment.graph,
        model_tasks=environment.model_tasks,
        request_value_policies=environment.request_value_policies,
        source_catalog~,
        source_preparation~,
      )
    }),
  )
}

///|
/// Call-expanded logical construction peak. Only the copied Stage array grows
/// with actual Stage count. Cursor/Option/tuple/closure/error sites below do not
/// retain each loop iteration; keys, row/parameter/step bodies stay borrowed.
/// Core budget/audit/closure/holder/result tuple:6H5R8W. Three field_at sites
/// plus the support member field:4*(5H7R3W); two element_at sites:2*(4H4R4W);
/// six length Options:6H6W; typed error alternatives:5H5R. This deliberately
/// co-counts sequential alternatives; it is not minimal storage or RSS.
pub fn parsed_check_prelude_construction_inventory(
  original : ParsedCheckInput,
) -> @shape.CollectionConstructionInventory {
  let child = @decode.indexed_child_construction_extent()
  let field = @decode.indexed_field_construction_extent()
  {
    records: 17L + 4L * field.record_headers + 2L * child.record_headers,
    record_references: 10L +
    4L * field.reference_slots +
    2L * child.reference_slots,
    record_words: 14L + 4L * field.scalar_words + 2L * child.scalar_words,
    reference_arrays: 1L,
    reference_items: @syntax.stage_count(original.program).to_int64(),
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  }
}
