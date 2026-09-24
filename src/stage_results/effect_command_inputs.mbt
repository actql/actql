///|
pub(all) struct EffectCommandInputLimits {
  max_work : Int
  max_nodes : Int
  max_depth : Int
  max_text_bytes : Int
} derive(Eq, Debug)

///|
pub(all) enum EffectCommandInputIssueKind {
  InvalidLimits
  WorkLimit
  InvalidContract
  MissingField(String)
  UnknownField(String)
  IncompatibleField(String)
  IncompatibleLiteral(String)
} derive(Eq, Debug)

///|
pub struct EffectCommandInputIssue {
  kind : EffectCommandInputIssueKind
  stage_index : Int
  effect_id : String
}

///|
pub fn effect_command_input_issue_kind(
  issue : EffectCommandInputIssue,
) -> EffectCommandInputIssueKind {
  issue.kind
}

///|
pub fn effect_command_input_issue_stage(issue : EffectCommandInputIssue) -> Int {
  issue.stage_index
}

///|
pub fn effect_command_input_issue_effect(
  issue : EffectCommandInputIssue,
) -> String {
  issue.effect_id
}

///|
pub(all) enum EffectCommandInputValue {
  ResultField(@schema.Field)
  Literal(@value.CheckedValue)
}

///|
pub struct EffectCommandInputField {
  name : String
  contract : @contract.Contract
  value : EffectCommandInputValue
}

///|
pub fn effect_command_input_field_name(
  value : EffectCommandInputField,
) -> String {
  value.name
}

///|
pub fn effect_command_input_field_contract(
  value : EffectCommandInputField,
) -> @contract.Contract {
  value.contract
}

///|
pub fn effect_command_input_field_value(
  value : EffectCommandInputField,
) -> EffectCommandInputValue {
  value.value
}

///|
pub struct EffectCommandInputBinding {
  target : EffectCommandTargetBinding
  fields : Array[EffectCommandInputField]
}

///|
pub fn effect_command_input_target(
  value : EffectCommandInputBinding,
) -> EffectCommandTargetBinding {
  value.target
}

///|
pub fn effect_command_input_field_count(
  value : EffectCommandInputBinding,
) -> Int {
  value.fields.length()
}

///|
pub fn effect_command_input_field_at(
  value : EffectCommandInputBinding,
  index : Int,
) -> EffectCommandInputField? {
  value.fields.get(index)
}

///|
pub struct EffectCommandInputs {
  targets : EffectCommandTargets
  entries : Array[EffectCommandInputBinding]
  work : Int
  nodes : Int
  text_bytes : Int
}

///|
pub fn effect_command_inputs_targets(
  value : EffectCommandInputs,
) -> EffectCommandTargets {
  value.targets
}

///|
pub fn effect_command_input_count(value : EffectCommandInputs) -> Int {
  value.entries.length()
}

///|
pub fn effect_command_input_at(
  value : EffectCommandInputs,
  index : Int,
) -> EffectCommandInputBinding? {
  value.entries.get(index)
}

///|
pub fn effect_command_inputs_usage(
  value : EffectCommandInputs,
) -> (Int, Int, Int) {
  (value.work, value.nodes, value.text_bytes)
}

///|
fn command_input_issue(
  kind : EffectCommandInputIssueKind,
  header : @syntax.EffectHeader,
) -> EffectCommandInputIssue {
  {
    kind,
    stage_index: @syntax.effect_header_stage(header),
    effect_id: @syntax.effect_header_id(header),
  }
}

///|
fn command_input_charge(
  remaining : Ref[Int],
  amount : Int,
  header : @syntax.EffectHeader,
) -> Result[Unit, EffectCommandInputIssue] {
  if amount > remaining.val {
    Err(command_input_issue(WorkLimit, header))
  } else {
    remaining.val -= amount
    Ok(())
  }
}

