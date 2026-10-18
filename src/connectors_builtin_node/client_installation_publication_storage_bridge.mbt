///|
/// Private DATA bridge to the existing publication Owner. The actual Host
/// retains its Store original and independently admits publication custody.
#export_name("clientInstallationPublicationStoragePrepare")
pub fn client_installation_publication_storage_prepare(
  contract : String,
  authority : String,
  generation : String,
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> Result[
  @publication.InstallationPublicationStorageBinding,
  @publication.PublicationContractIssue,
] {
  @publication.prepare_installation_publication_storage_binding(
    contract, authority, generation, bytes, nodes, depth,
  )
}

///|
#export_name("clientInstallationPublicationStorageWire")
pub fn client_installation_publication_storage_wire(
  value : @publication.InstallationPublicationStorageBinding,
) -> String {
  @publication.installation_publication_storage_binding_wire(value)
}

///|
#export_name("clientInstallationPublicationStorageCid")
pub fn client_installation_publication_storage_cid(
  value : @publication.InstallationPublicationStorageBinding,
) -> String {
  @publication.installation_publication_storage_binding_cid(value)
}
