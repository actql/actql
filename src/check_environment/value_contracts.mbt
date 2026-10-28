///|
pub(all) struct ValueContractLimits {
  max_envelopes : Int
  contracts : @value_contract.Limits
}

///|
pub(all) enum ValueContractIssue {
  InvalidLimits
  EnvelopeLimit
  InvalidContract(Int, @value_contract.AdmissionError)
  InvalidCommandInput(Int, CommandInputContractIssue)
} derive(Eq, Debug)

///|
priv enum ProtocolValueBody {
  Value(@value_contract.Contract)
  CommandInput(CommandInputContract)
}

///|
struct ProtocolValueContract {
  envelope : ContractEnvelope
  body : ProtocolValueBody
}

///|
struct ProtocolValueContracts {
  policies : SourceDataPolicies
  entries : Array[ProtocolValueContract]
  by_cid : Map[String, ProtocolValueContract]
  nodes : Int
  text : Int
}

///|
/// Admit every supplied value-role body, including unused ones. Only the
/// explicit command_input presence form uses its additional closed grammar;
/// legacy roles, Carrier schemas and behavioral contracts stay distinct.
pub fn check_protocol_value_contracts(
  policies : SourceDataPolicies,
  limits : ValueContractLimits,
) -> Result[ProtocolValueContracts, ValueContractIssue] {
  if limits.max_envelopes < 0 ||
    limits.contracts.max_nodes < 0 ||
    limits.contracts.max_depth < 0 ||
    limits.contracts.max_text_bytes < 0 {
    return Err(InvalidLimits)
  }
  read_protocol_value_contracts(policies, limits, {
    nodes: 0,
    text: 0,
    entries: 0,
  })
}

///|
priv struct ProtocolValueMeter {
  mut nodes : Int
  mut text : Int
  mut entries : Int
}

///|
/// Actual original node/text/complete-entry charges on typed refusal too.
/// This neither re-admits a Contract nor infers issuer or Host authority.
pub fn observe_protocol_value_contracts(
  policies : SourceDataPolicies,
  limits : ValueContractLimits,
) -> (Result[ProtocolValueContracts, ValueContractIssue], Int, Int, Int) {
  if limits.max_envelopes < 0 ||
    limits.contracts.max_nodes < 0 ||
    limits.contracts.max_depth < 0 ||
    limits.contracts.max_text_bytes < 0 {
    return (Err(InvalidLimits), 0, 0, 0)
  }
  let meter = ProtocolValueMeter::{ nodes: 0, text: 0, entries: 0, }
  let result = read_protocol_value_contracts(policies, limits, meter)
  (result, meter.nodes, meter.text, meter.entries)
}

///|
fn read_protocol_value_contracts(
  policies : SourceDataPolicies,
  limits : ValueContractLimits,
  meter : ProtocolValueMeter,
) -> Result[ProtocolValueContracts, ValueContractIssue] {
  let registry = policies.references.contents.registry
  if registry.entries.length() > limits.max_envelopes {
    return Err(EnvelopeLimit)
  }
  let entries = []
  let by_cid : Map[String, ProtocolValueContract] = Map([])

  for i in 0..<registry.entries.length() {
    let envelope = registry.entries[i]
    if !protocol_value_kind(envelope.kind) {
      continue
    }
    let remaining = {
      ..limits.contracts,
      max_nodes: limits.contracts.max_nodes - meter.nodes,
      max_text_bytes: limits.contracts.max_text_bytes - meter.text,
    }
    let body = if envelope.kind == "command_input" &&
      @decode.open_object(envelope.body) is Ok(object) &&
      @decode.lookup(object, command_input_required_fields_key) is Some(_) {
      let (result, n, t) = observe_command_input_contract(
        envelope.body,
        remaining,
      )
      meter.nodes += n
      meter.text += t
      let admitted = match result {
        Ok(value) => value
        Err(issue) => return Err(InvalidCommandInput(i, issue))
      }
      CommandInput(admitted)
    } else {
      let (result, n, t) = @value_contract.observe_checked_usage(
        envelope.body,
        remaining,
      )
      meter.nodes += n
      meter.text += t
      let contract = match result {
        Ok((value, _, _)) => value
        Err(issue) => return Err(InvalidContract(i, issue))
      }
      Value(contract)
    }
    let entry = { envelope, body, }
    entries.push(entry)
    meter.entries += 1
    by_cid[envelope.cid] = entry
  }
  Ok({ policies, entries, by_cid, nodes: meter.nodes, text: meter.text, })
}

///|
pub fn value_contract_policies(
  v : ProtocolValueContracts,
) -> SourceDataPolicies {
  v.policies
}

///|
pub fn protocol_value_usage(v : ProtocolValueContracts) -> (Int, Int, Int) {
  (v.nodes, v.text, v.entries.length())
}

///|
pub fn protocol_value_at(
  v : ProtocolValueContracts,
  i : Int,
) -> ProtocolValueContract? {
  v.entries.get(i)
}

///|
pub fn protocol_value_envelope(v : ProtocolValueContract) -> ContractEnvelope {
  v.envelope
}

///|
/// None identifies the Command-only presence record, not an unknown JSON type.
pub fn protocol_value_type(
  v : ProtocolValueContract,
) -> @value_contract.Contract? {
  match v.body {
    Value(contract) => Some(contract)
    CommandInput(_) => None
  }
}

///|
/// This role's domain-specific record is not a general Object ValueContract.
pub fn protocol_command_input_type(
  v : ProtocolValueContract,
) -> CommandInputContract? {
  match v.body {
    Value(_) => None
    CommandInput(contract) => Some(contract)
  }
}

///|
/// A same-CID envelope from a different environment is not interchangeable.
/// None also means this role uses a different body grammar, not an unknown type.
pub fn protocol_value_for(
  v : ProtocolValueContracts,
  envelope : ContractEnvelope,
) -> ProtocolValueContract? {
  if !physical_equal(
      member_environment(envelope.item),
      v.policies.references.contents.registry.environment,
    ) {
    return None
  }
  v.by_cid.get(envelope.cid)
}
