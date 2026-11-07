///|
// Canonical DATA assembly only. Every entry is still admitted by the same
// ordinary Environment/Catalog owner; exact duplicate bodies coalesce, while
// conflicting selectors remain present for its original typed refusal.
fn local_project_mock_members(
  values : Array[Json],
) -> Result[Json, LocalProjectMockModelIssue] {
  let members : Array[(String, String, Json)] = []
  for value in values {
    let wire = match local_project_mock_relation_wire(value) {
      Ok(value) => value
      Err(issue) => return Err(Source(issue))
    }
    if !members.any(entry => entry.1 == wire) {
      members.push(("sha256:" + @sha.hex(@utf8.encode(wire)), wire, value))
    }
  }
  members.sort_by((left, right) => {
    if left.0 < right.0 {
      -1
    } else if left.0 == right.0 {
      0
    } else {
      1
    }
  })
  Ok(Json::array(members.map(entry => entry.2)))
}

///|
fn local_project_mock_json(wire : String) -> Json raise ClientStop {
  @json.parse(wire) catch {
    _ => stop("InvalidProjectBindings")
  }
}

///|
fn local_project_mock_array(
  value : Json,
  key : String,
) -> Array[Json] raise ClientStop {
  guard value is Object(fields) && fields.get(key) is Some(Array(values)) else {
    stop("InvalidProjectBindings")
  }
  values.copy()
}

///|
fn LocalProjectMockDeclarations::prepare_source_environment(
  self : Self,
  base : @checked.CheckEnvironment,
) -> Result[@checked.CheckEnvironment, LocalProjectMockModelIssue] {
  if self.closing || self.retired || !self.sources_started {
    return Err(ForeignOriginal)
  }
  if self.model_failure is Some(issue) {
    return Err(issue)
  }
  if self.source_environment is Some((original, prepared)) {
    return if physical_equal(original, base) {
      Ok(prepared)
    } else {
      Err(ForeignOriginal)
    }
  }
  let result = try {
    let writer = @encode.writer(4000000, 400000, 64)
    @compiler_environment.emit(@checked.checking_environment_wire(base), writer)
    guard local_project_mock_json(@encode.finish(writer)) is Object(body) else {
      stop("InvalidProjectBindings")
    }
    let original = Json::object(body)
    let catalogs = local_project_mock_array(original, "connector_catalogs")
    let contracts = local_project_mock_array(original, "contract_registry")
    let views = local_project_mock_array(original, "source_views")
    let schemas = local_project_mock_array(original, "schema_snapshots")
    let capabilities = local_project_mock_array(
      original, "connector_capabilities",
    )
    let mappings = local_project_mock_array(original, "mapping_contracts")
    let manifest = match body.get("connector_manifest") {
      Some(Object(fields)) => fields
      None =>
        Map([
          ("version", Json::string("actql-connectors/0.1")),
          ("connectors", Json::array([])),
        ])
      _ => stop("InvalidProjectBindings")
    }
    let entries = local_project_mock_array(Json::object(manifest), "connectors")
    for source in self.sources {
      let declaration = source._retained_declaration
      catalogs.push(local_project_mock_json(declaration.catalog))
      for wire in declaration.contracts {
        contracts.push(local_project_mock_json(wire))
      }
      for wire in declaration.view_bodies {
        views.push(local_project_mock_json(wire))
      }
      let (source_schemas, source_capabilities) = @row_host.row_declaration_evidence_members(
        declaration,
      )
      for wire in source_schemas {
        schemas.push(local_project_mock_json(wire))
      }
      for wire in source_capabilities {
        capabilities.push(local_project_mock_json(wire))
      }
      entries.push(local_project_mock_json(declaration.manifest_entry))
      for write in source._retained_writes {
        mappings.push(local_project_mock_json(write.mapping.body))
      }
    }
    for
      (key, values) in [
        ("connector_catalogs", catalogs),
        ("contract_registry", contracts),
        ("source_views", views),
        ("schema_snapshots", schemas),
        ("connector_capabilities", capabilities),
        ("mapping_contracts", mappings),
      ] {
      body[key] = local_project_mock_members(values).unwrap_or_else(() => {
        stop("InvalidProjectBindings")
      })
    }
    manifest["connectors"] = local_project_mock_members(entries).unwrap_or_else(() => {
        stop("InvalidProjectBindings")
      },
    )
    body["connector_manifest"] = Json::object(manifest)
    ignore(body.remove("evidence_bundle_cid"))
    let preimage = local_project_mock_relation_wire(Json::object(body)).unwrap_or_else(() => {
        stop("InvalidProjectBindings")
      },
    )
    let cid = "sha256:" + @sha.hex(@utf8.encode(preimage))
    body["evidence_bundle_cid"] = Json::string(cid)
    let wire = local_project_mock_relation_wire(Json::object(body)).unwrap_or_else(() => {
        stop("InvalidProjectBindings")
      },
    )
    match local_admitted_check_environment(wire, cid) {
      Some(prepared) => Ok(prepared)
      None => Err(Environment)
    }
  } catch {
    _ => Err(Environment)
  }
  match result {
    Ok(prepared) => self.source_environment = Some((base, prepared))
    Err(issue) => self.model_failure = Some(issue)
  }
  result
}

