///|
// The inexpensive predicate scan is not a proof. It only avoids constructing
// a prefix graph when no literal success test can possibly be relevant.
fn infer_filter_may_refine(
  b : Budget,
  checked : @relation.CheckedOperation,
) -> Bool raise Stop {
  let source = @relation.source(checked)
  let expression = @relation.binding_expression_at(checked, 0).unwrap()
  let pending = [0]
  while pending.pop() is Some(index) {
    spend(b, source, 1)
    match @typing.node_form(expression, index) {
      Some(Expression("and", _)) => {
        let count = @typing.child_count(expression, index).unwrap()
        spend(b, source, count)
        for i in 0..<count {
          pending.push(@typing.child_at(expression, index, i).unwrap())
        }
      }
      Some(Expression("eq", _)) =>
        for i in [0, 1] {
          let child = @typing.child_at(expression, index, i).unwrap()
          if @typing.node_form(expression, child)
            is Some(Expression("literal", body)) &&
            @decode.text(body) == Ok("ok") {
            return true
          }
        }
      _ => ()
    }
  }
  false
}

///|
fn infer_filter_refinement(
  b : Budget,
  source : @decode.Cursor,
  steps : Array[CheckedStep],
  checked : @relation.CheckedOperation,
) -> @evidence.RefinedFilter? raise Stop {
  if !infer_filter_may_refine(b, checked) {
    return None
  }
  spend(b, source, steps.length())
  let nodes : Array[@evidence.InferFilterNode] = []
  for step in steps {
    nodes.push(
      match step.filter_refinement {
        Some(proof) => @evidence.Refined(proof)
        None =>
          match step.operation {
            Infer(checked) => @evidence.Infer(checked)
            Unary(checked) =>
              match @relation.operation(checked) {
                Filter
                | Derive
                | Select
                | Rename
                | Drop
                | Sort
                | Take
                | Distinct
                | DedupeRows
                | AssertRows => @evidence.Unary(checked)
                _ => @evidence.Other(step.source, step_schema(step))
              }
            Join(checked~, ..) => @evidence.Join(checked)
            _ => @evidence.Other(step.source, step_schema(step))
          }
      },
    )
  }
  let result = match
    @evidence.refine_infer_filter(source, nodes, checked, {
      max_work: b.work,
      max_nodes: b.nodes,
      max_depth: b.limits.max_depth,
      max_text_bytes: b.text,
    }) {
    Ok(value) => value
    Err(issue) =>
      match issue.kind {
        ProofBudgetExceeded => fail(issue.source, BudgetExceeded)
        _ => fail(issue.source, KeyEvidence(@evidence.InputContractMismatch))
      }
  }
  b.work -= result.work
  b.nodes -= result.nodes
  b.text -= result.text_bytes
  if physical_equal(
      @evidence.refined_filter_output(result.proof),
      @relation.output_schema(checked),
    ) {
    None
  } else {
    Some(result.proof)
  }
}
