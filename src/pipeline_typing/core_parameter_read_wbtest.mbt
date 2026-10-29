///|
fn[T] original_name_outcome(call : () -> T raise Stop) -> Result[T, IssueKind] {
  let value = call() catch { Stop(issue) => return Err(issue.kind) }
  Ok(value)
}

///|
fn original_parameter_declarations() -> @parameter.Declarations {
  @parameter.read_declarations(
    Some(
      evidence_read_cursor(
        "{\"p\":{\"type\":\"array\",\"items\":{\"type\":\"object\",\"fields\":{\"v\":{\"type\":\"number\"}}},\"default\":[{\"v\":1}]},\"zz\":{\"type\":\"string\",\"nullable\":true,\"default\":\"x\"}}",
      ),
    ),
    { max_parameters: 2, max_nodes: 100, max_depth: 20, max_text_bytes: 1000, },
  ).unwrap()
}

///|
fn original_parameter_core(
  from : @decode.Cursor,
  depth? : Int = 100,
  text? : Int = 10000,
) -> PipelineCoreRead {
  let carrier = evidence_read_carrier()
  begin_pipeline_core_read(
    evidence_read_cursor("[]"),
    [("é", carrier)],
    Some(original_parameter_declarations()),
    Some(from),
    { ..evidence_read_limits(), max_depth: depth, max_text_bytes: text, },
    None,
    None,
    [],
    [None],
    [None],
    [None],
    [CarrierInput(carrier)],
    None,
  ).unwrap()
}

///|
test "source-admitted Parameter declarations and selector consume one Budget and replace only their actual pending domain" {
  let selected = evidence_read_cursor("\"é\"")
  let read = original_parameter_core(selected)
  guard read.state is Reading(body) else { abort("original Core expected") }
  let parameters = body.parameters.unwrap()
  let budget = body.b
  while pipeline_core_read_phase(read) == Inputs {
    let _ = advance_pipeline_core_read(read)
  }
  let mut held = input_construction_bytes(
    core_parameter_retained(body).unwrap(),
  )
  assert_eq(held, 0L)
  let mut changed = false
  while pipeline_core_read_phase(read) == Parameters {
    let q = core_parameter_step_construction(body).unwrap()
    assert_eq(input_construction_bytes(q.replaced), held)
    let old = held
    let _ = advance_pipeline_core_read(read)
    assert_true(pipeline_core_read_phase(read) != Failed)
    held = input_construction_bytes(core_parameter_retained(body).unwrap())
    assert_true(
      held <= old + input_construction_bytes(q.peak) + 2L * q.peak_utf16_units,
    )
    if held < old {
      changed = true
    }
    assert_true(physical_equal(body.b, budget))
    assert_true(physical_equal(body.parameters.unwrap(), parameters))
  }
  assert_true(changed)
  assert_true(pipeline_core_read_phase(read) == ImportedEvidence)
  assert_eq(pipeline_core_read_consumed_work(read), Some(13))
  assert_eq(body.limits.max_text_bytes - body.b.text, 10)
  assert_eq(body.current, Some(Input(0)))
  assert_true(body.parameter_read is None)
  assert_true(body.steps is Some(_))
  assert_true(body.ranked_steps is Some(_))
  assert_true(body.keyed_steps is Some(_))
  // Default values are still original declarations, never rebound or narrowed.
  assert_true(
    @parameter.has_default(@parameter.declaration_at(parameters, 0).unwrap()),
  )
  let carrier = evidence_read_carrier()
  let complete = check_carriers(
    body.source,
    [("é", carrier)],
    Some(parameters),
    Some(selected),
    evidence_read_limits(),
  ).unwrap()
  assert_eq(complete.usage.work, 18)
  assert_eq(complete.usage.text_bytes, 10)
}

