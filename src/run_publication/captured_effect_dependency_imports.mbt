///|
/// Hash integrity and a closed DAG do not establish import correspondence.
/// Reuse already admitted values: do not parse or hash the closure again.
fn validate_effect_dependency_import_bindings(
  bodies : Array[CapturedEffectDependencyBody],
) -> Result[Unit, CapturedEffectDependencyIssue] {
  let index : Map[String, @json.CanonicalValue] = Map([])
  for body in bodies {
    index[dependency_key(body.node.kind, body.node.identity)] = body.value
  }
  fn referenced(
    value : @json.CanonicalValue,
    field : String,
    kind : String,
  ) -> @json.CanonicalValue? {
    guard evidence_string(value, field) is Some(cid) else { return None }
    index.get(dependency_key(kind, cid))
  }
  for body in bodies {
    let value = body.value
    if body.node.kind == "result_import_observation" {
      guard referenced(value, "import_interface_cid", "result_import_interface")
        is Some(interface) &&
        referenced(value, "consumer_unit_definition_cid", "local_dependencies")
        is Some(consumer) &&
        referenced(value, "producer_local_manifest_cid", "local_manifest")
        is Some(manifest) &&
        referenced(value, "result_artifact_cid", "result_artifact")
        is Some(artifact) &&
        referenced(artifact, "result_definition_cid", "local_result_definition")
        is Some(definition) &&
        evidence_string(value, "input_name") is Some(input_name) &&
        evidence_string(interface, "input_name") == Some(input_name) &&
        evidence_string(interface, "producer_result") is Some(result_name) &&
        evidence_string(definition, "result_name") == Some(result_name) &&
        evidence_string(interface, "producer_unit_definition_cid")
        is Some(producer) &&
        index.get(dependency_key("local_dependencies", producer))
        is Some(producer_definition) &&
        @json.object_field(interface, "producer_namespace")
        is Some(import_namespace) &&
        @json.object_field(producer_definition, "unit_namespace")
        is Some(producer_namespace) &&
        evidence_string(import_namespace, "program_id") ==
        evidence_string(producer_namespace, "program_id") &&
        evidence_string(import_namespace, "node_id") ==
        evidence_string(producer_namespace, "node_id") &&
        evidence_string(definition, "unit_definition_cid") == Some(producer) &&
        evidence_string(manifest, "unit_definition_cid") == Some(producer) &&
        evidence_string(manifest, "local_invocation_cid") ==
        evidence_string(artifact, "invocation_cid") &&
        @json.object_field(manifest, "results") is Some(results) &&
        evidence_string(results, result_name) ==
        evidence_string(value, "result_artifact_cid") &&
        @json.object_field(consumer, "import_interface_cids") is Some(imports) &&
        evidence_string_array(imports) is Some(imports) &&
        evidence_string(value, "import_interface_cid") is Some(interface_cid) &&
        imports.contains(interface_cid) else {
        return Err(InvalidBody)
      }
    } else if body.node.kind == "local_computation" {
      guard evidence_string(value, "unit_definition_cid") is Some(unit) &&
        referenced(value, "unit_definition_cid", "local_dependencies")
        is Some(definition) &&
        @json.object_field(definition, "import_interface_cids") is Some(imports) &&
        evidence_string_array(imports) is Some(imports) &&
        @json.object_field(value, "observation_cids") is Some(observations) &&
        evidence_string_array(observations) is Some(observations) else {
        return Err(InvalidBody)
      }
      let positions : Map[String, Bool] = Map([])
      let observed_interfaces : Map[String, Bool] = Map([])
      for cid in observations {
        if index.get(dependency_key("result_import_observation", cid))
          is Some(observation) {
          guard evidence_string(observation, "consumer_unit_definition_cid") ==
            Some(unit) &&
            evidence_string(observation, "input_name") is Some(position) &&
            evidence_string(observation, "import_interface_cid")
            is Some(interface) &&
            !positions.contains(position) else {
            return Err(InvalidBody)
          }
          positions[position] = true
          observed_interfaces[interface] = true
        }
      }
      for interface in imports {
        if !observed_interfaces.contains(interface) {
          return Err(InvalidBody)
        }
      }
    } else if body.node.kind == "local_manifest" {
      guard evidence_string(value, "unit_definition_cid") is Some(unit) &&
        evidence_string(value, "local_invocation_cid") is Some(invocation) &&
        referenced(value, "local_invocation_cid", "local_computation")
        is Some(computation) &&
        evidence_string(computation, "unit_definition_cid") == Some(unit) &&
        @json.object_field(value, "results") is Some(results) &&
        object_fields(results) is Ok(results) else {
        return Err(InvalidBody)
      }
      for (name, cid_value) in results {
        guard string_value(cid_value) is Some(cid) &&
          index.get(dependency_key("result_artifact", cid)) is Some(artifact) &&
          evidence_string(artifact, "invocation_cid") == Some(invocation) &&
          referenced(
            artifact, "result_definition_cid", "local_result_definition",
          )
          is Some(definition) &&
          evidence_string(definition, "unit_definition_cid") == Some(unit) &&
          evidence_string(definition, "result_name") == Some(name) else {
          return Err(InvalidBody)
        }
      }
    }
  }
  Ok(())
}
