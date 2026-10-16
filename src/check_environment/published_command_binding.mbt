///|
/// An explicit interpretation mode, never a target value or authority.
pub(all) enum PublishedCommandBindingMode {
  Installation
  Identifier
} derive(Eq, Debug)

///|
pub(all) enum PublishedCommandBindingIssue {
  InvalidLimit
  WorkLimit
  MissingBinding
  InvalidBinding
  InvalidIdentifierType(@value_contract.AdmissionError)
  UnsupportedIdentifierDomain
  Command(CommandTargetIssue)
} derive(Eq, Debug)

///|
/// Retains the exact original Command/Catalog/environment and checked domain.
/// No installation, ResourceRef, current grant or execution permission is issued.
pub struct PublishedCommandBinding {
  target : CommandTarget
  identifier : @value_contract.Contract?
  work : Int
  nodes : Int
  text : Int
}

///|
pub fn published_command_binding_target(
  value : PublishedCommandBinding,
) -> CommandTarget {
  value.target
}

///|
pub fn published_command_binding_mode(
  value : PublishedCommandBinding,
) -> PublishedCommandBindingMode {
  match value.identifier {
    None => Installation
    Some(_) => Identifier
  }
}

///|
pub fn published_command_binding_identifier_type(
  value : PublishedCommandBinding,
) -> @value_contract.Contract? {
  value.identifier
}

///|
pub fn published_command_binding_work(value : PublishedCommandBinding) -> Int {
  value.work
}

///|
/// Counts use the existing checked-type account, not JSON byte or heap size.
pub fn published_command_binding_usage(
  value : PublishedCommandBinding,
) -> (Int, Int) {
  (value.nodes, value.text)
}

///|
/// Select the original declared mode. Absence is legacy field-target meaning,
/// not a default fixed-installation mode. Plain values still need their actual
/// installed issuer/current binding before capture or execution.
pub fn select_published_command_binding(
  contents : CatalogContents,
  reference : String,
  limits : @value_contract.Limits,
  max_work : Int,
) -> Result[PublishedCommandBinding, PublishedCommandBindingIssue] {
  if max_work < 0 ||
    limits.max_nodes < 0 ||
    limits.max_depth < 0 ||
    limits.max_text_bytes < 0 {
    return Err(InvalidLimit)
  }
  let (target, declaration) = match
    select_command_target_parts(contents, reference, max_work, true) {
    Ok(value) => value
    Err(CommandTargetIssue::WorkLimit) => return Err(WorkLimit)
    Err(issue) => return Err(Command(issue))
  }
  guard declaration is Some(source) else { return Err(MissingBinding) }
  admit_published_command_binding(target, source, limits, max_work)
}

///|
// Both selection entrances use this same original declaration reader. A
// malformed explicit binding cannot become a legacy ResourceRef target.
fn admit_published_command_binding(
  target : CommandTarget,
  source : @decode.Cursor,
  limits : @value_contract.Limits,
  max_work : Int,
) -> Result[PublishedCommandBinding, PublishedCommandBindingIssue] {
  let remaining = max_work - command_target_work(target)
  if remaining < 2 {
    return Err(WorkLimit)
  }
  let object = match
    @decode.closed_object(source, ["kind", "identity_contract"]) {
    Ok(value) => value
    Err(_) => return Err(InvalidBinding)
  }
  let kind = match @decode.lookup(object, "kind") {
    Some(value) =>
      match @decode.text(value) {
        Ok(value) => value
        Err(_) => return Err(InvalidBinding)
      }
    None => return Err(InvalidBinding)
  }
  let mode : PublishedCommandBindingMode = match kind {
    "installation" => Installation
    "identifier" => Identifier
    _ => return Err(InvalidBinding)
  }
  if limits.max_nodes < 2 || limits.max_depth < 1 {
    return Err(WorkLimit)
  }
  let mut nodes = 2
  let mut text = match @scalar.admit_utf8_length(kind, limits.max_text_bytes) {
    Ok(value) => value
    Err(_) => return Err(WorkLimit)
  }
  if text > remaining - nodes {
    return Err(WorkLimit)
  }
  let type_work = remaining - nodes - text
  let identifier = match mode {
    Installation => {
      if @decode.lookup(object, "identity_contract") is Some(_) {
        return Err(InvalidBinding)
      }
      None
    }
    Identifier => {
      guard @decode.lookup(object, "identity_contract") is Some(body) else {
        return Err(InvalidBinding)
      }
      let (contract, child_nodes, child_text) = match
        @value_contract.read_checked_usage(body, {
          max_nodes: Int::min(limits.max_nodes - nodes, type_work),
          max_depth: limits.max_depth - 1,
          max_text_bytes: Int::min(limits.max_text_bytes - text, type_work),
        }) {
        Ok(value) => value
        Err(@value_contract.ContractIssue(@value_contract.BudgetExceeded, ..)) =>
          return Err(WorkLimit)
        Err(issue) => return Err(InvalidIdentifierType(issue))
      }
      nodes += child_nodes
      text += child_text
      if contract.nullable ||
        !@value_contract.key_comparable(contract, contract) {
        return Err(UnsupportedIdentifierDomain)
      }
      Some(contract)
    }
  }
  if nodes > remaining || text > remaining - nodes {
    return Err(WorkLimit)
  }
  Ok({
    target,
    identifier,
    work: max_work - remaining + nodes + text,
    nodes,
    text,
  })
}

///|
/// One original Command selection, retaining legacy ResourceRef meaning when
/// no binding is declared. This is not a target value, issuer or grant.
struct CommandTargetSelection {
  target : CommandTarget
  published : PublishedCommandBinding?
}

///|
pub fn command_target_selection_target(
  value : CommandTargetSelection,
) -> CommandTarget {
  value.target
}

///|
pub fn command_target_selection_published(
  value : CommandTargetSelection,
) -> PublishedCommandBinding? {
  value.published
}

///|
pub fn command_target_selection_work(value : CommandTargetSelection) -> Int {
  value.published
  .map(published_command_binding_work)
  .unwrap_or(command_target_work(value.target))
}

///|
pub fn command_target_selection_usage(
  value : CommandTargetSelection,
) -> (Int, Int) {
  value.published.map(published_command_binding_usage).unwrap_or((0, 0))
}

///|
/// Walk the Catalog once, then admit its exact declared mode. None is solely
/// the existing ResourceRef-field mode, never a default installation target.
pub fn select_command_target_binding(
  contents : CatalogContents,
  reference : String,
  limits : @value_contract.Limits,
  max_work : Int,
) -> Result[CommandTargetSelection, PublishedCommandBindingIssue] {
  if max_work < 0 ||
    limits.max_nodes < 0 ||
    limits.max_depth < 0 ||
    limits.max_text_bytes < 0 {
    return Err(InvalidLimit)
  }
  let (target, declaration) = match
    select_command_target_parts(contents, reference, max_work, true) {
    Ok(value) => value
    Err(CommandTargetIssue::WorkLimit) => return Err(WorkLimit)
    Err(issue) => return Err(Command(issue))
  }
  let published = match declaration {
    None => None
    Some(source) =>
      match admit_published_command_binding(target, source, limits, max_work) {
        Ok(value) => Some(value)
        Err(issue) => return Err(issue)
      }
  }
  Ok({ target, published, })
}
