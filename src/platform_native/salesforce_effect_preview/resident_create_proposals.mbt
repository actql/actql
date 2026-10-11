///|
/// Requests projected from one actual retained consumer Result. This connection
/// owns no approval, credential use, execution permit or physical holding.
/// Its original consumer/input owners must remain current through Preview.
struct NativeResidentEffectCreatedTargets {
  consumer : @resident.ResidentSourceCompute
  materials : @host.ClientEffectRunMaterials
  inputs : @strategy.CapturedEffectInputs
  request : @host.ClientRequestIdentity
  stage : Int
  effect_id : String
  local_result : Int
  requests : Array[@catalog.SingleWriteRequest]
}

///|
fn NativeResidentEffectCreatedTargets::matches(
  self : NativeResidentEffectCreatedTargets,
  consumer : @resident.ResidentSourceCompute,
  materials : @host.ClientEffectRunMaterials,
  inputs : @strategy.CapturedEffectInputs,
  stage : Int,
  effect_id : String,
  local_result : Int,
) -> Bool {
  physical_equal(self.consumer, consumer) &&
  physical_equal(self.materials.prepared, materials.prepared) &&
  physical_equal(self.materials.compilation, materials.compilation) &&
  physical_equal(self.materials.allowed, materials.allowed) &&
  @publication.publication_contract_identity(self.materials.run_definition) ==
  @publication.publication_contract_identity(materials.run_definition) &&
  physical_equal(self.inputs, inputs) &&
  self.stage == stage &&
  self.effect_id == effect_id &&
  self.local_result == local_result &&
  materials.request == Some(self.request) &&
  consumer.request_for_effect_review(inputs) == Some(self.request)
}

///|
/// Project mapped create requests through the checked proposal and Catalog
/// Owners. No existing target is observed or claimed absent at a Provider:
/// create-before and content/occurrence identities use the shared Preview law.
/// Failed export cannot produce this nominal connection or authorize a write.
pub fn prepare_native_resident_effect_created_targets(
  consumer : @resident.ResidentSourceCompute,
  materials : @host.ClientEffectRunMaterials,
  inputs : @strategy.CapturedEffectInputs,
  stage : Int,
  effect_id : String,
  local_result : Int,
  mapping : @catalog.ExecutionMapping,
  projection : @catalog.WriteProjection,
  api_version : String,
  export_limits : @host.PublicationOutputExportLimits,
  body_limits : @catalog.WriteBodyLimits,
  request_limits : @catalog.WriteRequestLimits,
  max_rows : Int,
  max_fields : Int,
  max_work : Int,
  max_utf16_units : Int,
  max_total_bytes : Int,
) -> Result[NativeResidentEffectCreatedTargets, NativeResidentEffectTargetIssue] {
  if max_rows < 1 ||
    max_work < 1 ||
    max_utf16_units < 1 ||
    max_total_bytes < 1 ||
    body_limits.max_bytes < 1 ||
    body_limits.max_nodes < 1 ||
    body_limits.max_depth < 1 {
    return Err(InvalidLimits)
  }
  guard consumer.request_for_effect_review(inputs) is Some(request) &&
    materials.request == Some(request) &&
    @host.client_effect_member_descriptor(
      materials.prepared,
      stage,
      effect_id,
      max_work,
    )
    is Ok(descriptor) &&
    descriptor.2 == "create" &&
    descriptor.4 == mapping.mapping_ref &&
    descriptor.5 == mapping.mapping_cid &&
    mapping.operation is @catalog.WriteCreate &&
    @strategy.captured_effect_inputs_match_computation(
      inputs,
      @host.prepared_client_effect_computation_graph(materials.prepared),
    ) &&
    @strategy.captured_effect_inputs_run_definition_cid(inputs) ==
    Some(@publication.publication_contract_identity(materials.run_definition)) else {
    return Err(ForeignMapping)
  }
  match @catalog.check_execution_write(mapping, projection) {
    Ok(_) => ()
    Err(issue) => return Err(Mapping(issue))
  }
  let requests : Array[@catalog.SingleWriteRequest] = []
  let mut remaining = max_total_bytes
  let mut failure : NativeResidentEffectTargetIssue? = None
  let receive = (index : Int, selector : String, changes : String) => {
    let prepare = () => {
      if index != requests.length() ||
        index >= max_rows ||
        selector != "null" ||
        consumer.request_for_effect_review(inputs) != Some(request) {
        return Err(NativeResidentEffectTargetIssue::InvalidChanges)
      }
      let changes_bytes = @utf8.encode(changes)
      if changes_bytes.length() > remaining {
        return Err(InvalidLimits)
      }
      let body = try {
        let source = match
          @source.parse_json_bytes_preserving(changes_bytes, {
            max_input_bytes: body_limits.max_bytes,
            max_nodes: body_limits.max_nodes,
            max_depth: body_limits.max_depth,
          }) {
          Ok(value) => value
          Err(_) => return Err(InvalidChanges)
        }
        let value = @canonical.from_source(
          source,
          body_limits.max_nodes,
          body_limits.max_depth,
          body_limits.max_bytes,
          data_keys=true,
        )
        guard @canonical.object_field_count(value) == Some(2) &&
          @canonical.object_field(value, "state")
          is Some(@canonical.String("present")) &&
          @canonical.object_field(value, "value") is Some(body) else {
          return Err(InvalidChanges)
        }
        @canonical.stringify_value(
          body,
          body_limits.max_bytes,
          body_limits.max_nodes,
          body_limits.max_depth,
        )
      } catch {
        _ => return Err(InvalidChanges)
      }
      let proposed = match
        @catalog.recover_single_write_request(
          projection, body, selector, api_version, body_limits, request_limits,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Request(issue))
      }
      match @catalog.check_execution_single_write(mapping, proposed) {
        Ok(_) => ()
        Err(issue) => return Err(Mapping(issue))
      }
      if @catalog.single_write_request_effect_kind(proposed) != "create" {
        return Err(ForeignMapping)
      }
      remaining -= changes_bytes.length()
      requests.push(proposed)
      Ok(())
    }
    match prepare() {
      Ok(_) => Ok(())
      Err(issue) => {
        failure = Some(issue)
        Err(())
      }
    }
  }
  match
    consumer.read_effect_proposals(
      inputs,
      descriptor.0,
      local_result,
      export_limits,
      max_fields,
      max_work,
      body_limits.max_bytes,
      body_limits.max_nodes,
      body_limits.max_depth,
      max_utf16_units,
      receive,
    ) {
    Ok(count) if count == requests.length() &&
      consumer.request_for_effect_review(inputs) == Some(request) =>
      Ok({
        consumer,
        materials,
        inputs,
        request,
        stage,
        effect_id,
        local_result,
        requests,
      })
    Ok(_) => Err(InvalidChanges)
    Err(@resident.ReceiverRejected) => Err(failure.unwrap_or(InvalidChanges))
    Err(issue) => Err(Proposal(issue))
  }
}
