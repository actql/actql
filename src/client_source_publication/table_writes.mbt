///|
/// Original installed Table-write publication, shared by check and preparation.
/// This binds static metadata only; it issues no capture or write permission.
pub fn published_table_writes(
  environment : @program_check.CheckEnvironment,
  publication : String,
) -> Result[Array[@query_program.TableWriteBinding], PublicationIssue] {
  Ok(table_write_publication(environment, publication)) catch {
    PublicationStop(issue) => Err(issue)
  }
}

///|
// Published by installed Effect owners only. Resolving a Table name must not
// reuse read aliases or derive a write grant from Source acquisition metadata.
fn table_write_publication(
  environment : @program_check.CheckEnvironment,
  publication : String,
) -> Array[@query_program.TableWriteBinding] raise PublicationStop {
  let root = source_publication_cursor(publication)
  table_write_publication_from_root(environment, root)
}

///|
fn table_write_publication_from_root(
  environment : @program_check.CheckEnvironment,
  root : @decode.Cursor,
) -> Array[@query_program.TableWriteBinding] raise PublicationStop {
  if source_publication_text(root, "environmentCid") !=
    @program_check.checking_environment_cid(environment) {
    raise PublicationStop(Publication)
  }
  let object = @decode.closed_object(root, [
    "environmentCid", "aliases", "tableWrites", "updateTargets", "storeTargets",
    "commandTargets",
  ]).unwrap_or_else(() => raise PublicationStop(Publication))
  guard @decode.lookup(object, "tableWrites") is Some(section) else {
    return []
  }
  let entries = @decode.elements(section).unwrap_or_else(() => {
    raise PublicationStop(Publication)
  })
  if entries.length() > 1024 {
    raise PublicationStop(Limit)
  }
  if entries.is_empty() {
    return []
  }
  let mappings = @check_environment.check_mapping_contract_shapes(
    @program_check.checking_environment_wire(environment),
    { max_bytes: 1048576, max_nodes: 16384, max_depth: 32, max_members: 32768, },
    1000000,
  ).unwrap_or_else(() => raise PublicationStop(Publication))
  let bindings : Array[@query_program.TableWriteBinding] = []
  for entry in entries {
    let entry_object = @decode.closed_object(entry, [
      "name", "targetRef", "mappingRef", "mappingCid", "capabilityCid", "installationBindingCid",
      "action", "expectedTable",
    ]).unwrap_or_else(() => raise PublicationStop(Publication))
    let name = @query_syntax.parse_relation_path(
      source_publication_text(entry, "name"),
      {
        max_source_bytes: 1024,
        max_tokens: 256,
        max_literal_bytes: 1024,
        max_work: 16384,
      },
    ).unwrap_or_else(() => raise PublicationStop(Publication))
    let mapping_ref = source_publication_text(entry, "mappingRef")
    let mapping = @check_environment.mapping_shape_for(mappings, mapping_ref).unwrap_or_else(() => {
        raise PublicationStop(Publication)
      },
    )
    let target_ref = source_publication_text(entry, "targetRef")
    let mapping_cid = source_publication_text(entry, "mappingCid")
    if @check_environment.mapping_shape_target(mapping) != target_ref ||
      @check_environment.mapping_shape_cid(mapping) != mapping_cid {
      raise PublicationStop(Publication)
    }
    // CREATE deliberately binds absence as explicit NULL. Required non-null
    // field access would conflate that valid action with missing metadata.
    let expected = @decode.lookup(entry_object, "expectedTable").unwrap_or_else(() => {
        raise PublicationStop(Publication)
      },
    )
    let action : @query_program.TableWriteAction = match
      source_publication_text(entry, "action") {
      "create" => {
        if !(@decode.view(expected) is @decode.NullValue) {
          raise PublicationStop(Publication)
        }
        @query_program.Create
      }
      "replace" => {
        @decode.closed_object(expected, ["table_uuid", "generation_cid"]).unwrap_or_else(() => {
            raise PublicationStop(Publication)
          },
        )
        |> ignore
        @query_program.Replace(
          source_publication_text(expected, "table_uuid"),
          source_publication_text(expected, "generation_cid"),
        )
      }
      _ => raise PublicationStop(Publication)
    }
    bindings.push({
      name,
      target_ref,
      mapping_ref,
      mapping_cid,
      capability_cid: source_publication_text(entry, "capabilityCid"),
      installation_binding_cid: source_publication_text(
        entry, "installationBindingCid",
      ),
      action,
    })
  }
  // The lowerer's bounded validator also rejects invalid metadata outside the
  // selected name. Ambiguity is an authored resolution error at check time.
  for binding in bindings {
    match
      @query_program.resolve_table_write_binding(
        [binding],
        binding.name,
        true,
        1000000,
      ) {
      Ok(_) => ()
      Err(_) => raise PublicationStop(Publication)
    }
  }
  bindings
}
