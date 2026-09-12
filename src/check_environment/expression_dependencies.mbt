///|
/// Declared body-reference graph. Selected operation/profile laws are additional
/// Program roots, not inferred from this graph or from arbitrary schema strings.
pub(all) enum ExpressionContractBody {
  ExpressionRoot
  RegexRepresentation
  RegexRepresentationSchema
  ConsumerCapacity
  Inherited(InheritedTextTimeContract)
} derive(Eq, Debug)

///|
pub struct ExpressionContractDependency {
  pointer : String
  target : ExpressionContractBody
}

///|
/// Unknown means unsupported interpretation, not an empty dependency set.
pub fn expression_contract_body(cid : String) -> ExpressionContractBody? {
  if cid == expression_dependency_root_cid() {
    Some(ExpressionRoot)
  } else if cid == expression_dependency_regex_contract_cid() {
    Some(RegexRepresentation)
  } else if cid == expression_dependency_regex_schema_cid() {
    Some(RegexRepresentationSchema)
  } else if cid == expression_dependency_consumer_capacity_cid() {
    Some(ConsumerCapacity)
  } else {
    inherited_text_time_contract(cid).map(body => Inherited(body))
  }
}

///|
pub fn expression_contract_body_cid(v : ExpressionContractBody) -> String {
  match v {
    ExpressionRoot => expression_dependency_root_cid()
    RegexRepresentation => expression_dependency_regex_contract_cid()
    RegexRepresentationSchema => expression_dependency_regex_schema_cid()
    ConsumerCapacity => expression_dependency_consumer_capacity_cid()
    Inherited(body) => inherited_text_time_cid(body)
  }
}

///|
pub fn expression_contract_dependency_count(v : ExpressionContractBody) -> Int {
  match v {
    ExpressionRoot => 3
    RegexRepresentation => 1
    RegexRepresentationSchema | ConsumerCapacity => 0
    Inherited(body) => inherited_text_time_dependency_count(body)
  }
}

///|
pub fn expression_contract_dependency_at(
  v : ExpressionContractBody,
  index : Int,
) -> ExpressionContractDependency? {
  match v {
    ExpressionRoot =>
      match index {
        0 =>
          Some({
            pointer: "/inherited_text_time_profile_cid",
            target: Inherited(Base),
          })
        1 =>
          Some({
            pointer: "/regex_ast_contract/cid",
            target: RegexRepresentation,
          })
        2 =>
          Some({
            pointer: "/laws/consumer_capacity_contract_cid",
            target: ConsumerCapacity,
          })
        _ => None
      }
    RegexRepresentation =>
      if index == 0 {
        Some({ pointer: "/schema/cid", target: RegexRepresentationSchema, })
      } else {
        None
      }
    RegexRepresentationSchema | ConsumerCapacity => None
    Inherited(body) =>
      inherited_text_time_dependency_at(body, index).map(edge => {
        pointer: edge.pointer,
        target: Inherited(edge.target),
      })
  }
}
