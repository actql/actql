///|
/// Fixed checked schema and limits only. The Node test uses the product Host
/// receiver; this fixture cannot issue storage or execution evidence.
#export_name("managedFileValues")
pub fn managed_file_values() -> @execution.ManagedOutputValues {
  let checked = @pipeline.check(
    cursor(
      "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"label\":{\"type\":\"string\",\"nullable\":true}},\"rows\":[]},\"as\":\"v\"},{\"select\":[\"id\",\"label\"]}]",
    ),
    [],
    None,
    None,
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 20,
    },
  ).unwrap()
  let owner = @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  @execution.prepare_managed_output_values(
    owner,
    Step(1),
    100,
    { max_nodes: 1000, max_text_bytes: 10000, max_depth: 10, max_work: 10000, },
    1000,
    { max_work: 1000, max_bytes: 10000, max_nodes: 1000, max_depth: 10, },
  ).unwrap()
}

///|
#export_name("managedFilePhysicalLimits")
pub fn managed_file_physical_limits() -> @duckdb.PhysicalResultLimits {
  { max_rows: 100, max_cells: 200, max_nodes: 1000, max_text_bytes: 10000, }
}

///|
#export_name("managedFileTransportLimits")
pub fn managed_file_transport_limits() -> @duckdb.TransportColumnLimits {
  {
    max_rows: 100,
    max_columns: 2,
    max_bytes: 10000,
    max_nodes: 1000,
    max_text_bytes: 10000,
  }
}
