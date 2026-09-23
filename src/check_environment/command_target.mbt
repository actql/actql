///|
pub(all) enum CommandTargetIssue {
  InvalidLimit
  WorkLimit
  MissingCommand(String)
  InvalidCommand(String)
} derive(Eq, Debug)

///|
pub struct CommandTarget {
  catalog : Catalog
  item : Member
  command_id : String
  resource_kind : String
  work : Int
}

///|
pub fn command_target_catalog(value : CommandTarget) -> Catalog {
  value.catalog
}

///|
pub fn command_target_member(value : CommandTarget) -> Member {
  value.item
}

///|
pub fn command_target_id(value : CommandTarget) -> String {
  value.command_id
}

///|
pub fn command_target_resource_kind(value : CommandTarget) -> String {
  value.resource_kind
}

///|
pub fn command_target_work(value : CommandTarget) -> Int {
  value.work
}

///|
/// Select the exact Command Contract inside an identity-checked Catalog.
/// This admits only the target ResourceRef kind. Input, permission, recovery,
/// current authority, and execution admission remain separate obligations.
pub fn select_command_target(
  contents : CatalogContents,
  reference : String,
  max_work : Int,
) -> Result[CommandTarget, CommandTargetIssue] {
  if max_work < 0 {
    return Err(InvalidLimit)
  }
  let mut remaining = max_work
  for catalog in contents.entries {
    if remaining == 0 {
      return Err(WorkLimit)
    }
    remaining -= 1
    for item in catalog.commands {
      if remaining == 0 {
        return Err(WorkLimit)
      }
      remaining -= 1
      let root = member_body(item)
      let object = @decode.open_object(root).unwrap()
      let command = match @decode.lookup(object, "command_id") {
        Some(value) =>
          match @decode.text(value) {
            Ok(value) => value
            Err(_) => return Err(InvalidCommand(reference))
          }
        None => return Err(InvalidCommand(reference))
      }
      if command != reference {
        continue
      }
      let target = match @decode.lookup(object, "target") {
        Some(value) => value
        None => return Err(InvalidCommand(reference))
      }
      let target = match
        @decode.closed_object(target, [
          "resource_kind", "cardinality", "max_items",
        ]) {
        Ok(value) => value
        Err(_) => return Err(InvalidCommand(reference))
      }
      let kind = match @decode.lookup(target, "resource_kind") {
        Some(value) =>
          match @decode.text(value) {
            Ok(value) if !value.is_empty() => value
            _ => return Err(InvalidCommand(reference))
          }
        None => return Err(InvalidCommand(reference))
      }
      let cardinality = match @decode.lookup(target, "cardinality") {
        Some(value) =>
          match @decode.text(value) {
            Ok(value) => value
            Err(_) => return Err(InvalidCommand(reference))
          }
        None => return Err(InvalidCommand(reference))
      }
      if cardinality != "single" && cardinality != "bounded_many" {
        return Err(InvalidCommand(reference))
      }
      if @decode.lookup(target, "max_items") is Some(value) {
        match @decode.safe_integer(value) {
          Ok(n) if n > 0L => ()
          _ => return Err(InvalidCommand(reference))
        }
      }
      return Ok({
        catalog,
        item,
        command_id: command,
        resource_kind: kind,
        work: max_work - remaining,
      })
    }
  }
  Err(MissingCommand(reference))
}
