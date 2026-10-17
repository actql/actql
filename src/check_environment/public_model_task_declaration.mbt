///|
/// Original public Task syntax and checked field contracts. This is not an
/// installed model, checked Environment, handling policy or execution grant.
/// Keep the original decoded document through later provider/Run admission.
struct PublicModelTaskDeclaration {
  original : @decode.Cursor
  task : String
  model : (String, String)?
  instructions : String
  input : PublicModelTaskContract
  output : PublicModelTaskContract
  max_items : Int64?
  max_output_tokens : Int64?
  work : Int
  contract_nodes : Int
  contract_text : Int
}

///|
fn public_task_declaration_contract(
  root : @decode.Cursor,
  budget : ModelTaskBudget,
) -> PublicModelTaskContract raise ModelTaskStop {
  let limits : ModelTaskLimits = {
    bodies: budget.limits.bodies,
    contracts: {
      max_nodes: budget.limits.contracts.max_nodes - budget.contract_nodes,
      max_depth: budget.limits.contracts.max_depth,
      max_text_bytes: budget.limits.contracts.max_text_bytes -
      budget.contract_text,
    },
    max_work: budget.limits.max_work - budget.work,
  }
  let value = match read_public_model_task_contract(root, limits) {
    Ok(value) => value
    Err(issue) => raise ModelTaskStop(issue)
  }
  let (work, nodes, text) = public_model_task_contract_usage(value)
  model_task_charge(budget, work, root)
  budget.contract_nodes += nodes
  budget.contract_text += text
  value
}

///|
/// The caller supplies the original bounded, strict decoded JSON/YAML Cursor.
/// Intake/decoding and filesystem lifetime remain the source/Host Owners'
/// responsibility. All declaration fields, both contracts and their aggregate
/// work/node/text budgets are checked here, before any installed selection.
pub fn read_public_model_task_declaration(
  root : @decode.Cursor,
  limits : ModelTaskLimits,
) -> Result[PublicModelTaskDeclaration, ModelTaskIssue] {
  if limits.max_work < 0 ||
    limits.bodies.max_bytes < 0 ||
    limits.bodies.max_nodes < 0 ||
    limits.bodies.max_depth < 0 ||
    limits.bodies.max_members < 0 ||
    limits.contracts.max_nodes < 0 ||
    limits.contracts.max_depth < 0 ||
    limits.contracts.max_text_bytes < 0 {
    return Err({ kind: InvalidLimits, source: Some(root), })
  }
  let usage = @decode.admission_usage(root)
  if usage.nodes > limits.bodies.max_nodes ||
    usage.depth > limits.bodies.max_depth ||
    usage.total_string_bytes > limits.bodies.max_bytes {
    return Err({ kind: BodyLimit, source: Some(root), })
  }
  let budget : ModelTaskBudget = {
    limits,
    work: 0,
    contract_nodes: 0,
    contract_text: 0,
  }
  try {
    let object = model_task_object(
      root,
      ["task", "model", "input", "instructions", "output", "limits"],
      budget,
    )
    let task = model_task_string(object, "task", root, budget)
    if !task.has_prefix("model-task:") {
      model_task_fail(InvalidBody, root)
    }
    let model = match @decode.field(object, "model") {
      Missing => None
      ExplicitNull => model_task_fail(InvalidBody, root)
      Present(value) => {
        let pair = model_task_object(value, ["provider", "name"], budget)
        Some(
          (
            model_task_string(pair, "provider", value, budget),
            model_task_string(pair, "name", value, budget),
          ),
        )
      }
    }
    let instructions_source = model_task_required(object, "instructions", root)
    let instructions = match @decode.text(instructions_source) {
      Ok(value) => value
      Err(_) => model_task_fail(InvalidBody, instructions_source)
    }
    // Empty instructions are explicit text, not a missing/default prompt.
    model_task_charge(budget, instructions.length(), instructions_source)
    let input = public_task_declaration_contract(
      model_task_required(object, "input", root),
      budget,
    )
    let output = public_task_declaration_contract(
      model_task_required(object, "output", root),
      budget,
    )
    let mut max_items = None
    let mut max_output_tokens = None
    match @decode.field(object, "limits") {
      Missing => ()
      ExplicitNull => model_task_fail(InvalidBody, root)
      Present(value) => {
        let bounds = model_task_object(
          value,
          ["max_items", "max_output_tokens"],
          budget,
        )
        for field in ["max_items", "max_output_tokens"] {
          let amount = match @decode.field(bounds, field) {
            Missing => None
            ExplicitNull => model_task_fail(InvalidBody, value)
            Present(amount) => Some(model_task_integer(amount, true, budget))
          }
          if field == "max_items" {
            max_items = amount
          } else {
            max_output_tokens = amount
          }
        }
      }
    }
    Ok({
      original: root,
      task,
      model,
      instructions,
      input,
      output,
      max_items,
      max_output_tokens,
      work: budget.work,
      contract_nodes: budget.contract_nodes,
      contract_text: budget.contract_text,
    })
  } catch {
    ModelTaskStop(issue) => Err(issue)
  }
}

///|
pub fn public_model_task_declaration_original(
  value : PublicModelTaskDeclaration,
) -> @decode.Cursor {
  value.original
}

///|
/// The public identifier is also its exact internal version. This mapping
/// applies only to this public form; legacy explicit Task versions are intact.
pub fn public_model_task_declaration_identity(
  value : PublicModelTaskDeclaration,
) -> (String, String) {
  (value.task, value.task)
}

///|
pub fn public_model_task_declaration_model(
  value : PublicModelTaskDeclaration,
) -> (String, String)? {
  value.model
}

///|
pub fn public_model_task_declaration_instructions(
  value : PublicModelTaskDeclaration,
) -> String {
  value.instructions
}

///|
pub fn public_model_task_declaration_contracts(
  value : PublicModelTaskDeclaration,
) -> (PublicModelTaskContract, PublicModelTaskContract) {
  (value.input, value.output)
}

///|
pub fn public_model_task_declaration_limits(
  value : PublicModelTaskDeclaration,
) -> (Int64?, Int64?) {
  (value.max_items, value.max_output_tokens)
}

///|
pub fn public_model_task_declaration_usage(
  value : PublicModelTaskDeclaration,
) -> (Int, Int, Int) {
  (value.work, value.contract_nodes, value.contract_text)
}
