///|
pub(all) enum InferFilterNode {
  Infer(CheckedInfer)
  Unary(@relation.CheckedOperation)
  Join(@join.CheckedJoin)
  Refined(RefinedFilter)
  Other(@decode.Cursor, @row.Schema?)
}

///|
pub(all) struct FilterProofLimits {
  max_work : Int
  max_nodes : Int
  max_depth : Int
  max_text_bytes : Int
}

///|
pub(all) enum FilterProofIssueKind {
  InvalidProofLimits
  ProofBudgetExceeded
  ForeignProofSource
  ForeignProofInput
}

///|
pub struct FilterProofIssue {
  source : @decode.Cursor
  kind : FilterProofIssueKind
}

///|
priv suberror FilterProofStop {
  FilterProofStop(FilterProofIssue)
}

///|
priv struct FilterProofBudget {
  limits : FilterProofLimits
  mut work : Int
  mut nodes : Int
  mut text : Int
}

///|
fn[T] filter_proof_fail(
  source : @decode.Cursor,
  kind : FilterProofIssueKind,
) -> T raise FilterProofStop {
  raise FilterProofStop({ source, kind, })
}

///|
fn filter_proof_spend(
  b : FilterProofBudget,
  source : @decode.Cursor,
  amount : Int,
) -> Unit raise FilterProofStop {
  if amount < 0 || amount > b.work {
    filter_proof_fail(source, ProofBudgetExceeded)
  }
  b.work -= amount
}

///|
fn filter_proof_charge(
  b : FilterProofBudget,
  source : @decode.Cursor,
  value : String,
) -> Unit raise FilterProofStop {
  match @scalar.admit_utf8_length(value, b.text) {
    Ok(bytes) => b.text -= bytes
    Err(_) => filter_proof_fail(source, ProofBudgetExceeded)
  }
}

///|
priv enum FilterProofTarget {
  External
  Step(Int)
}

///|
priv struct FilterProofStep {
  operation : InferFilterNode
  input : FilterProofTarget?
  right : FilterProofTarget
  output : @row.Schema?
}

///|
// The constructor verifies exact source-owner and input-schema correspondence.
// An equal-shaped operation, foreign producer or self-join side is not a proof.
struct RefinedFilter {
  original : @relation.CheckedOperation
  output : @row.Schema
  lineage : Array[FilterProofStep]
}

///|
pub struct FilterProofResult {
  proof : RefinedFilter
  work : Int
  nodes : Int
  text_bytes : Int
}

///|
pub fn refined_filter_original(
  value : RefinedFilter,
) -> @relation.CheckedOperation {
  value.original
}

///|
pub fn refined_filter_output(value : RefinedFilter) -> @row.Schema {
  value.output
}

///|
// Outcome/value dependence belongs to a checked Infer producer, not to field
// spellings or a structural Object contract. Follow only exact copy projections.
// Join occurrence/side is part of the proof: two rows of the same Infer producer
// are not interchangeable merely because their static producer is identical.
fn infer_success_expression_path(
  b : FilterProofBudget,
  source : @decode.Cursor,
  expression : @typing.TypedExpression,
  start : Int,
  suffix : Array[String],
) -> (String, Array[String])? raise FilterProofStop {
  let mut index = start
  let mut path = suffix.copy()
  filter_proof_spend(b, source, path.length())
  while true {
    filter_proof_spend(b, source, 1)
    if path.length() > b.limits.max_depth {
      filter_proof_fail(source, ProofBudgetExceeded)
    }
    match @typing.node_form(expression, index) {
      Some(Expression("field", body)) => {
        let field = @decode.text(body).unwrap()
        filter_proof_charge(b, source, field)
        return Some((field, path))
      }
      Some(Expression("property", body)) => {
        let object = @decode.open_object(body).unwrap()
        let name = @decode.text(@decode.lookup(object, "name").unwrap()).unwrap()
        filter_proof_charge(b, source, name)
        filter_proof_spend(b, source, path.length())
        path = [name] + path
        index = @typing.child_at(expression, index, 0).unwrap()
      }
      Some(Expression("object", body)) if !path.is_empty() => {
        let names = @decode.object_field_names(body).unwrap()
        filter_proof_spend(b, source, names.length())
        let mut selected : Int? = None
        for i in 0..<names.length() {
          filter_proof_charge(b, source, names[i])
          if names[i] == path[0] {
            selected = Some(i)
          }
        }
        guard selected is Some(child) else { return None }
        index = @typing.child_at(expression, index, child).unwrap()
        let rest : Array[String] = []
        filter_proof_spend(b, source, path.length())
        for i in 1..<path.length() {
          rest.push(path[i])
        }
        path = rest
      }
      _ => return None
    }
  }
  None
}

