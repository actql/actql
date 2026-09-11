///|
pub(all) struct Limits {
  max_work : Int
  max_slots : Int
  max_references : Int
  max_pointer_units : Int
  max_direct_text_bytes : Int
} derive(Eq, Debug)

///|
pub(all) enum Issue {
  InvalidLimits
  ForeignRoot
  WorkLimit
  Slots(@pipeline.ExpressionSlotIssue)
  Syntax(@expression.Issue)
  References(@references.Issue)
} derive(Eq, Debug)

///|
struct Collected {
  pipeline : @pipeline.CheckedPipeline
  expressions : @pipeline.ExpressionSlots
  operands : @pipeline.ParameterSlots
  index : @references.Index
  work : Int
  direct_text_bytes : Int
}

///|
priv suberror Stop {
  Stop(Issue)
}

///|
priv struct Budget {
  mut remaining : Int
}

///|
fn spend(budget : Budget, amount : Int) -> Unit raise Stop {
  if amount > budget.remaining {
    raise Stop(WorkLimit)
  }
  budget.remaining -= amount
}

///|
/// Collect all currently admitted local operation Parameter slots, not a caller
/// selected subset. The root determines pointer coordinates, not Program validity.
pub fn collect(
  root : @decode.Cursor,
  pipeline : @pipeline.CheckedPipeline,
  limits : Limits,
) -> Result[Collected, Issue] {
  if limits.max_work < 0 ||
    limits.max_slots < 0 ||
    limits.max_references < 0 ||
    limits.max_pointer_units < 0 ||
    limits.max_direct_text_bytes < 0 {
    return Err(InvalidLimits)
  }
  try {
    let source = @pipeline.source(pipeline)
    if @decode.tree_index(root, source) is None {
      raise Stop(ForeignRoot)
    }
    let base = @decode.cursor_path(root)
    let path = @decode.cursor_path(source)
    if base.length() > path.length() {
      raise Stop(ForeignRoot)
    }
    let budget = { remaining: limits.max_work, }
    spend(budget, base.length())
    spend(budget, path.length())
    for i in 0..<base.length() {
      if base[i] != path[i] {
        raise Stop(ForeignRoot)
      }
    }
    let expressions = match
      @pipeline.collect_expression_slots(
        pipeline,
        max_work=budget.remaining,
        max_slots=limits.max_slots,
      ) {
      Ok(v) => v
      Err(e) => raise Stop(Slots(e))
    }
    spend(budget, @pipeline.expression_slots_work(expressions))
    let expression_count = @pipeline.expression_slot_count(expressions)
    let operands = match
      @pipeline.collect_parameter_slots(
        pipeline,
        max_work=budget.remaining,
        max_slots=limits.max_slots - expression_count,
      ) {
      Ok(v) => v
      Err(e) => raise Stop(Slots(e))
    }
    spend(budget, @pipeline.parameter_slots_work(operands))
    let occurrences : Array[@expression.ParameterOccurrences] = []
    let mut reference_count = 0
    let mut direct_text = limits.max_direct_text_bytes
    for i in 0..<(expression_count + @pipeline.parameter_slot_count(operands)) {
      let expression = if i < expression_count {
        @typing.expression(
          @pipeline.expression_slot_at(expressions, i).unwrap().expression,
        )
      } else {
        let operand = @pipeline.parameter_slot_at(
          operands,
          i - expression_count,
        ).unwrap()
        // A direct operand is exactly an object and a string. Account for the
        // two retained nodes as well as common admission's visited nodes.
        spend(budget, 2)
        let syntax = match
          @expression.admit(operand.source, {
            max_nodes: budget.remaining,
            max_depth: 2,
            max_tokens: 0,
            max_text_bytes: direct_text,
            tree: {
              max_nodes: 2,
              max_depth: 1,
              max_string_bytes: direct_text,
              max_total_string_bytes: direct_text,
            },
          }) {
          Ok(v) => v
          Err(e) => raise Stop(Syntax(e))
        }
        let usage = @expression.usage(syntax)
        spend(budget, usage.nodes)
        direct_text -= usage.text_bytes
        syntax
      }
      let refs = match
        @expression.collect_parameter_occurrences(
          expression,
          max_work=budget.remaining,
        ) {
        Ok(v) => v
        Err(e) => raise Stop(Syntax(e))
      }
      spend(budget, @expression.parameter_occurrence_work(refs))
      let count = @expression.parameter_occurrence_count(refs)
      if count > limits.max_references - reference_count {
        raise Stop(References(ReferenceLimit))
      }
      reference_count += count
      occurrences.push(refs)
    }
    spend(budget, occurrences.length())
    spend(budget, reference_count)
    let declarations = match @pipeline.parameters(pipeline) {
      Some(d) => d
      None =>
        @parameter.read_declarations(None, {
          max_parameters: 0,
          max_nodes: 0,
          max_depth: 0,
          max_text_bytes: 0,
        }).unwrap()
    }
    let index = match
      @references.build(root, declarations, occurrences, {
        max_slots: limits.max_slots,
        max_references: limits.max_references,
        max_pointer_units: if budget.remaining < limits.max_pointer_units {
          budget.remaining
        } else {
          limits.max_pointer_units
        },
      }) {
      Ok(v) => v
      Err(e) => raise Stop(References(e))
    }
    spend(budget, @references.pointer_units(index))
    Ok({
      pipeline,
      expressions,
      operands,
      index,
      work: limits.max_work - budget.remaining,
      direct_text_bytes: limits.max_direct_text_bytes - direct_text,
    })
  } catch {
    Stop(e) => Err(e)
  }
}

///|
pub fn pipeline(value : Collected) -> @pipeline.CheckedPipeline {
  value.pipeline
}

///|
pub fn index(value : Collected) -> @references.Index {
  value.index
}

///|
pub fn expressions(value : Collected) -> @pipeline.ExpressionSlots {
  value.expressions
}

///|
pub fn operands(value : Collected) -> @pipeline.ParameterSlots {
  value.operands
}

///|
pub fn work(value : Collected) -> Int {
  value.work
}

///|
pub fn direct_text_bytes(value : Collected) -> Int {
  value.direct_text_bytes
}
