///|
pub(all) enum BodyDependencyIssue {
  ForeignEnvironment
  UnsupportedBodyGrammar(String)
  MissingBodyAdmission
} derive(Eq, Debug)

///|
struct ContractBodyDependencies {
  value : ProtocolValueContract
}

///|
/// Interpret direct contract dependencies only for an admitted body grammar.
/// A checked value-contract body has no external ContractRef positions; it
/// depends on its pinned governing grammar. Other kinds are not empty leaves.
/// This is not a complete Unit closure or admission of the governing grammar's
/// own semantic dependencies, which the enclosing selector must also process.
pub fn check_body_dependencies(
  values : ProtocolValueContracts,
  envelope : ContractEnvelope,
) -> Result[ContractBodyDependencies, BodyDependencyIssue] {
  if !physical_equal(
      member_environment(envelope.item),
      values.policies.references.contents.registry.environment,
    ) {
    return Err(ForeignEnvironment)
  }
  if !protocol_value_kind(envelope.kind) {
    return Err(UnsupportedBodyGrammar(envelope.kind))
  }
  match protocol_value_for(values, envelope) {
    None => Err(MissingBodyAdmission)
    Some(value) => Ok({ value, })
  }
}

///|
pub fn body_dependency_contract(
  v : ContractBodyDependencies,
) -> ContractEnvelope {
  v.value.envelope
}

///|
pub fn body_dependency_value(
  v : ContractBodyDependencies,
) -> ProtocolValueContract {
  v.value
}

///|
/// The governing grammar is the sole direct contract dependency of this body
/// shape. ResourceKind/ArtifactType strings are type data, not ContractRefs.
pub fn body_dependency_count(_v : ContractBodyDependencies) -> Int {
  1
}

///|
pub fn body_dependency_at(
  _v : ContractBodyDependencies,
  index : Int,
) -> String? {
  if index == 0 {
    Some(protocol_value_grammar_cid())
  } else {
    None
  }
}
