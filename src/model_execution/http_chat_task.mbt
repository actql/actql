///|
/// A checked Task and matching nonsecret route. Physical installation is a
/// separate capability and still checks the runtime against the response profile.
pub struct PortableModelHttpChatTask {
  task : @environment.NormalizedPublicModelTask
  defaults : @publication_host.ClientModelProviderDefaults
  route : ResolvedStructuredModel
  profile : @environment.ModelResponseProfile
  provider_wire : String
  retained_bytes : Int64
}

///|
pub(all) enum PortableModelHttpChatTaskIssue {
  Capacity
  ForeignConfiguration
  Task(@environment.ModelTaskIssue)
}

///|
fn portable_model_http_metadata_units(
  extent : @environment.RegistryConstructionExtent,
) -> @relation.PreparationRepresentationUnits {
  {
    record_headers: extent.record_headers,
    reference_slots: extent.reference_slots,
    scalar_words: extent.scalar_words,
    owned_utf16_units: extent.owned_utf16_units,
    owned_wire_bytes: extent.owned_wire_bytes,
  }
}

///|
fn portable_model_http_profile_construction(
  body : Bytes,
  limits : @environment.Limits,
) -> (
  @relation.PreparationRepresentationUnits,
  @relation.PreparationRepresentationUnits,
)? {
  let nodes = Int::min(body.length(), limits.max_nodes)
  guard portable_model_http_configuration_construction_extent(
      body.length(),
      limits.max_bytes,
      nodes,
      limits.max_depth,
      normalize_keys=true,
    )
    is Some(parser) &&
    @environment.wire_hash_construction_extent(nodes) is Some(hashing) else {
    return None
  }
  // Only the typed profile, its installation/limits, at most eight
  // observation references and their projected strings escape this phase.
  let retained : @relation.PreparationRepresentationUnits = {
    record_headers: 48L,
    // Includes the borrowed execution and policy locators on the configuration.
    reference_slots: 74L,
    scalar_words: 48L,
    owned_utf16_units: body.length().to_int64(),
    owned_wire_bytes: 0L,
  }
  // Hash and hash-with-self-CID-omitted use the existing same emitter.
  // The indexed tree stays live while checking each closed record and
  // comparing the two bounded hash results. No parser result is retained.
  let fields = nodes.to_int64()
  guard @relation.compose_preparation_representation([
      parser,
      portable_model_http_metadata_units(hashing),
      retained,
      {
        record_headers: 24L + 12L * fields,
        reference_slots: 68L + 24L * fields,
        scalar_words: 48L + 18L * fields,
        owned_utf16_units: 3L * 71L,
        owned_wire_bytes: 512L,
      },
    ])
    is Some(working) else {
    return None
  }
  Some((retained, working))
}