///|
/// Admit the closed inline input contract for each selected Command and
/// retain its exact typed Result fields or literals. Catalog role-reference
/// closure, permissions, recovery and current authority remain separate.
pub fn bind_effect_command_inputs(
  targets : EffectCommandTargets,
  limits : EffectCommandInputLimits,
) -> Result[EffectCommandInputs, EffectCommandInputIssue] {
  if limits.max_work < 0 ||
    limits.max_nodes < 0 ||
    limits.max_depth < 0 ||
    limits.max_text_bytes < 0 {
    return Err({ kind: InvalidLimits, stage_index: -1, effect_id: "", })
  }
  let work = Ref(limits.max_work)
  let nodes = Ref(limits.max_nodes)
  let text = Ref(limits.max_text_bytes)
  let entries : Array[EffectCommandInputBinding] = []
  for index in 0..<effect_command_target_count(targets) {
    let target = effect_command_target_at(targets, index).unwrap()
    let effect = effect_command_target_effect(target)
    let header = effect_result_binding_header(effect)
    match command_input_charge(work, 1, header) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    let contract_body = @environment.member_body(
      @environment.command_target_member(effect_command_target_contract(target)),
    )
    let contract_root = @decode.open_object(contract_body).unwrap()
    let input_contract = match @decode.lookup(contract_root, "input_contract") {
      Some(value) => value
      None => return Err(command_input_issue(InvalidContract, header))
    }
    let input_shape = match
      @decode.closed_object(input_contract, ["additional_properties", "fields"]) {
      Ok(value) => value
      Err(_) => return Err(command_input_issue(InvalidContract, header))
    }
    guard @decode.lookup(input_shape, "additional_properties") is Some(closed) &&
      @decode.boolean(closed) == Ok(false) &&
      @decode.lookup(input_shape, "fields") is Some(contract_fields) &&
      @decode.object_length(contract_fields) is Some(expected_count) else {
      return Err(command_input_issue(InvalidContract, header))
    }
    let effect_body = @decode.open_object(@syntax.effect_header_body(header)).unwrap()
    let authored = @decode.lookup(effect_body, "input").unwrap()
    let authored_count = @decode.object_length(authored).unwrap()
    if expected_count > work.val || authored_count > work.val - expected_count {
      return Err(command_input_issue(WorkLimit, header))
    }
    work.val -= expected_count + authored_count
    let supplied : Map[String, @decode.Cursor] = Map([])
    for at in 0..<authored_count {
      let (name, value) = @decode.field_at(authored, at).unwrap()
      supplied[name] = value
    }
    let result_fields : Map[String, @schema.Field] = Map([])
    let bound_count = effect_result_field_binding_count(effect)
    match command_input_charge(work, bound_count, header) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    for at in 0..<bound_count {
      let binding = effect_result_field_binding_at(effect, at).unwrap()
      if effect_result_field_binding_role(binding) is EffectValue(name) {
        result_fields[name] = effect_result_field_binding_field(binding)
      }
    }
    let fields : Array[EffectCommandInputField] = []
    let expected_names : Map[String, Bool] = Map([])
    for at in 0..<expected_count {
      let (name, body) = @decode.field_at(contract_fields, at).unwrap()
      expected_names[name] = true
      let supplied_value = match supplied.get(name) {
        Some(value) => value
        None => return Err(command_input_issue(MissingField(name), header))
      }
      let (contract, used_nodes, used_text) = match
        @contract.read_checked_usage(body, {
          max_nodes: Int::min(nodes.val, work.val),
          max_depth: limits.max_depth,
          max_text_bytes: text.val,
        }) {
        Ok(value) => value
        Err(@contract.ContractIssue(@contract.BudgetExceeded, ..)) =>
          return Err(command_input_issue(WorkLimit, header))
        Err(_) => return Err(command_input_issue(InvalidContract, header))
      }
      work.val -= used_nodes
      nodes.val -= used_nodes
      text.val -= used_text
      let wrapper = @decode.open_object(supplied_value).unwrap()
      let value = if @decode.lookup(wrapper, "field") is Some(_) {
        let source = match result_fields.get(name) {
          Some(value) => value
          None => return Err(command_input_issue(MissingField(name), header))
        }
        let (compatible, used) = @contract.assignable_usage(
          @schema.field_contract(source),
          contract,
          work.val,
        ) catch {
          _ => return Err(command_input_issue(WorkLimit, header))
        }
        work.val -= used
        if !compatible {
          return Err(command_input_issue(IncompatibleField(name), header))
        }
        ResultField(source)
      } else {
        let literal = @decode.lookup(wrapper, "literal").unwrap()
        let (checked, used_nodes, used_text) = match
          @value.admit_usage(contract, literal, {
            max_nodes: Int::min(nodes.val, work.val),
            max_depth: limits.max_depth,
            max_text_bytes: text.val,
          }) {
          Ok(value) => value
          Err(@value.ValueIssue(@value.BudgetExceeded, ..)) =>
            return Err(command_input_issue(WorkLimit, header))
          Err(_) =>
            return Err(command_input_issue(IncompatibleLiteral(name), header))
        }
        work.val -= used_nodes
        nodes.val -= used_nodes
        text.val -= used_text
        Literal(checked)
      }
      fields.push({ name, contract, value, })
    }
    for at in 0..<authored_count {
      let (name, _) = @decode.field_at(authored, at).unwrap()
      if !expected_names.contains(name) {
        return Err(command_input_issue(UnknownField(name), header))
      }
    }
    entries.push({ target, fields, })
  }
  Ok({
    targets,
    entries,
    work: limits.max_work - work.val,
    nodes: limits.max_nodes - nodes.val,
    text_bytes: limits.max_text_bytes - text.val,
  })
}
