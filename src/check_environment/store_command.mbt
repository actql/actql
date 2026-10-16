///|
// This optional relationship is part of the original Mapping's self-CID.
// Absence leaves the existing relation-store meaning unchanged.
struct StoreCommandReference {
  catalog_cid : String
  command_ref : String
  command_contract_cid : String
}

///|
fn read_mapping_store_command(
  mapping : @decode.ObjectView,
  index : Int,
) -> StoreCommandReference? raise MappingShapeStop {
  guard @decode.lookup(mapping, "store_command") is Some(value) else {
    return None
  }
  let object = match
    @decode.closed_object(value, [
      "catalog_cid", "command_ref", "command_contract_cid",
    ]) {
    Ok(value) => value
    Err(_) => raise MappingShapeStop(InvalidMapping(index))
  }
  let command_ref = mapping_shape_text(object, "command_ref", index)
  if !@contract_ref.valid_command_ref(command_ref) {
    raise MappingShapeStop(InvalidMapping(index))
  }
  Some({
    catalog_cid: mapping_shape_cid_text(object, "catalog_cid", index),
    command_ref,
    command_contract_cid: mapping_shape_cid_text(
      object, "command_contract_cid", index,
    ),
  })
}

///|
pub(all) enum StoreCommandIssue {
  InvalidLimit
  MissingRelationship
  ForeignEnvironment
  ForeignCatalog
  ForeignCommand
  UnsupportedMapping
  Mapping(MappingPermissionIssue)
  Command(CommandTargetIssue)
  WorkLimit
} derive(Eq, Debug)

///|
// A checked join of existing originals, not a Capability, ResourceRef issuer
// or execution permit. Installation and current authorization are separate.
pub struct StoreCommandBinding {
  mapping : MappingContractShape
  command : CommandTarget
  mapping_operation : String
  work : Int
}

///|
pub fn store_command_mapping(
  binding : StoreCommandBinding,
) -> MappingContractShape {
  binding.mapping
}

///|
pub fn store_command_target(binding : StoreCommandBinding) -> CommandTarget {
  binding.command
}

///|
// The original collection-only Mapping remains create/none. Selecting its
// Command does not admit canonical relation-store or invent a row identity.
pub fn store_command_mapping_operation(
  binding : StoreCommandBinding,
) -> (String, String) {
  (binding.mapping_operation, "none")
}

///|
pub fn store_command_work(binding : StoreCommandBinding) -> Int {
  binding.work
}

///|
// Resolve only the exact relationship published in the original Mapping.
// Neither compatible schemas, names nor current grants select a Command.
pub fn bind_store_command(
  mapping : MappingContractShape,
  catalogs : CatalogContents,
  max_work : Int,
) -> Result[StoreCommandBinding, StoreCommandIssue] {
  if max_work < 0 {
    return Err(InvalidLimit)
  }
  guard mapping.store_command is Some(reference) else {
    return Err(MissingRelationship)
  }
  if !physical_equal(
      member_environment(mapping.item),
      contract_registry_environment(catalog_registry(catalogs)),
    ) {
    return Err(ForeignEnvironment)
  }
  let mapping_operation = match mapping_shape_primary_identity(mapping) {
    None => "create"
    Some(_) => "store"
  }
  let (supported, work) = match
    mapping_supports_operation(mapping, mapping_operation, "none", max_work) {
    Ok(value) => value
    Err(MappingPermissionIssue::WorkLimit) => return Err(WorkLimit)
    Err(issue) => return Err(Mapping(issue))
  }
  if !supported {
    return Err(UnsupportedMapping)
  }
  let command = match
    select_command_target(catalogs, reference.command_ref, max_work - work) {
    Ok(value) => value
    Err(CommandTargetIssue::WorkLimit) => return Err(WorkLimit)
    Err(issue) => return Err(Command(issue))
  }
  let (_, _, connector, revision) = connector_manifest_entry_identity(
    mapping.connector,
  )
  if catalog_identity(command_target_catalog(command)) !=
    (connector, revision, reference.catalog_cid) {
    return Err(ForeignCatalog)
  }
  if command_target_cid(command) != reference.command_contract_cid {
    return Err(ForeignCommand)
  }
  Ok({ mapping, command, mapping_operation, work: work + command_target_work(command), })
}
