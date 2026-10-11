///|
/// Original describe response and its existing Catalog projection. This is
/// private evidence, not current Provider permission or Reviewer authority.
pub struct NativeEffectCatalogResponse {
  catalog : @catalog.CatalogObservation
  use_cid : String
  status : Int
  body : Bytes
}

///|
fn effect_catalog_binding_fields(
  binding : @catalog.CatalogObservationBinding,
  resource : String,
  authority : String,
) -> Array[String] {
  [
    "actql-native-effect-catalog-custody/0.1",
    authority,
    binding.namespace_id,
    binding.principal,
    binding.environment,
    binding.connection_revision,
    binding.org_id,
    binding.site_key,
    binding.site_generation.to_string(),
    binding.connector_registration,
    binding.connector_revision,
    binding.resource_origin,
    binding.run_invocation_cid,
    binding.dispatch_request_cid,
    binding.sync_occurrence,
    resource,
  ]
}

///|
fn effect_catalog_strings(
  fields : Array[String],
  max_bytes : Int,
) -> Result[String, NativePublicationStoreIssue] {
  try {
    let writer = @encode.writer(max_bytes, 64, 2)
    @encode.begin_array(writer)
    for field in fields {
      @encode.string_value(writer, field)
    }
    @encode.end_array(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(InvalidConfiguration)
  }
}

///|
/// One scoped original observation slot, independent of encrypted nonce or
/// response content. Another response cannot silently occupy a second slot.
#warnings("-unused_value")
fn effect_catalog_holding(
  binding : @catalog.CatalogObservationBinding,
  resource : String,
  authority : String,
  max_bytes : Int,
) -> Result[String, NativePublicationStoreIssue] {
  if authority.is_empty() || resource.is_empty() {
    return Err(InvalidConfiguration)
  }
  effect_catalog_strings(
    effect_catalog_binding_fields(binding, resource, authority),
    max_bytes,
  ).map(body => "sha256:" + @sha.hex(@utf8.encode(body)))
}

///|
/// Reuse the Catalog Owner's exact body/use/hash/binding admission. Caller
/// selects the original binding from trusted retained Host custody; response
/// bytes or a proposed Catalog cannot supply that expected context.
fn effect_catalog_response(
  catalog_wire : String,
  binding : @catalog.CatalogObservationBinding,
  resource : String,
  use_cid : String,
  status : Int,
  body : Bytes,
  limits : @catalog.DescribeLimits,
  max_bytes : Int,
) -> Result[NativeEffectCatalogResponse, NativePublicationStoreIssue] {
  if status != 200 || body.length() > limits.max_bytes {
    return Err(StateCollision)
  }
  let owned_body = body[:].to_owned()
  match
    @catalog.recover_named_catalog_observation(
      catalog_wire,
      [resource],
      [Some(owned_body)],
      [1],
      binding,
      [Some(use_cid)],
      [Some(@catalog.catalog_response_sha256(owned_body))],
      limits,
      max_bytes,
    ) {
    Ok(catalog) => Ok({ catalog, use_cid, status, body: owned_body, })
    Err(_) => Err(StateCollision)
  }
}

///|
fn effect_catalog_record(
  evidence : NativeEffectCatalogResponse,
  binding : @catalog.CatalogObservationBinding,
  resource : String,
  authority : String,
  max_bytes : Int,
) -> Result[String, NativePublicationStoreIssue] {
  let fields = effect_catalog_binding_fields(binding, resource, authority)
  fields.push(evidence.use_cid)
  fields.push(evidence.status.to_string())
  fields.push(@catalog.catalog_response_sha256(evidence.body))
  fields.push(@base64.encode(evidence.body))
  fields.push(@catalog.catalog_observation_json(evidence.catalog))
  effect_catalog_strings(fields, max_bytes)
}

///|
#warnings("-unused_value")
fn restore_effect_catalog_record(
  wire : String,
  binding : @catalog.CatalogObservationBinding,
  resource : String,
  original_use_cid : String,
  authority : String,
  limits : @catalog.DescribeLimits,
  max_bytes : Int,
) -> Result[NativeEffectCatalogResponse, NativePublicationStoreIssue] {
  let source = match
    @source.parse_json_bytes_preserving(@utf8.encode(wire), {
      max_input_bytes: max_bytes,
      max_nodes: 64,
      max_depth: 2,
    }) {
    Ok(value) => value
    Err(_) => return Err(StateCollision)
  }
  let cursor = match
    @decode.admit(source, {
      max_nodes: 64,
      max_depth: 2,
      max_string_bytes: max_bytes,
      max_total_string_bytes: max_bytes,
    }) {
    Ok(value) => value
    Err(_) => return Err(StateCollision)
  }
  let elements = match @decode.elements(cursor) {
    Ok(value) if value.length() == 21 => value
    _ => return Err(StateCollision)
  }
  let fields : Array[String] = []
  for element in elements {
    match @decode.text(element) {
      Ok(value) => fields.push(value)
      Err(_) => return Err(StateCollision)
    }
  }
  let expected = effect_catalog_binding_fields(binding, resource, authority)
  for index in 0..<expected.length() {
    if fields[index] != expected[index] {
      return Err(StateCollision)
    }
  }
  let body = @base64.decode(fields[19][:]) catch {
    _ => return Err(StateCollision)
  }
  if fields[16] != original_use_cid ||
    fields[17] != "200" ||
    @catalog.catalog_response_sha256(body) != fields[18] {
    return Err(StateCollision)
  }
  let evidence = match
    effect_catalog_response(
      fields[20],
      binding,
      resource,
      fields[16],
      200,
      body,
      limits,
      max_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // Encrypted storage carries exact original bytes, not a newly normalized
  // response or another accepted spelling of the private record.
  match
    effect_catalog_record(evidence, binding, resource, authority, max_bytes) {
    Ok(original) if original == wire => Ok(evidence)
    _ => Err(StateCollision)
  }
}

///|
#warnings("-unused_value")
fn effect_catalog_terminal(holding : String, bytes : Int64) -> String {
  // Holding is the bounded lowercase digest issued by effect_catalog_holding;
  // this tombstone carries only reservation metadata, never Provider bytes.
  "[\"actql-native-effect-catalog-retired/0.1\",\"" +
  holding +
  "\",\"" +
  bytes.to_string() +
  "\"]"
}

///|
#warnings("-unused_value")
fn effect_catalog_terminal_bytes(
  wire : String,
  holding : String,
  max_bytes : Int,
) -> Int64? {
  let prefix = "[\"actql-native-effect-catalog-retired/0.1\",\"" +
    holding +
    "\",\""
  guard wire.has_prefix(prefix) && wire.has_suffix("\"]") else { return None }
  let count = wire.unsafe_substring(
    start=prefix.length(),
    end=wire.length() - 2,
  )
  let bytes = @string.parse_int64(count) catch { _ => return None }
  guard bytes > 0L &&
    bytes <= max_bytes.to_int64() &&
    bytes <= 1398272L &&
    effect_catalog_terminal(holding, bytes) == wire else {
    return None
  }
  Some(bytes)
}
