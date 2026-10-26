///|
// Existing SourceView static identity DATA, not a ResourceReference issuer.
// Connection revision/current authority and concrete boundary evidence remain
// with the installing Host. Schema/payload admission shares the declaration's
// remaining byte/node/depth envelope rather than a second unbounded parser.
fn relation_resource_identity_body(
  wire : String,
  resource_kind : String,
  schema : @schema.Schema,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_work : Int,
) -> Result[(Json, Int, Int, Int), RowHostIssue] {
  if max_bytes < 1 || max_nodes < 1 || max_depth < 1 {
    return Err(InvalidSpecification)
  }
  let source = match
    @source.parse_json(wire, {
      max_input_bytes: max_bytes,
      max_nodes,
      max_depth,
    }) {
    Ok(value) => value
    Err(_) => return Err(InvalidSpecification)
  }
  let cursor = match
    @decode.admit(source, {
      max_nodes,
      max_depth,
      max_string_bytes: max_bytes,
      max_total_string_bytes: max_bytes,
    }) {
    Ok(value) => value
    Err(_) => return Err(InvalidSpecification)
  }
  let used_work = match
    @environment.check_source_view_resource_identity_shape(cursor, max_work) {
    Ok(value) => value
    Err(_) => return Err(InvalidSpecification)
  }
  let parsed = @json.parse(wire) catch { _ => return Err(InvalidSpecification) }
  guard spec_text(parsed, "resource_kind") == Some(resource_kind) &&
    spec_text(parsed, "provider_id_field") is Some(provider_id) &&
    @schema.lookup_reference(schema, provider_id) is Some(_) &&
    spec_text(parsed, "output_field") is Some(output) &&
    @schema.lookup_reference(schema, output) is Some(field) &&
    field.contract.shape is @contract.ResourceRef(resource_kind=output_kind) &&
    output_kind == resource_kind else {
    return Err(InvalidSpecification)
  }
  let canonical = @identity.from_json(parsed, max_nodes, max_depth, max_bytes) catch {
    _ => return Err(InvalidSpecification)
  }
  let bytes = @identity.measure_value(
    canonical, max_bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(InvalidSpecification)
  }
  let canonical_wire = @identity.stringify_value(
    canonical, bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(InvalidSpecification)
  }
  let canonical_body = @json.parse(canonical_wire) catch {
    _ => return Err(InvalidSpecification)
  }
  Ok((canonical_body, bytes, @decode.admission_usage(cursor).nodes, used_work))
}
