///|
/// A Command-only presence declaration, not a nullable/optional Object value
/// contract. The complete original record remains the role/body identity.
pub struct CommandInputContract {
  fields : @value_contract.Fields
  by_name : Map[String, @value_contract.Contract]
  required : Map[String, Bool]
  source : @decode.Cursor
  nodes : Int
  text : Int
}

///|
pub(all) enum CommandInputContractIssue {
  InvalidCommandInputLimits
  CommandInputBudget
  InvalidCommandInputRecord
  InvalidCommandInputField(String)
  InvalidCommandInputType(String, @value_contract.AdmissionError)
  ForeignCommandInputOwner
  CommandInputRoleMismatch
  CommandInputBodyMismatch
} derive(Eq, Debug)

///|
/// Read the additional closed command_input form only. Legacy role bodies
/// still use the existing checked ValueContract reader without conversion.
/// Every declared child is checked even when its authored input is omitted.
pub fn read_command_input_contract(
  source : @decode.Cursor,
  limits : @value_contract.Limits,
) -> Result[CommandInputContract, CommandInputContractIssue] {
  if limits.max_nodes < 0 || limits.max_depth < 0 || limits.max_text_bytes < 0 {
    return Err(InvalidCommandInputLimits)
  }
  read_command_input_contract_owned(source, limits, { nodes: 0, text: 0, })
}

///|
priv struct CommandInputMeter {
  mut nodes : Int
  mut text : Int
}

///|
/// Original presence/child-reader budget cells, including partial refusal.
/// Original input grammar and first child error remain authoritative.
pub fn observe_command_input_contract(
  source : @decode.Cursor,
  limits : @value_contract.Limits,
) -> (Result[CommandInputContract, CommandInputContractIssue], Int, Int) {
  if limits.max_nodes < 0 || limits.max_depth < 0 || limits.max_text_bytes < 0 {
    return (Err(InvalidCommandInputLimits), 0, 0)
  }
  let meter = CommandInputMeter::{ nodes: 0, text: 0, }
  let result = read_command_input_contract_owned(source, limits, meter)
  (result, meter.nodes, meter.text)
}

///|
fn read_command_input_contract_owned(
  source : @decode.Cursor,
  limits : @value_contract.Limits,
  meter : CommandInputMeter,
) -> Result[CommandInputContract, CommandInputContractIssue] {
  let object = match
    @decode.closed_object(source, [
      "additional_properties", command_input_fields_key, command_input_required_fields_key,
    ]) {
    Ok(value) => value
    Err(_) => return Err(InvalidCommandInputRecord)
  }
  guard @decode.lookup(object, "additional_properties") is Some(closed) &&
    @decode.boolean(closed) == Ok(false) &&
    @decode.lookup(object, command_input_fields_key) is Some(fields) &&
    @decode.object_length(fields) is Some(field_count) &&
    @decode.lookup(object, command_input_required_fields_key)
    is Some(required_fields) &&
    @decode.array_length(required_fields) is Some(required_count) else {
    return Err(InvalidCommandInputRecord)
  }
  // Charge the presence record/array and each retained subset entry before
  // allocating their lookup. Checked child types use their existing budgets.
  if limits.max_depth < 1 ||
    limits.max_nodes < 2 ||
    required_count > limits.max_nodes - 2 ||
    field_count > limits.max_nodes - 2 - required_count {
    return Err(CommandInputBudget)
  }
  meter.nodes = 2 + required_count
  let declarations : Array[(String, @value_contract.Contract)] = []
  let declared : Map[String, @value_contract.Contract] = Map([])
  for index in 0..<field_count {
    let (name, body) = @decode.field_at(fields, index).unwrap()
    let name_bytes = match
      @scalar.admit_utf8_length(name, limits.max_text_bytes - meter.text) {
      Ok(value) => value
      Err(_) => return Err(CommandInputBudget)
    }
    meter.text += name_bytes
    let (result, child_nodes, child_text) = @value_contract.observe_checked_usage(
      body,
      {
        max_nodes: limits.max_nodes - meter.nodes,
        max_depth: limits.max_depth - 1,
        max_text_bytes: limits.max_text_bytes - meter.text,
      },
    )
    meter.nodes += child_nodes
    meter.text += child_text
    let contract = match result {
      Ok((value, _, _)) => value
      Err(@value_contract.ContractIssue(@value_contract.BudgetExceeded, ..)) =>
        return Err(CommandInputBudget)
      Err(issue) => return Err(InvalidCommandInputType(name, issue))
    }
    declarations.push((name, contract))
    declared[name] = contract
  }
  // Reuse the existing checked field-name owner. This internal all-field
  // collection is not exposed as the presence record's ValueContract type.
  let declaration = match
    @value_contract.object_contract(
      declarations,
      nullable=false,
      max_fields=field_count,
      max_name_bytes=limits.max_text_bytes,
    ) {
    Ok(value) => value
    Err(@value_contract.InvalidConstructionName(name))
    | Err(@value_contract.NonCanonicalConstructionName(name))
    | Err(@value_contract.DuplicateConstructionName(name)) =>
      return Err(InvalidCommandInputField(name))
    Err(_) => return Err(InvalidCommandInputRecord)
  }
  guard declaration.shape is Object(field_values) else {
    return Err(InvalidCommandInputRecord)
  }
  let required : Map[String, Bool] = Map([])
  for index in 0..<required_count {
    let name = match
      @decode.text(@decode.element_at(required_fields, index).unwrap()) {
      Ok(value) => value
      Err(_) => return Err(InvalidCommandInputRecord)
    }
    if !declared.contains(name) || required.contains(name) {
      return Err(InvalidCommandInputField(name))
    }
    let size = match
      @scalar.admit_utf8_length(name, limits.max_text_bytes - meter.text) {
      Ok(value) => value
      Err(_) => return Err(CommandInputBudget)
    }
    meter.text += size
    required[name] = true
  }
  Ok({
    fields: field_values,
    by_name: declared,
    required,
    source,
    nodes: meter.nodes,
    text: meter.text,
  })
}