///|
test "source-admitted Parameter failures retain exact work and issue before arrays without upgrading to successful Usage" {
  for
    (raw, kind, expected_work) in [
      ("\"missing\"", UnknownName("missing"), 13),
      ("\"\"", InvalidName(""), 13),
      ("1", InvalidBody, 12),
    ] {
    let selected = evidence_read_cursor(raw)
    let read = original_parameter_core(selected)
    while pipeline_core_read_phase(read) != Failed {
      let _ = advance_pipeline_core_read(read)
    }
    assert_eq(pipeline_core_read_consumed_work(read), Some(expected_work))
    guard read.state is Rejected(body, issue) else {
      abort("original typed refusal expected")
    }
    assert_eq(issue.kind, kind)
    assert_true(physical_equal(issue.source, selected))
    assert_true(body.steps is None)
    assert_true(body.parameter_read is None)
    clear_pipeline_core_read(read)
    assert_true(pipeline_core_read_consumed_work(read) is None)
  }
  let read = original_parameter_core(evidence_read_cursor("\"é\""), depth=1)
  while pipeline_core_read_phase(read) != Failed {
    let _ = advance_pipeline_core_read(read)
  }
  assert_eq(pipeline_core_read_consumed_work(read), Some(11))
  guard read.state is Rejected(body, issue) else {
    abort("original nested depth refusal expected")
  }
  assert_eq(issue.kind, BudgetExceeded)
  let nested = body.parameter_read.unwrap()
  assert_true(nested.state is Rejected(_))
  assert_true(body.steps is None)
  clear_pipeline_core_read(read)
  assert_true(nested.state is Cleared)
}

///|
test "selector uses its completed normalization once and preserves spend text empty and invalid-body precedence" {
  let selected = evidence_read_cursor("\"é\"")
  let budget = contract_preflight_original_budget(10, 2)
  let normalized = read_name(budget, selected) catch {
    Stop(_) => abort("original normalized selector expected")
  }
  assert_eq(normalized, "é")
  assert_eq(budget.work, 99)
  assert_eq(budget.text, 0)
  let short = contract_preflight_original_budget(10, 1)
  let failed = original_name_outcome(() => read_name(short, selected))
  assert_true(failed is Err(BudgetExceeded))
  assert_eq(short.work, 99)
  assert_eq(short.text, 1)
  let strict = contract_preflight_original_budget(10, 100)
  let refused = original_name_outcome(() => name(strict, selected, "é"))
  assert_true(refused is Err(InvalidName("é")))
}

///|
test "original Unicode Parameter name fixture retains the actual nominal name refusal" {
  let refused = @parameter.read_declarations(
    Some(
      evidence_read_cursor(
        "{\"p\":{\"type\":\"array\",\"items\":{\"type\":\"object\",\"fields\":{\"v\":{\"type\":\"number\"}}},\"default\":[{\"v\":1}]},\"é\":{\"type\":\"string\",\"nullable\":true,\"default\":\"x\"}}",
      ),
    ),
    { max_parameters: 2, max_nodes: 100, max_depth: 20, max_text_bytes: 1000, },
  )
  assert_true(
    refused is Err(@parameter.ParameterIssue(@parameter.InvalidName, ..)),
  )
}

///|
test "selector from another admitted tree backs its own original issue path" {
  let root = evidence_read_cursor(
    "[".repeat(64) + "\"missing\"" + "]".repeat(64),
  )
  let mut selector = root
  for _ in 0..<64 {
    selector = @decode.elements(selector).unwrap()[0]
  }
  let read = original_parameter_core(selector)
  guard read.state is Reading(body) else { abort("original Core expected") }
  while !(body.phase == Parameters && body.parameter_step is Select) {
    let _ = advance_pipeline_core_read(read)
  }
  let q = core_parameter_step_construction(body).unwrap()
  let original_issue = @decode.issue_path_construction_extent(64L).unwrap()
  assert_true(q.peak.reference_slots >= original_issue.reference_slots)
  assert_true(advance_pipeline_core_read(read) == Failed)
  guard read.state is Rejected(_, issue) else {
    abort("original selector issue expected")
  }
  assert_eq(issue.kind, UnknownName("missing"))
  assert_eq(issue.path.length(), 64)
  assert_true(physical_equal(issue.source, selector))
  clear_pipeline_core_read(read)
}