///|
fn infer_success_origin(
  b : FilterProofBudget,
  source : @decode.Cursor,
  steps : Array[FilterProofStep],
  target : FilterProofTarget,
  reference : String,
  suffix : Array[String],
) -> (Int, String, Array[String], Array[(Int, @row.Side)])? raise FilterProofStop {
  let mut target = target
  let mut reference = reference
  let mut path = suffix
  let occurrences : Array[(Int, @row.Side)] = []
  while target is Step(index) {
    filter_proof_spend(b, source, 1)
    let step = steps[index]
    guard step.input is Some(input) else { return None }
    match step.operation {
      Infer(_) => {
        if reference == "outcome" && path.is_empty() {
          return Some((index, "outcome", [], occurrences))
        }
        if reference == "value" {
          return Some((index, "value", path, occurrences))
        }
        return None
      }
      Unary(operation) => {
        match @relation.operation(operation) {
          Select | Rename | Drop => {
            let count = @relation.projection_field_count(operation)
            filter_proof_spend(b, source, count)
            let mut selected : String? = None
            for i in 0..<count {
              let field = @relation.projection_field_at(operation, i).unwrap()
              let output = @row.reference_name(field.output)
              filter_proof_charge(b, source, output)
              if output == reference {
                selected = Some(@row.reference_name(field.input))
              }
            }
            guard selected is Some(field) else { return None }
            reference = field
          }
          Derive => {
            // Sequential prior-slot resolution needs its own correspondence;
            // never reinterpret a prior slot as the input with the same name.
            guard @relation.form(operation) is DeriveMap else { return None }
            let count = @relation.binding_count(operation)
            filter_proof_spend(b, source, count)
            let mut selected : @relation.Binding? = None
            for i in 0..<count {
              let binding = @relation.binding_at(operation, i).unwrap()
              if binding.name == Some(reference) {
                selected = Some(binding)
              }
            }
            if selected is Some(binding) {
              filter_proof_spend(b, source, binding.references.length())
              for entry in binding.references {
                guard entry.target is InputField(_) else { return None }
              }
              guard infer_success_expression_path(
                  b,
                  source,
                  binding.expression,
                  0,
                  path,
                )
                is Some((field, next)) else {
                return None
              }
              reference = field
              path = next
            }
          }
          Filter | Sort | Take | Distinct | DedupeRows | AssertRows => ()
          _ => return None
        }
        target = input
      }
      Join(checked) => {
        let right = step.right
        let mut field : @row.FieldName? = None
        if @join.projection_count(checked) is Some(count) {
          filter_proof_spend(b, source, count)
          for i in 0..<count {
            let entry = @join.projection_at(checked, i).unwrap()
            let output = @row.reference_name(entry.output)
            filter_proof_charge(b, source, output)
            if output == reference {
              field = Some(entry.input)
            }
          }
        } else {
          field = @row.lookup_reference(@join.output_schema(checked), reference).map(f => {
              f.name
            },
          )
        }
        match field {
          Some(Qualified(Left, name)) => {
            occurrences.push((index, Left))
            target = input
            reference = name
          }
          Some(Qualified(Right, name)) => {
            occurrences.push((index, Right))
            target = right
            reference = name
          }
          _ => return None
        }
      }
      _ => return None
    }
    // Checked graph inputs precede their consumer; retain a local termination
    // assertion without trusting arbitrary supplied alias/target coordinates.
    if target is Step(previous) && previous >= index {
      return None
    }
  }
  None
}

///|
fn infer_success_contract(
  b : FilterProofBudget,
  source : @decode.Cursor,
  steps : Array[FilterProofStep],
  producer : Int,
  path : Array[String],
) -> @contract.Contract? raise FilterProofStop {
  guard steps[producer].operation is Infer(checked) else { return None }
  let mut value = @model_environment.model_task_output(
    infer_model_task(checked),
  )
  let mut nullable = value.nullable
  for name in path {
    filter_proof_spend(b, source, 1)
    guard value.shape is @contract.Object(fields) else { return None }
    let count = @contract.field_count(fields)
    filter_proof_spend(b, source, count)
    let mut next : @contract.Contract? = None
    for i in 0..<count {
      let field = @contract.field_at(fields, i).unwrap()
      filter_proof_charge(b, source, field.name)
      if field.name == name {
        next = Some(field.contract)
      }
    }
    guard next is Some(contract) else { return None }
    value = contract
    nullable = nullable || value.nullable
  }
  Some(@contract.with_nullability(value, nullable))
}

