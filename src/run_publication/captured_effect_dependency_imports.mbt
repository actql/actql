///|
/// Hash integrity and a closed DAG do not establish import correspondence.
/// Reuse already admitted values: do not parse or hash the closure again.
fn validate_effect_dependency_import_bindings(
  bodies : Array[CapturedEffectDependencyBody],
  prepared? : Bool = false,
  work? : ((Int) -> Bool)? = None,
) -> Result[Unit, CapturedEffectDependencyIssue] {
  // The prepared path builds each immutable Unit import index once. The
  // legacy branch keeps its original behavior. Every body/edge is still
  // validated, including duplicate/unused/missing import obligations below.
  let interfaces : Map[String, Map[String, Bool]]? = if prepared {
    let interfaces : Map[String, Map[String, Bool]] = Map([])
    for body in bodies {
      if !dependency_validation_work(work, 1) ||
        !dependency_validation_key_work(
          work,
          body.node.kind,
          body.node.identity,
          2,
        ) {
        return Err(ReferenceLimit)
      }
      if !dependency_validation_work(work, 1) {
        return Err(ReferenceLimit)
      }
      if body.node.kind != "local_dependencies" {
        continue
      }
      let selected : Map[String, Bool] = Map([])
      for reference in body.node.references {
        if !dependency_validation_work(work, reference.identity.length()) {
          return Err(ReferenceLimit)
        }
        if reference.kind == "result_import_interface" {
          selected[reference.identity] = true
        }
      }
      interfaces[body.node.identity] = selected
    }
    Some(interfaces)
  } else {
    None
  }
  let index : Map[String, @json.CanonicalValue] = Map([])
  for body in bodies {
    if !dependency_validation_work(work, 1) ||
      !dependency_validation_key_work(
        work,
        body.node.kind,
        body.node.identity,
        2,
      ) {
      return Err(ReferenceLimit)
    }
    index[dependency_key(body.node.kind, body.node.identity)] = body.value
  }
  fn referenced(
    value : @json.CanonicalValue,
    field : String,
    kind : String,
  ) -> @json.CanonicalValue? {
    guard dependency_binding_string(value, field, work) is Some(cid) else {
      return None
    }
    if !dependency_validation_key_work(work, kind, cid, 2) {
      return None
    }
    index.get(dependency_key(kind, cid))
  }
  for body in bodies {
    if !dependency_validation_work(work, 1) {
      return Err(ReferenceLimit)
    }
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
        dependency_binding_string(value, "input_name", work) is Some(input_name) &&
        dependency_binding_string(interface, "input_name", work) ==
        Some(input_name) &&
        dependency_binding_string(interface, "producer_result", work)
        is Some(result_name) &&
        dependency_binding_string(definition, "result_name", work) ==
        Some(result_name) &&
        dependency_binding_string(
          interface, "producer_unit_definition_cid", work,
        )
        is Some(producer) &&
        index.get(dependency_key("local_dependencies", producer))
        is Some(producer_definition) &&
        dependency_binding_field(interface, "producer_namespace", work)
        is Some(import_namespace) &&
        dependency_binding_field(producer_definition, "unit_namespace", work)
        is Some(producer_namespace) &&
        dependency_binding_string(import_namespace, "program_id", work) ==
        dependency_binding_string(producer_namespace, "program_id", work) &&
        dependency_binding_string(import_namespace, "node_id", work) ==
        dependency_binding_string(producer_namespace, "node_id", work) &&
        dependency_binding_string(definition, "unit_definition_cid", work) ==
        Some(producer) &&
        dependency_binding_string(manifest, "unit_definition_cid", work) ==
        Some(producer) &&
        dependency_binding_string(manifest, "local_invocation_cid", work) ==
        dependency_binding_string(artifact, "invocation_cid", work) &&
        dependency_binding_field(manifest, "results", work) is Some(results) &&
        dependency_binding_string(results, result_name, work) ==
        dependency_binding_string(value, "result_artifact_cid", work) &&
        dependency_binding_string(value, "import_interface_cid", work)
        is Some(interface_cid) &&
        (match interfaces {
          Some(interfaces) => {
            guard dependency_binding_string(consumer, "self_cid", work)
              is Some(unit) &&
              interfaces.get(unit) is Some(selected) else {
              return Err(InvalidBody)
            }
            selected.contains(interface_cid)
          }
          None => {
            guard dependency_binding_field(
                consumer, "import_interface_cids", work,
              )
              is Some(imports) &&
              dependency_binding_string_array(imports, work) is Some(imports) else {
              return Err(InvalidBody)
            }
            imports.contains(interface_cid)
          }
        }) else {
        return Err(InvalidBody)
      }
    } else if body.node.kind == "local_computation" {
      guard dependency_binding_string(value, "unit_definition_cid", work)
        is Some(unit) &&
        referenced(value, "unit_definition_cid", "local_dependencies")
        is Some(definition) &&
        dependency_binding_field(definition, "import_interface_cids", work)
        is Some(imports) &&
        dependency_binding_string_array(imports, work) is Some(imports) &&
        dependency_binding_field(value, "observation_cids", work)
        is Some(observations) &&
        dependency_binding_string_array(observations, work)
        is Some(observations) else {
        return Err(InvalidBody)
      }
      let positions : Map[String, Bool] = Map([])
      let observed_interfaces : Map[String, Bool] = Map([])
      let model_positions : Map[Int64, Bool] = Map([])
      for cid in observations {
        if !dependency_validation_work(work, cid.length()) ||
          !dependency_validation_work(work, 1) {
          return Err(ReferenceLimit)
        }
        if index.get(dependency_key("local_model_observation", cid))
          is Some(observation) {
          guard dependency_binding_string(
              observation, "unit_definition_cid", work,
            ) ==
            Some(unit) &&
            dependency_binding_field(observation, "source_ordinal", work)
            is Some(@json.Number(raw)) &&
            @scalar.read_safe_integer(raw) is Some(ordinal) &&
            !model_positions.contains(ordinal) else {
            return Err(InvalidBody)
          }
          model_positions[ordinal] = true
        } else if index.get(dependency_key("result_import_observation", cid))
          is Some(observation) {
          guard dependency_binding_string(
              observation, "consumer_unit_definition_cid", work,
            ) ==
            Some(unit) &&
            dependency_binding_string(observation, "input_name", work)
            is Some(position) &&
            dependency_binding_string(observation, "import_interface_cid", work)
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
      guard dependency_binding_string(value, "unit_definition_cid", work)
        is Some(unit) &&
        dependency_binding_string(value, "local_invocation_cid", work)
        is Some(invocation) &&
        referenced(value, "local_invocation_cid", "local_computation")
        is Some(computation) &&
        dependency_binding_string(computation, "unit_definition_cid", work) ==
        Some(unit) &&
        dependency_binding_field(value, "results", work) is Some(results) &&
        dependency_binding_fields(results, work) is Ok(results) else {
        return Err(InvalidBody)
      }
      for
        (map_name, artifact_kind, definition_kind, name_field) in [
          (
            "results", "result_artifact", "local_result_definition", "result_name",
          ),
          (
            "table_inputs", "table_input_artifact", "local_table_input_definition",
            "table_input_name",
          ),
        ] {
        let entries = if map_name == "results" {
          results
        } else {
          match dependency_binding_field(value, map_name, work) {
            None => continue
            Some(map) => {
              guard dependency_binding_fields(map, work) is Ok(entries) else {
                return Err(InvalidBody)
              }
              entries
            }
          }
        }
        for (name, cid_value) in entries {
          if !dependency_validation_work(work, name.length()) ||
            !dependency_validation_work(work, 1) {
            return Err(ReferenceLimit)
          }
          guard string_value(cid_value) is Some(cid) &&
            index.get(dependency_key(artifact_kind, cid)) is Some(artifact) &&
            dependency_binding_string(artifact, "invocation_cid", work) ==
            Some(invocation) &&
            referenced(artifact, "result_definition_cid", definition_kind)
            is Some(definition) &&
            dependency_binding_string(definition, "unit_definition_cid", work) ==
            Some(unit) &&
            dependency_binding_string(definition, name_field, work) ==
            Some(name) else {
            return Err(InvalidBody)
          }
        }
      }
    }
  }
  Ok(())
}

///|
// Prepared dependency bindings use the admitted canonical field order. The
// legacy field lookup stays untouched; this private binary search borrows the
// same frozen fields and charges spans before comparison, with no copy/index.
fn dependency_binding_field(
  value : @json.CanonicalValue,
  name : String,
  work : ((Int) -> Bool)?,
) -> @json.CanonicalValue? {
  if work is None {
    return @json.object_field(value, name)
  }
  guard value is @json.Object(fields) else { return None }
  let mut low = 0
  let mut high = @json.array_count(fields)
  while low < high {
    if !dependency_validation_work(work, 1) {
      return None
    }
    let middle = low + (high - low) / 2
    let (key, item) = @json.array_at(fields, middle).unwrap()
    if !dependency_validation_work(work, key.length()) ||
      !dependency_validation_work(work, name.length()) {
      return None
    }
    let compared = @canonical.compare_utf16(key, name)
    if compared == 0 {
      return Some(item)
    }
    if compared < 0 {
      low = middle + 1
    } else {
      high = middle
    }
  }
  None
}

///|
fn dependency_binding_string(
  value : @json.CanonicalValue,
  field : String,
  work : ((Int) -> Bool)?,
) -> String? {
  guard dependency_binding_field(value, field, work) is Some(@json.String(text)) else {
    return None
  }
  if !dependency_validation_work(work, text.length()) {
    return None
  }
  Some(text)
}

///|
fn dependency_binding_string_array(
  value : @json.CanonicalValue,
  work : ((Int) -> Bool)?,
) -> Array[String]? {
  if work is None {
    return evidence_string_array(value)
  }
  guard value is @json.Array(values) else { return None }
  let count = @json.array_count(values)
  if !dependency_validation_work(work, count) {
    return None
  }
  let result : Array[String] = []
  for index in 0..<count {
    guard @json.array_at(values, index) is Some(@json.String(text)) else {
      return None
    }
    if !dependency_validation_work(work, text.length()) {
      return None
    }
    result.push(text)
  }
  Some(result)
}

///|
fn dependency_binding_fields(
  value : @json.CanonicalValue,
  work : ((Int) -> Bool)?,
) -> Result[Array[(String, @json.CanonicalValue)], PublicationContractIssue] {
  if work is Some(_) {
    guard @json.object_field_count(value) is Some(count) &&
      dependency_validation_work(work, count) else {
      return Err(Encoding)
    }
  }
  object_fields(value)
}
