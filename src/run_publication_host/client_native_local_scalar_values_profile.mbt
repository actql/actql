///|
/// Read-only reachability evidence over the original checked preparation.
/// This is not contract compatibility, authorization or a runnable replacement
/// for that preparation. Retained original contracts remain separate inputs.
pub struct ClientNativeLocalScalarValuesProfile {
  preparation : PreparedClientProgram
  operations : Array[String]
  expressions : Array[String]
  inspected : Int
}

///|
pub(all) enum ClientNativeLocalScalarValuesProfileIssue {
  InvalidLimit
  UnsupportedProfile
  NonScalar
  UnprovenExpression
  BudgetExceeded
  ForeignPreparation
} derive(Eq, Debug)

///|
priv struct ScalarValuesInspection {
  mut remaining : Int
  expressions : Array[String]
}

///|
fn scalar_values_spend(
  budget : ScalarValuesInspection,
) -> Result[Unit, ClientNativeLocalScalarValuesProfileIssue] {
  if budget.remaining <= 0 {
    return Err(BudgetExceeded)
  }
  budget.remaining -= 1
  Ok(())
}

///|
// Closed scalar alternatives from the existing Value contract Owner. Json,
// containers and both reference families deliberately remain outside this
// compatibility profile even when a later projection removes their columns.
fn scalar_values_contract(contract : @contract.Contract) -> Bool {
  match contract.shape {
    @contract.Text(_)
    | @contract.Number
    | @contract.Boolean
    | @contract.Timestamp
    | @contract.Date
    | @contract.Decimal(..) => true
    _ => false
  }
}

///|
fn scalar_values_schema(
  schema : @schema.Schema,
  budget : ScalarValuesInspection,
) -> Result[Unit, ClientNativeLocalScalarValuesProfileIssue] {
  for i in 0..<@schema.field_count(schema) {
    match scalar_values_spend(budget) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    let field = @schema.field_at(schema, i).unwrap()
    if !scalar_values_contract(@schema.field_contract(field)) {
      return Err(NonScalar)
    }
  }
  Ok(())
}

///|
fn scalar_values_expression(
  expression : @expression.TypedExpression,
  budget : ScalarValuesInspection,
) -> Result[Unit, ClientNativeLocalScalarValuesProfileIssue] {
  if @expression.pending_validation_count(expression) != 0 ||
    !@expression.required_profiles(expression).is_empty() {
    return Err(UnprovenExpression)
  }
  for i in 0..<@expression.node_count(expression) {
    match scalar_values_spend(budget) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    let node = @expression.node_at(expression, i).unwrap()
    if !scalar_values_contract(node.contract) {
      return Err(NonScalar)
    }
    let tag = match @expression.node_form(expression, i) {
      Some(@expression.Expression(tag, _)) => tag
      Some(@expression.ImplicitNull) => "#implicit_null"
      _ => return Err(UnprovenExpression)
    }
    match tag {
      "literal"
      | "field"
      | "$param"
      | "add"
      | "sub"
      | "mul"
      | "div"
      | "neg"
      | "eq"
      | "neq"
      | "lt"
      | "lte"
      | "gt"
      | "gte"
      | "and"
      | "or"
      | "not"
      | "is_null"
      | "coalesce"
      | "case"
      | "if"
      | "#implicit_null" => ()
      _ => return Err(UnprovenExpression)
    }
    budget.expressions.push(tag)
  }
  Ok(())
}

///|
fn scalar_values_parameters(
  parameters : @parameter.BoundValues?,
  budget : ScalarValuesInspection,
) -> Result[Unit, ClientNativeLocalScalarValuesProfileIssue] {
  match parameters {
    Some(parameters) => {
      let declarations = @parameter.bound_declarations(parameters)
      for i in 0..<@parameter.declaration_count(declarations) {
        match scalar_values_spend(budget) {
          Err(issue) => return Err(issue)
          Ok(_) => ()
        }
        let declaration = @parameter.declaration_at(declarations, i).unwrap()
        if !scalar_values_contract(declaration.parameter_type.contract) {
          return Err(NonScalar)
        }
      }
      for i in 0..<@parameter.bound_value_count(parameters) {
        match scalar_values_spend(budget) {
          Err(issue) => return Err(issue)
          Ok(_) => ()
        }
        let parameter = @parameter.bound_value_at(parameters, i).unwrap()
        if !scalar_values_contract(parameter.value.contract) {
          return Err(NonScalar)
        }
      }
    }
    None => ()
  }
  Ok(())
}