///|
fn infer_success_nonnull_path(
  b : FilterProofBudget,
  source : @decode.Cursor,
  original : @contract.Contract,
  path : Array[String],
) -> @contract.Contract raise FilterProofStop {
  let parents : Array[(@contract.Fields, String)] = []
  let mut value = original
  for name in path {
    guard value.shape is @contract.Object(fields) else { return original }
    let count = @contract.field_count(fields)
    filter_proof_spend(b, source, count)
    let mut next : @contract.Contract? = None
    for i in 0..<count {
      let field = @contract.field_at(fields, i).unwrap()
      filter_proof_charge(b, source, field.name)
      if field.name == name {
        next = Some(field.contract)
      }
    }
    guard next is Some(contract) else { return original }
    parents.push((fields, name))
    value = contract
  }
  if b.nodes == 0 {
    filter_proof_fail(source, ProofBudgetExceeded)
  }
  b.nodes -= 1
  let mut result = @contract.with_nullability(value, false)
  while parents.pop() is Some((fields, name)) {
    let count = @contract.field_count(fields)
    filter_proof_spend(b, source, count)
    let entries : Array[(String, @contract.Contract)] = []
    for i in 0..<count {
      let field = @contract.field_at(fields, i).unwrap()
      filter_proof_charge(b, source, field.name)
      entries.push(
        (field.name, if field.name == name { result } else { field.contract }),
      )
    }
    if b.nodes == 0 {
      filter_proof_fail(source, ProofBudgetExceeded)
    }
    b.nodes -= 1
    result = @contract.object_contract(
      entries,
      nullable=false,
      max_fields=count,
      max_name_bytes=@contract.field_name_bytes(fields),
    ).unwrap()
  }
  result
}

///|
// This post-filter Carrier proof is additional to the local Filter's structural
// typing. It never changes the predicate, permission, ModelTask or row values.
fn infer_success_filter_schema(
  b : FilterProofBudget,
  source : @decode.Cursor,
  input : FilterProofTarget,
  steps : Array[FilterProofStep],
  checked : @relation.CheckedOperation,
) -> @row.Schema raise FilterProofStop {
  let output = @relation.output_schema(checked)
  let expression = @relation.binding_expression_at(checked, 0).unwrap()
  let pending = [0]
  let successes : Array[(Int, Array[(Int, @row.Side)])] = []
  while pending.pop() is Some(index) {
    filter_proof_spend(b, source, 1)
    match @typing.node_form(expression, index) {
      Some(Expression("and", _)) => {
        let count = @typing.child_count(expression, index).unwrap()
        filter_proof_spend(b, source, count)
        for i in 0..<count {
          pending.push(@typing.child_at(expression, index, i).unwrap())
        }
      }
      Some(Expression("eq", _)) =>
        for direction in [0, 1] {
          let literal = @typing.child_at(expression, index, direction).unwrap()
          let other = @typing.child_at(expression, index, 1 - direction).unwrap()
          if @typing.node_form(expression, literal)
            is Some(Expression("literal", body)) &&
            @decode.text(body) == Ok("ok") {
            if infer_success_expression_path(b, source, expression, other, [])
              is Some((field, path)) {
              if infer_success_origin(b, source, steps, input, field, path)
                is Some((producer, "outcome", _, occurrences)) {
                successes.push((producer, occurrences))
              }
            }
          }
        }
      // OR, NOT, CASE and nonliteral/equivalent strings establish no proof.
      _ => ()
    }
  }
  if successes.is_empty() {
    return output
  }
  let fields : Array[(@row.FieldName, @contract.Contract, @row.Presence)] = []
  let count = @row.field_count(output)
  filter_proof_spend(b, source, count)
  let bytes = b.text
  for i in 0..<count {
    let field = @row.field_at(output, i).unwrap()
    let name = @row.reference_name(field.name)
    filter_proof_charge(b, source, name)
    let mut contract = field.contract
    let nodes = [(field.contract, [])]
    while nodes.pop() is Some((current, path)) {
      filter_proof_spend(b, source, 1)
      if path.length() > b.limits.max_depth {
        filter_proof_fail(source, ProofBudgetExceeded)
      }
      if current.nullable {
        if infer_success_origin(b, source, steps, input, name, path)
          is Some((producer, "value", original_path, occurrences)) {
          filter_proof_spend(b, source, successes.length())
          if successes.contains((producer, occurrences)) {
            if infer_success_contract(b, source, steps, producer, original_path)
              is Some(original) &&
              !original.nullable {
              contract = infer_success_nonnull_path(b, source, contract, path)
            }
          }
        }
      }
      if current.shape is @contract.Object(members) {
        let size = @contract.field_count(members)
        filter_proof_spend(b, source, size)
        for j in 0..<size {
          let child = @contract.field_at(members, j).unwrap()
          filter_proof_charge(b, source, child.name)
          filter_proof_spend(b, source, path.length())
          nodes.push((child.contract, path + [child.name]))
        }
      }
    }
    fields.push((field.name, contract, field.presence))
  }
  @row.from_presence_fields(fields, max_fields=count, max_name_bytes=bytes).unwrap()
}