///|
// Project only names/requests onto SAME restored view originals. The existing
// publication owner checks path syntax, complete schema and request contracts.
fn LocalProjectMockDeclarations::source_aliases(
  self : Self,
) -> Array[Json] raise ClientStop {
  let result = []
  for source in self.sources {
    for
      entry in local_project_mock_array(source._retained_entry, "query_aliases") {
      guard entry is Object(fields) &&
        fields.get("resource") is Some(String(resource)) else {
        stop("InvalidProjectBindings")
      }
      let mut selected = None
      for view in source._retained_declaration.views {
        if view.resource == resource {
          selected = Some(view)
        }
      }
      let view = selected.unwrap_or_else(() => stop("InvalidProjectBindings"))
      let projected : Map[String, Json] = Map([
        ("sourceRef", Json::string(view.source_ref)),
        ("sourceViewContractCid", Json::string(view.view_cid)),
        ("schemaContractCid", Json::string(view.carrier_schema_cid)),
      ])
      for key, value in fields {
        match key {
          "resource" => ()
          "name" | "request" => projected[key] = value
          _ => projected["public_input_field:" + key] = value
        }
      }
      result.push(Json::object(projected))
    }
  }
  result
}

///|
fn LocalProjectMockDeclarations::prepare_source_publication(
  self : Self,
  environment : @checked.CheckEnvironment,
) -> Result[
  (@source_publication.PreparedPublishedQueryEnvironment, String),
  LocalProjectMockModelIssue,
] {
  if self.closing || self.retired {
    return Err(ForeignOriginal)
  }
  guard self.model_environment is Some((_, original)) &&
    physical_equal(original, environment) else {
    return Err(ForeignOriginal)
  }
  if self.publication is Some((original, wire, prepared)) {
    return if physical_equal(original, environment) {
      Ok((prepared, wire))
    } else {
      Err(ForeignOriginal)
    }
  }
  let result = try {
    let body : Json = {
      "environmentCid": Json::string(
        @checked.checking_environment_cid(environment),
      ),
      "aliases": Json::array(self.source_aliases()),
      "updateTargets": Json::array(self.update_aliases()),
    }
    let wire = local_project_mock_relation_wire(body).unwrap_or_else(() => {
      stop("InvalidProjectBindings")
    })
    match
      @source_publication.prepare_published_query_environment(environment, wire) {
      Ok(value) => Ok((value, wire))
      Err(issue) => Err(Publication(issue))
    }
  } catch {
    _ => Err(Environment)
  }
  match result {
    Ok((prepared, wire)) =>
      self.publication = Some((environment, wire, prepared))
    Err(issue) => self.model_failure = Some(issue)
  }
  result
}

///|
fn local_command_project_publication(
  environment : @checked.CheckEnvironment,
) -> (@source_publication.PreparedPublishedQueryEnvironment, String) raise ClientStop {
  if command_preparation_invocation.val is Some(original) &&
    original.project is Some(project) &&
    project.mock_declarations is Some(mock) {
    if original.closing || original.closed {
      stop("LocalBusinessOriginalUnavailable")
    }
    match mock.prepare_source_publication(environment) {
      Ok(value) => return value
      Err(issue) => {
        original.retain_primary(CommandProjectMock(issue))
        stop("InvalidProjectBindings")
      }
    }
  }
  let wire = "{\"environmentCid\":\"" +
    @checked.checking_environment_cid(environment) +
    "\",\"aliases\":[]}"
  let prepared = @source_publication.prepare_published_query_environment(
    environment, wire,
  ).unwrap_or_else(() => stop("InvalidLocalQueryContext"))
  (prepared, wire)
}