///|
/// Classify a finite source-free Values pipeline using the existing checked
/// step schemas and every intermediate typed expression annotation. No source
/// text is reparsed and no schema is inferred from the final Named Result.
pub fn inspect_client_native_local_scalar_values_profile(
  prepared : PreparedClientProgram,
  max_work : Int,
) -> Result[
  ClientNativeLocalScalarValuesProfile,
  ClientNativeLocalScalarValuesProfileIssue,
] {
  if max_work <= 0 {
    return Err(InvalidLimit)
  }
  let graph = prepared_client_graph(prepared)
  if prepared_client_acquisition_count(prepared) != 0 ||
    prepared_client_uses_graph_carrier(prepared) ||
    @strategy.graph_program_has_effects(graph) ||
    !@strategy.graph_source_free_inputs_complete(graph) ||
    @strategy.graph_task_count(graph) != 1 ||
    prepared_client_infer_execution_occurrence(prepared, 0) is Some(_) {
    return Err(UnsupportedProfile)
  }
  guard @strategy.graph_task_owner(graph, 0) is Some(owner) else {
    return Err(UnsupportedProfile)
  }
  let preparation = @lower.bound_preparation(owner)
  let pipeline = @lower.pipeline(preparation)
  if @pipeline.input_count(pipeline) != 0 || @pipeline.step_count(pipeline) == 0 {
    return Err(UnsupportedProfile)
  }
  let budget : ScalarValuesInspection = {
    remaining: max_work,
    expressions: [],
  }
  match scalar_values_parameters(@lower.parameter_bindings(owner), budget) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  // Inspect every original lowered node, including dropped columns and Values
  // schemas with zero rows. Bound cells come from the same original Owner.
  for i in 0..<@lower.node_count(preparation) {
    match scalar_values_spend(budget) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    let node = @lower.node_at(preparation, i).unwrap()
    guard @lower.node_relation_schema(node) is Some(schema) else {
      return Err(UnsupportedProfile)
    }
    match scalar_values_schema(schema, budget) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    if @lower.node_values_row_count(node) is Some(rows) {
      for row in 0..<rows {
        for column in 0..<@schema.field_count(schema) {
          match scalar_values_spend(budget) {
            Err(issue) => return Err(issue)
            Ok(_) => ()
          }
          let cell = match @lower.bound_values_cell(owner, i, row, column) {
            Ok(value) => value
            Err(_) => return Err(UnsupportedProfile)
          }
          if !scalar_values_contract(cell.contract) {
            return Err(NonScalar)
          }
        }
      }
    }
  }
  let sequence = match
    @lower.prepare_sequence(owner, client_standard_values_sequence_limits()) {
    Ok(value) => value
    Err(_) => return Err(UnsupportedProfile)
  }
  let operations : Array[String] = []
  for i in 0..<@lower.sequence_count(sequence) {
    match scalar_values_spend(budget) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    let name = match @lower.sequence_step(sequence, i) {
      Some(@lower.ValuesStep(_)) => "REL.values"
      Some(@lower.RowStep(kernel)) =>
        match @relation.operation(@lower.kernel_checked(kernel)) {
          @relation.Derive => "REL.derive"
          @relation.Filter => "REL.filter"
          @relation.Select => "REL.select"
          @relation.Rename => "REL.rename"
          @relation.Drop => "REL.drop"
          _ => return Err(UnsupportedProfile)
        }
      _ => return Err(UnsupportedProfile)
    }
    operations.push(name)
  }
  // The existing complete root index includes ordinary arithmetic as well as
  // obligation sites. Never substitute only demand/obligation projections.
  let roots = match
    @lower.prepare_roots(sequence, {
      max_roots: max_work,
      max_pointer_bytes: max_work,
      max_work,
    }) {
    Ok(value) => value
    Err(_) => return Err(UnprovenExpression)
  }
  for i in 0..<@lower.root_count(roots) {
    let root = @lower.root_at(roots, i).unwrap()
    match scalar_values_expression(root.typed_expression, budget) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  Ok({
    preparation: prepared,
    operations,
    expressions: budget.expressions,
    inspected: max_work - budget.remaining,
  })
}

///|
/// The original opaque preparation is part of the evidence, not a copied CID.
pub fn validate_client_native_local_scalar_values_preparation(
  profile : ClientNativeLocalScalarValuesProfile,
  prepared : PreparedClientProgram,
) -> Result[Unit, ClientNativeLocalScalarValuesProfileIssue] {
  if physical_equal(profile.preparation, prepared) {
    Ok(())
  } else {
    Err(ForeignPreparation)
  }
}
