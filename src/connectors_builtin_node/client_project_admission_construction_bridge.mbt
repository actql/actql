///|
fn client_project_admission_capacity(
  inventory : @execution.PreparationRepresentationUnits?,
) -> @execution.ExecutionCapacity? {
  guard inventory is Some(retained) else { return None }
  @execution.preparation_execution_capacity({
    retained,
    workspace: {
      record_headers: 0L,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  })
}

///|
#export_name("clientProjectCatalogAdmissionConstructionCapacity")
pub fn client_project_catalog_admission_construction_capacity(
  wire : String,
) -> @execution.ExecutionCapacity? {
  client_project_admission_capacity(
    @publication_host.client_project_catalog_admission_construction_inventory(
      wire,
    ),
  )
}

///|
#export_name("clientProjectConnectionsAdmissionConstructionCapacity")
pub fn client_project_connections_admission_construction_capacity(
  wire : String,
) -> @execution.ExecutionCapacity? {
  client_project_admission_capacity(
    @publication_host.client_project_connections_admission_construction_inventory(
      wire,
    ),
  )
}