///|
pub fn command_input_contract_usage(value : CommandInputContract) -> (Int, Int) {
  (value.nodes, value.text)
}

///|
pub fn command_input_contract_field_count(value : CommandInputContract) -> Int {
  @value_contract.field_count(value.fields)
}

///|
pub fn command_input_contract_field_at(
  value : CommandInputContract,
  index : Int,
) -> @value_contract.Field? {
  @value_contract.field_at(value.fields, index)
}

///|
pub fn command_input_contract_field_required(
  value : CommandInputContract,
  name : String,
) -> Bool {
  value.required.contains(name)
}

///|
pub fn command_input_contract_field_type(
  value : CommandInputContract,
  name : String,
) -> @value_contract.Contract? {
  value.by_name.get(name)
}

///|
/// Compare complete decoded bodies, not bare-body hashes or a subset of the
/// inline declaration. Callers separately establish original role/Catalog/
/// environment membership. Array order remains identity-bearing.
pub fn command_input_contract_matches(
  value : CommandInputContract,
  other : @decode.Cursor,
  max_work : Int,
) -> Result[(Bool, Int), CommandInputContractIssue] {
  if max_work < 0 {
    return Err(InvalidCommandInputLimits)
  }
  if max_work == 0 {
    return Err(CommandInputBudget)
  }
  let mut work = 0
  let pending = [(value.source, other)]
  while pending.pop() is Some((left, right)) {
    if work == max_work {
      return Err(CommandInputBudget)
    }
    work += 1
    if @decode.object_length(left) is Some(count) {
      if @decode.object_length(right) != Some(count) {
        return Ok((false, work))
      }
      if count > max_work - work - pending.length() {
        return Err(CommandInputBudget)
      }
      let object = @decode.open_object(right).unwrap()
      for index in 0..<count {
        let (name, child) = @decode.field_at(left, index).unwrap()
        guard @decode.lookup(object, name) is Some(other_child) else {
          return Ok((false, work))
        }
        pending.push((child, other_child))
      }
    } else if @decode.array_length(left) is Some(count) {
      if @decode.array_length(right) != Some(count) {
        return Ok((false, work))
      }
      if count > max_work - work - pending.length() {
        return Err(CommandInputBudget)
      }
      for index in 0..<count {
        pending.push(
          (
            @decode.element_at(left, index).unwrap(),
            @decode.element_at(right, index).unwrap(),
          ),
        )
      }
    } else {
      let equal = match (@decode.view(left), @decode.view(right)) {
        (NullValue, NullValue) => true
        (BoolValue(a), BoolValue(b)) => a == b
        (NumberValue(a), NumberValue(b)) => a == b
        (TextValue(a), TextValue(b)) => a == b
        _ => false
      }
      if !equal {
        return Ok((false, work))
      }
    }
  }
  Ok((true, work))
}

///|
/// Resolve the exact input_schema occurrence of this original Catalog Command.
/// The checked role body, not a reconstructed hash or a foreign equal member,
/// supplies its complete presence declaration. Returned work includes the
/// checked type admission and bounded complete body comparison. Node/text
/// usage is also reported separately, for its own resource domain.
pub fn command_target_input_contract(
  target : CommandTarget,
  references : CatalogReferences,
  limits : @value_contract.Limits,
  max_work : Int,
) -> Result[(CommandInputContract, Int), CommandInputContractIssue] {
  if max_work < 0 {
    return Err(InvalidCommandInputLimits)
  }
  if !physical_equal(
      member_environment(target.item),
      references.contents.registry.environment,
    ) {
    return Err(ForeignCommandInputOwner)
  }
  let command = @decode.open_object(member_body(target.item)).unwrap()
  guard @decode.lookup(command, "input_schema") is Some(schema) &&
    catalog_reference_for_cursor(references, schema) is Some(reference) &&
    physical_equal(reference.item, target.item) &&
    physical_equal(reference.catalog, target.catalog) &&
    reference.contract.kind == "command_input" else {
    return Err(CommandInputRoleMismatch)
  }
  guard @decode.lookup(command, "input_contract") is Some(inline) else {
    return Err(CommandInputBodyMismatch)
  }
  let admitted = match
    read_command_input_contract(reference.contract.body, {
      ..limits,
      max_nodes: Int::min(limits.max_nodes, max_work),
    }) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if max_work < admitted.nodes {
    return Err(CommandInputBudget)
  }
  let (matches, work) = match
    command_input_contract_matches(admitted, inline, max_work - admitted.nodes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !matches {
    return Err(CommandInputBodyMismatch)
  }
  Ok((admitted, admitted.nodes + work))
}