///|
fn filter_proof_same_input(
  b : FilterProofBudget,
  source : @decode.Cursor,
  target : FilterProofTarget,
  steps : Array[FilterProofStep],
  actual : @row.Schema,
) -> Unit raise FilterProofStop {
  filter_proof_spend(b, source, 1)
  if target is Step(index) {
    guard steps[index].output is Some(expected) &&
      physical_equal(expected, actual) else {
      filter_proof_fail(source, ForeignProofInput)
    }
  }
}

///|
fn filter_proof_named_target(
  b : FilterProofBudget,
  source : @decode.Cursor,
  names : Map[String, Int],
) -> FilterProofTarget raise FilterProofStop {
  let name = @decode.text(source).unwrap_or("")
  filter_proof_charge(b, source, name)
  match names.get(name) {
    Some(index) => Step(index)
    None => External
  }
}

///|
// Validate the complete nominal source correspondence, rather than accepting
// caller-provided graph edges or producer indices. Private checked inputs must
// be the very same immutable schemas as the preceding owned outputs.
pub fn refine_infer_filter(
  source : @decode.Cursor,
  nodes : Array[InferFilterNode],
  original : @relation.CheckedOperation,
  limits : FilterProofLimits,
) -> Result[FilterProofResult, FilterProofIssue] {
  try {
    if limits.max_work < 0 ||
      limits.max_nodes < 0 ||
      limits.max_depth < 0 ||
      limits.max_text_bytes < 0 {
      filter_proof_fail(source, InvalidProofLimits)
    }
    let b : FilterProofBudget = {
      limits,
      work: limits.max_work,
      nodes: limits.max_nodes,
      text: limits.max_text_bytes,
    }
    guard @relation.operation(original) is Filter else {
      filter_proof_fail(source, ForeignProofSource)
    }
    guard @decode.array_length(source) is Some(length) &&
      nodes.length() < length else {
      filter_proof_fail(source, ForeignProofSource)
    }
    filter_proof_spend(b, source, nodes.length())
    let steps : Array[FilterProofStep] = []
    let names : Map[String, Int] = Map([])
    let mut current = External
    for i in 0..<=nodes.length() {
      filter_proof_spend(b, source, 1)
      let body = @decode.element_at(source, i).unwrap()
      guard @decode.open_object(body) is Ok(object) else {
        filter_proof_fail(body, ForeignProofSource)
      }
      let input = match @decode.lookup(object, "from") {
        Some(at) => filter_proof_named_target(b, at, names)
        None => current
      }
      if i == nodes.length() {
        guard @decode.lookup(object, "filter") is Some(at) &&
          @decode.tree_index(source, at) ==
          @decode.tree_index(source, @relation.source(original)) &&
          @decode.tree_index(source, at) is Some(_) else {
          filter_proof_fail(body, ForeignProofSource)
        }
        filter_proof_same_input(
          b,
          body,
          input,
          steps,
          @relation.input_schema(original),
        )
        let output = infer_success_filter_schema(
          b,
          @relation.source(original),
          input,
          steps,
          original,
        )
        return Ok({
          proof: { original, output, lineage: steps, },
          work: limits.max_work - b.work,
          nodes: limits.max_nodes - b.nodes,
          text_bytes: limits.max_text_bytes - b.text,
        })
      }
      let node = nodes[i]
      let mut right = External
      let (operation, at, output) = match node {
        Infer(checked) => {
          guard @decode.lookup(object, "infer") is Some(at) &&
            @decode.tree_index(source, at) ==
            @decode.tree_index(source, infer_source(checked)) &&
            @decode.tree_index(source, at) is Some(_) else {
            filter_proof_fail(body, ForeignProofSource)
          }
          filter_proof_same_input(
            b,
            body,
            input,
            steps,
            infer_input_schema(checked),
          )
          (node, at, Some(infer_output_schema(checked)))
        }
        Unary(checked) | Refined({ original: checked, .. }) => {
          let key = match @relation.operation(checked) {
            Filter => "filter"
            Derive => "derive"
            Select => "select"
            Rename => "rename"
            Drop => "drop"
            Sort => "sort"
            Take => "take"
            Distinct => "distinct"
            DedupeRows => "dedupe_rows"
            AssertRows => "assert_rows"
            _ => filter_proof_fail(body, ForeignProofSource)
          }
          guard @decode.lookup(object, key) is Some(at) &&
            @decode.tree_index(source, at) ==
            @decode.tree_index(source, @relation.source(checked)) &&
            @decode.tree_index(source, at) is Some(_) else {
            filter_proof_fail(body, ForeignProofSource)
          }
          filter_proof_same_input(
            b,
            body,
            input,
            steps,
            @relation.input_schema(checked),
          )
          let output = match node {
            Refined(proof) => proof.output
            _ => @relation.output_schema(checked)
          }
          (Unary(checked), at, Some(output))
        }
        Join(checked) => {
          guard @decode.lookup(object, "join") is Some(at) &&
            @decode.tree_index(source, at) ==
            @decode.tree_index(source, @join.source(checked)) &&
            @decode.tree_index(source, at) is Some(_) else {
            filter_proof_fail(body, ForeignProofSource)
          }
          let join = @decode.open_object(at).unwrap()
          guard @decode.lookup(join, "with") is Some(right_source) else {
            filter_proof_fail(body, ForeignProofSource)
          }
          right = filter_proof_named_target(b, right_source, names)
          filter_proof_same_input(
            b,
            body,
            input,
            steps,
            @join.input_schema(checked, Left),
          )
          filter_proof_same_input(
            b,
            body,
            right,
            steps,
            @join.input_schema(checked, Right),
          )
          (node, at, Some(@join.output_schema(checked)))
        }
        Other(at, schema) => {
          guard @decode.tree_index(source, at) ==
            @decode.tree_index(source, body) &&
            @decode.tree_index(source, at) is Some(_) else {
            filter_proof_fail(body, ForeignProofSource)
          }
          (node, at, schema)
        }
      }
      if b.nodes == 0 {
        filter_proof_fail(at, ProofBudgetExceeded)
      }
      b.nodes -= 1
      steps.push({ operation, input: Some(input), right, output, })
      current = Step(i)
      if @decode.lookup(object, "as") is Some(binding_source) {
        let name = @decode.text(binding_source).unwrap_or("")
        filter_proof_charge(b, binding_source, name)
        names[name] = i
      }
    }
    filter_proof_fail(source, ForeignProofSource)
  } catch {
    FilterProofStop(issue) => Err(issue)
  }
}