///|
/// Admit only the three original canonical nonsecret Host documents and the
/// exact Response Profile. The caller holds all original body loans and pays
/// for each aggregate construction peak before it is used. The returned
/// extent is for the successful retained value, outside those body loans.
pub fn prepare_portable_model_http_chat_task(
  registry : @publication_host.ClientProjectModelRegistry,
  declaration : @environment.PublicModelTaskDeclaration,
  selection : @publication_host.ClientProjectModelTaskSelection,
  installation : Bytes,
  contract : Bytes,
  provider : Bytes,
  response : Bytes,
  profile_cid : String,
  credential_file : String,
  limits : @environment.ModelTaskLimits,
  prepare_peak : (Int64) -> Bool,
) -> Result[PortableModelHttpChatTask, PortableModelHttpChatTaskIssue] {
  guard @publication_host.client_project_model_task_selection_for(
      selection, registry, declaration,
    )
    is Some((provider_id, _, _)) else {
    return Err(ForeignConfiguration)
  }
  let bodies = limits.bodies
  let p = provider.length()
  let r = installation.length()
  let c = contract.length()
  guard p <= 65536 &&
    r > 0 &&
    r <= 65536 &&
    c > 0 &&
    c <= 65536 &&
    credential_file.length() > 0 &&
    credential_file.length() <= 128 &&
    credential_file != "." &&
    credential_file != ".." &&
    !credential_file.contains("/") &&
    !credential_file.contains("\\") &&
    !credential_file.contains("\u{0000}") &&
    profile_cid.length() == 71 else {
    return Err(ForeignConfiguration)
  }
  let route_owned : @relation.PreparationRepresentationUnits = {
    record_headers: 8L,
    reference_slots: 16L,
    scalar_words: 8L,
    owned_utf16_units: 2L * p.to_int64(),
    owned_wire_bytes: 0L,
  }
  guard portable_model_http_configuration_construction_extent(
      p,
      bodies.max_bytes,
      bodies.max_nodes,
      bodies.max_depth,
    )
    is Some(parser) &&
    @relation.preparation_representation_cost(route_owned) is Some(route_bytes) &&
    @encode.hash_writer_construction_inventory(0, 0) is Some(hash) &&
    @relation.compose_preparation_representation([
      route_owned,
      parser,
      {
        record_headers: 24L + 2L * hash.record_headers,
        reference_slots: 32L + 2L * hash.reference_slots,
        scalar_words: 24L + 2L * hash.scalar_words,
        // Three UTF-16 decode destinations, their returned strings, two
        // file identities and the protected credential reference comparison.
        owned_utf16_units: 2L * (p.to_int64() + r.to_int64() + c.to_int64()) +
        4L * 71L +
        2L * credential_file.length().to_int64() +
        16L,
        owned_wire_bytes: 2L * hash.owned_wire_bytes,
      },
    ])
    is Some(route_working) else {
    return Err(Capacity)
  }
  let combined = Ref(0L)
  let reserve = units => {
    guard @relation.preparation_representation_cost(units) is Some(bytes) &&
      @relation.checked_preparation_add_product(combined.val, 1L, bytes)
      is Some(next) &&
      prepare_peak(next) else {
      return false
    }
    combined.val = next
    true
  }
  if !reserve(route_working) {
    return Err(Capacity)
  }
  guard read_portable_model_http_chat_file_route(
      provider,
      provider_id,
      "sha256:" + @sha.hex(installation),
      "sha256:" + @sha.hex(contract),
      profile_cid,
      credential_file,
      bodies,
    )
    is Some(route) else {
    return Err(ForeignConfiguration)
  }
  let (installation_wire, contract_wire, provider_wire) = (
    @utf8.decode(installation),
    @utf8.decode(contract),
    @utf8.decode(provider),
  ) catch {
    _ => return Err(ForeignConfiguration)
  }
  guard @publication_host.client_model_provider_defaults_construction_extent(
      provider_id, installation_wire, contract_wire, provider_wire, bodies,
    )
    is Some(defaults_peak) &&
    reserve(portable_model_http_metadata_units(defaults_peak)) else {
    return Err(Capacity)
  }
  guard @publication_host.read_client_model_provider_defaults(
      provider_id,
      installation_wire,
      contract_wire,
      provider_wire,
      bodies,
      limits.max_work,
    )
    is Ok(defaults) else {
    return Err(ForeignConfiguration)
  }
  let (resolution, _) = @publication_host.client_model_provider_defaults_resolution_extents(
    defaults,
    @environment.public_model_task_declaration_limits(declaration).1,
  )
  guard @environment.public_model_task_normalization_construction_extent(
      declaration, limits,
    )
    is Some(normalization) &&
    reserve(portable_model_http_metadata_units(resolution)) &&
    reserve(portable_model_http_metadata_units(normalization)) else {
    return Err(Capacity)
  }
  let task = match
    @publication_host.normalize_client_project_model_task(
      selection, registry, declaration, defaults, limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Task(issue))
  }
  if @environment.normalized_public_model_task_model_selector(task) !=
    route.selector {
    return Err(ForeignConfiguration)
  }
  guard portable_model_http_profile_construction(response, bodies)
    is Some((profile_retained, profile_peak)) &&
    reserve(profile_peak) else {
    return Err(Capacity)
  }
  guard @environment.read_model_response_profile(
      response,
      profile_cid,
      bodies,
      limits.max_work,
    )
    is Ok(profile) &&
    @environment.model_response_profile_matches_normalized_chat(
      profile,
      task,
      route.endpoint,
    ) else {
    return Err(ForeignConfiguration)
  }
  guard @publication_host.client_model_provider_defaults_retained_extent(
      defaults,
    )
    is Some(defaults_retained) &&
    @relation.compose_preparation_representation([
      profile_retained,
      portable_model_http_metadata_units(defaults_retained),
      portable_model_http_metadata_units(
        @environment.normalized_public_model_task_retained_extent(task),
      ),
    ])
    is Some(retained) &&
    @relation.preparation_representation_cost(retained) is Some(other_bytes) &&
    @relation.checked_preparation_add_product(route_bytes, 1L, other_bytes)
    is Some(retained_bytes) &&
    retained_bytes <= combined.val else {
    return Err(Capacity)
  }
  Ok({ task, defaults, route, profile, provider_wire, retained_bytes, })
}

///|
/// Issue the capability from the already checked Task and its canonical
/// installation. The route and binding were admitted from the same bytes.
/// The Host funds the holders and supplies its independent physical profile.
pub fn install_portable_model_http_chat_capability(
  configured : PortableModelHttpChatTask,
  installation : @environment.ModelResponseProfileInstallation,
) -> Result[StructuredModelCapability, StructuredModelCapabilityIssue] {
  if !@environment.model_response_profile_matches_installation(
      configured.profile,
      installation,
    ) {
    return Err(ForeignProfile)
  }
  let connector = @environment.normalized_public_model_task_connector(
    configured.task,
  )
  match install_async_model_provider(connector) {
    Err(_) => Err(InvalidRegistration)
    Ok(provider) =>
      Ok({
        provider,
        binding: @publication_host.client_model_provider_defaults_binding(
          configured.defaults,
        ),
        profile: configured.profile,
        resolved: configured.route,
        adapter_supports: true,
        model_supports: true,
      })
  }
}
