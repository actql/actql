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
} derive(Eq, Debug)

///|
struct ProtocolValueContract {
  envelope : ContractEnvelope
  contract : @value_contract.Contract
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
/// Admits all bodies governed by the checked value-contract grammar, including
/// unused ones. Carrier schemas and behavioral contract bodies are separate.
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
  let registry = policies.references.contents.registry
  if registry.entries.length() > limits.max_envelopes {
    return Err(EnvelopeLimit)
  }
  let entries = []
  let by_cid : Map[String, ProtocolValueContract] = Map([])
  let mut nodes = 0
  let mut text = 0
  for i in 0..<registry.entries.length() {
    let envelope = registry.entries[i]
    if !protocol_value_kind(envelope.kind) {
      continue
    }
    let remaining = {
      ..limits.contracts,
      max_nodes: limits.contracts.max_nodes - nodes,
      max_text_bytes: limits.contracts.max_text_bytes - text,
    }
    let (contract, n, t) = match
      @value_contract.read_checked_usage(envelope.body, remaining) {
      Ok(v) => v
      Err(e) => return Err(InvalidContract(i, e))
    }
    nodes += n
    text += t
    let entry = { envelope, contract, }
    entries.push(entry)
    by_cid[envelope.cid] = entry
  }
  Ok({ policies, entries, by_cid, nodes, text, })
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
pub fn protocol_value_type(
  v : ProtocolValueContract,
) -> @value_contract.Contract {
  v.contract
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