///|
// No caller supplies a replacement schema. It is derived only by the owned
// conditional proof; original key lineage and pending obligations are retained.
pub fn refined_filter_keys(
  previous : KeySet?,
  proof : RefinedFilter,
  limits : TransferLimits,
) -> Result[KeySetTransfer, Issue] {
  match advance_keys(previous, proof.original, limits) {
    Err(issue) => Err(issue)
    Ok(transfer) => {
      let count = transfer.keys.witnesses.length()
      if count > limits.max_work - transfer.work {
        return Err({
          kind: LimitExceeded,
          path: @decode.cursor_path(@relation.source(proof.original)),
          span: @decode.cursor_span(@relation.source(proof.original)),
        })
      }
      let records = @carrier.typed_rows(proof.output)
      let witnesses = transfer.keys.witnesses.map(key => { ..key, records, })
      Ok({
        keys: { ..transfer.keys, records, witnesses, },
        work: transfer.work + count,
        name_bytes: transfer.name_bytes,
      })
    }
  }
}

///|
pub fn refined_filter_literals(
  previous : LiteralDomains?,
  proof : RefinedFilter,
  limits : TransferLimits,
) -> Result[LiteralTransfer, Issue] {
  transfer_literal_domains(previous, proof.original, limits).map(transfer => {
    ..transfer,
    domains: { ..transfer.domains, schema: proof.output, },
  })
}

///|
pub fn refined_filter_lineage_count(value : RefinedFilter) -> Int {
  value.lineage.length()
}

///|
pub fn refined_filter_ranking(
  previous : RankingInput,
  proof : RefinedFilter,
  limits : @checking.Limits,
) -> Result[RankingTransfer, @checking.Issue] {
  transfer_ranking_unary(previous, proof.original, limits).map(transfer => {
    ..transfer,
    input: {
      ..transfer.input,
      carrier: @carrier.relation(@carrier.typed_rows(proof.output)),
    },
  })
}
