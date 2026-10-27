///|
/// A composite Command input and its original typed children. The enclosing
/// captured owner must bind the reader to the exact Result row and retain it.
/// This pure DATA projection supplies no target, key, custody or authority.
struct EffectCommandCheckedInput {
  binding : EffectCommandInputBinding
  source_row_index : Int
  fields : Array[(String, @value.CheckedValue)]
  checked : @value.CheckedValue
}

///|
pub(all) enum EffectCommandCheckedInputIssue {
  InvalidLimits
  FieldLimit
  WorkLimit
  MissingSourceField(String)
  ForeignSourceContract(String)
  InvalidReadUsage
  InvalidInputContract
  ValueLimit
} derive(Eq, Debug)

///|
/// Materialize only the authored, present inputs of the original binding.
/// Result readers return their actual field Contract and bounded usage; literals
/// retain their original CheckedValue. Optional absence never becomes NULL.
/// Limits bound work and DATA construction, not an independent funded parent.
pub fn project_effect_command_checked_input(
  binding : EffectCommandInputBinding,
  source_row_index : Int,
  read : (String, Int, @value.Limits) -> (@value.CheckedValue, Int, Int, Int)?,
  max_fields : Int,
  max_work : Int,
  values : @value.Limits,
) -> Result[EffectCommandCheckedInput, EffectCommandCheckedInputIssue] {
  if source_row_index < 0 ||
    max_fields < 0 ||
    max_work < 0 ||
    values.max_nodes < 1 ||
    values.max_depth < 1 ||
    values.max_text_bytes < 0 {
    return Err(InvalidLimits)
  }
  let count = effect_command_input_field_count(binding)
  if count > max_fields {
    return Err(FieldLimit)
  }
  // Account for both field-vector walks before allocating either vector.
  if count > max_work / 2 {
    return Err(WorkLimit)
  }
  let mut work = max_work - count * 2
  let mut text = values.max_text_bytes
  let mut longest_name = 1
  for index in 0..<count {
    let field = effect_command_input_field_at(binding, index).unwrap()
    let name = effect_command_input_field_name(field)
    if name.length() > work {
      return Err(WorkLimit)
    }
    work -= name.length()
    let size = match @scalar.admit_utf8_length(name, text) {
      Ok(size) => size
      Err(_) => return Err(ValueLimit)
    }
    if size > work {
      return Err(WorkLimit)
    }
    work -= size
    text -= size
    longest_name = Int::max(longest_name, name.length())
  }
  // Both the contract constructor and the detached child vector sort names.
  // Checked division keeps all products finite before either sort runs.
  if count > 0 && count > work / count {
    return Err(WorkLimit)
  }
  let comparisons = count * count
  if comparisons > 0 && longest_name > work / comparisons / 2 {
    return Err(WorkLimit)
  }
  work -= comparisons * longest_name * 2
  let name_bytes = values.max_text_bytes - text
  let mut nodes = values.max_nodes - 1
  let fields : Array[(String, @value.CheckedValue)] = []
  let contracts : Array[(String, @contract.Contract)] = []
  for index in 0..<count {
    let field = effect_command_input_field_at(binding, index).unwrap()
    let name = effect_command_input_field_name(field)
    let remaining : @value.Limits = {
      max_nodes: nodes,
      max_depth: values.max_depth - 1,
      max_text_bytes: text,
    }
    let checked = match effect_command_input_field_value(field) {
      ResultField(source) => {
        let reference = @schema.field_reference_name(source)
        if reference.length() > work {
          return Err(WorkLimit)
        }
        work -= reference.length()
        guard read(reference, work, remaining)
          is Some((original, used_work, used_nodes, used_text)) else {
          return Err(MissingSourceField(reference))
        }
        if used_work < 0 ||
          used_work > work ||
          used_nodes < 1 ||
          used_nodes > nodes ||
          used_text < 0 ||
          used_text > text ||
          used_nodes > used_work ||
          used_text > used_work - used_nodes {
          return Err(InvalidReadUsage)
        }
        if !physical_equal(original.contract, @schema.field_contract(source)) {
          return Err(ForeignSourceContract(reference))
        }
        work -= used_work
        nodes -= used_nodes
        text -= used_text
        original
      }
      Literal(original) => {
        // Bound the complete traversal before entering the existing rechecker.
        if nodes > work || text > work - nodes {
          return Err(WorkLimit)
        }
        guard @value.recheck_runtime_value_usage(
            original.value,
            original.contract,
            remaining,
          )
          is Some((_, used_nodes, used_text)) else {
          return Err(ValueLimit)
        }
        work -= used_nodes + used_text
        nodes -= used_nodes
        text -= used_text
        original
      }
    }
    fields.push((name, checked))
    contracts.push((name, effect_command_input_field_contract(field)))
  }
  let total_nodes = values.max_nodes - nodes
  let total_text = values.max_text_bytes - text
  // The final recheck validates the complete composite against the exact
  // selected input field types, including narrower Result-to-input bindings.
  // Its traversal is additional work; it is not a second value allowance.
  if total_nodes > work || total_text > work - total_nodes {
    return Err(WorkLimit)
  }
  let contract = match
    @contract.object_contract(
      contracts,
      nullable=false,
      max_fields=count,
      max_name_bytes=name_bytes,
    ) {
    Ok(contract) => contract
    Err(_) => return Err(InvalidInputContract)
  }
  fields.sort_by((left, right) => @canonical.compare_utf16(left.0, right.0))
  guard @value.prepare_contract_object_value(contract) is Some(builder) else {
    return Err(InvalidInputContract)
  }
  for index in 0..<fields.length() {
    if !@value.append_contract_object_field(
        builder,
        index,
        fields[index].1.value,
      ) {
      let _ = @value.cancel_object_value(builder)
      return Err(InvalidInputContract)
    }
  }
  guard @value.finish_object_value(builder) is Some(value) else {
    return Err(InvalidInputContract)
  }
  guard @value.recheck_runtime_value_usage(value, contract, values)
    is Some((checked, checked_nodes, checked_text)) else {
    return Err(ValueLimit)
  }
  if checked_nodes != total_nodes || checked_text != total_text {
    return Err(InvalidReadUsage)
  }
  Ok({ binding, source_row_index, fields, checked, })
}

///|
pub fn effect_command_checked_input_value(
  input : EffectCommandCheckedInput,
) -> @value.CheckedValue {
  input.checked
}

///|
pub fn effect_command_checked_input_binding(
  input : EffectCommandCheckedInput,
) -> EffectCommandInputBinding {
  input.binding
}

///|
pub fn effect_command_checked_input_row_index(
  input : EffectCommandCheckedInput,
) -> Int {
  input.source_row_index
}

///|
pub fn effect_command_checked_input_field_count(
  input : EffectCommandCheckedInput,
) -> Int {
  input.fields.length()
}

///|
pub fn effect_command_checked_input_field_at(
  input : EffectCommandCheckedInput,
  index : Int,
) -> (String, @value.CheckedValue)? {
  input.fields.get(index)
}
