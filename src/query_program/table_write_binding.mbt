///|
/// A fixed write action published by the installed Connector. This is not a
/// Catalog lookup, a Source alias or permission to stage/apply a write.
pub(all) enum TableWriteAction {
  Create
  Replace(String, String)
} derive(Eq, Debug)

///|
/// Host-owned publication for one logical Table name. Mapping, Capability and
/// installation references retain their existing owners and are rechecked by
/// the installed Table Effect before approval and apply.
pub(all) struct TableWriteBinding {
  name : Array[@query.NamePart]
  target_ref : String
  mapping_ref : String
  mapping_cid : String
  capability_cid : String
  installation_binding_cid : String
  action : TableWriteAction
}

///|
pub(all) enum TableWriteBindingIssue {
  InvalidBinding
  UnknownTable
  AmbiguousTable
  ActionMismatch
  WorkLimit
} derive(Eq, Debug)

///|
fn table_write_cid(value : String) -> Bool {
  if value.length() != 71 || !value.has_prefix("sha256:") {
    return false
  }
  for index in 7..<value.length() {
    let c = value[index]
    if !((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) {
      return false
    }
  }
  true
}

///|
fn table_write_uuid(value : String) -> Bool {
  if value.length() != 36 {
    return false
  }
  for index in 0..<value.length() {
    let c = value[index]
    if [8, 13, 18, 23].contains(index) {
      if c != '-' {
        return false
      }
    } else if !((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) {
      return false
    }
  }
  true
}

///|
/// Resolve against the complete fixed publication, never against observed rows
/// or a read alias. Even OR REPLACE cannot refresh a generation or switch an
/// already selected create into replacement after a commit conflict.
pub fn resolve_table_write_binding(
  bindings : Array[TableWriteBinding],
  name : Array[@query.NamePart],
  allow_replace : Bool,
  max_work : Int,
) -> Result[TableWriteBinding, TableWriteBindingIssue] {
  if name.is_empty() ||
    name.length() > 32 ||
    name.any(part => part.value.is_empty() || part.value.length() > 1024) ||
    bindings.length() > 1024 ||
    max_work < 1 {
    return Err(InvalidBinding)
  }
  let mut remaining = max_work
  let matches : Array[TableWriteBinding] = []
  for binding in bindings {
    let cost = binding.name.length() + 1
    if cost > remaining {
      return Err(WorkLimit)
    }
    remaining -= cost
    if binding.name.is_empty() ||
      binding.name.length() > 32 ||
      binding.name.any(part => {
        part.value.is_empty() || part.value.length() > 1024
      }) ||
      !binding.target_ref.has_prefix("connector://") ||
      binding.target_ref.length() <= 12 ||
      binding.target_ref.length() > 4096 ||
      binding.mapping_ref.length() > 1024 ||
      !@contract_ref.valid_mapping_ref(binding.mapping_ref) ||
      !table_write_cid(binding.mapping_cid) ||
      !table_write_cid(binding.capability_cid) ||
      !table_write_cid(binding.installation_binding_cid) {
      return Err(InvalidBinding)
    }
    match binding.action {
      Create => ()
      Replace(uuid, generation) =>
        if !table_write_uuid(uuid) || !table_write_cid(generation) {
          return Err(InvalidBinding)
        }
    }
    if same_relation_path(binding.name, name) {
      matches.push(binding)
    }
  }
  if matches.is_empty() {
    return Err(UnknownTable)
  }
  if matches.length() != 1 {
    return Err(AmbiguousTable)
  }
  let selected = matches[0]
  if !allow_replace && selected.action is Replace(_, _) {
    return Err(ActionMismatch)
  }
  Ok(selected)
}
