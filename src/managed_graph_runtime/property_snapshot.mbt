///|
/// Restore through the exact output's existing storage and retention owner.
pub fn append_property_snapshot_node(
  output : OutputBuilder,
  record : @decode.Cursor,
  reference_issuer? : @value.ReferenceIssuer? = None,
) -> Result[Unit, Issue] {
  if !output.open {
    return Err(Closed)
  }
  @storage.append_property_snapshot_node(
    output.graph,
    record,
    reference_issuer~,
  ).map_err(issue => {
    output.open = false
    @lifecycle.cancel_retention_port(output.retention) |> ignore
    Storage(issue)
  })
}

///|
pub fn append_property_snapshot_edge(
  output : OutputBuilder,
  record : @decode.Cursor,
  reference_issuer? : @value.ReferenceIssuer? = None,
) -> Result[Unit, Issue] {
  if !output.open {
    return Err(Closed)
  }
  @storage.append_property_snapshot_edge(
    output.graph,
    record,
    reference_issuer~,
  ).map_err(issue => {
    output.open = false
    @lifecycle.cancel_retention_port(output.retention) |> ignore
    Storage(issue)
  })
}
