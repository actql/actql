///|
/// Internal context binding material from the admitted checker owner. Source
/// inventories remain private; the Host binds only aliases authorized for the
/// caller separately. ModelTask contracts have their existing installed scope.
/// This observation performs no checking and grants no execution authority.
#export_name("clientProgramCheckContextIdentity")
pub fn client_program_check_context_identity(
  environment : @program_check.CheckEnvironment,
) -> String {
  let wire = @program_check.checking_environment_wire(environment)
  let profiles = @program_check.checking_environment_profile_selection(
    environment,
  )
  try {
    // The admitted wire is bounded to 65,536 bytes and 4,096 nodes. Reserve
    // separate output overhead for the selected profiles and context wrapper.
    let writer = @encode.writer(131072, 8192, 64)
    @encode.begin_object(writer)
    @encode.key(writer, "host_policy_profile")
    @check_environment.emit_host_policy(wire, writer)
    @encode.key(writer, "model_task_contract_cids")
    @encode.begin_array(writer)
    if @program_check.checking_environment_model_tasks(environment)
      is Some(tasks) {
      let selected = @check_environment.model_tasks_environment(tasks)
      for
        index in 0..<@check_environment.member_count(
          selected,
          ModelTaskContracts,
        ) {
        let entry = @check_environment.member_at(
          selected,
          ModelTaskContracts,
          index,
        ).unwrap()
        @encode.string_value(writer, @check_environment.member_cid(entry))
      }
    }
    @encode.end_array(writer)
    @encode.key(writer, "profiles")
    @encode.begin_object(writer)
    @encode.key(writer, "calendar")
    @encode.bool_value(writer, profiles.operations.calendar)
    @encode.key(writer, "calendar_profile_cid")
    check_context_optional_cid(writer, profiles.calendar_profile_cid)
    @encode.key(writer, "model_tasks")
    @encode.bool_value(writer, profiles.model_tasks)
    @encode.key(writer, "numeric_profile_cid")
    check_context_optional_cid(writer, profiles.numeric_profile_cid)
    @encode.key(writer, "graph")
    @encode.bool_value(writer, profiles.graph)
    @encode.key(writer, "graph_law_cid")
    check_context_optional_cid(
      writer,
      if profiles.graph {
        Some(@graph_contract.law_cid())
      } else {
        None
      },
    )
    @encode.key(writer, "rela")
    @encode.bool_value(writer, profiles.operations.rela)
    @encode.key(writer, "sga")
    @encode.bool_value(writer, profiles.operations.sga)
    @encode.key(writer, "tea")
    @encode.bool_value(writer, profiles.operations.tea)
    @encode.key(writer, "text_rank")
    @encode.bool_value(writer, profiles.operations.text_rank)
    @encode.key(writer, "text_rank_profile_cid")
    check_context_optional_cid(writer, profiles.text_rank_profile_cid)
    @encode.key(writer, "text_time")
    @encode.bool_value(writer, profiles.expressions.text_time)
    @encode.key(writer, "veca")
    @encode.bool_value(writer, profiles.expressions.veca)
    @encode.end_object(writer)
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => abort("CheckContextIdentityEncoding")
  }
}

///|
fn check_context_optional_cid(
  writer : @encode.Writer,
  value : String?,
) -> Unit raise @encode.EncodeFailure {
  match value {
    Some(cid) => @encode.string_value(writer, cid)
    None => @encode.null_value(writer)
  }
}
