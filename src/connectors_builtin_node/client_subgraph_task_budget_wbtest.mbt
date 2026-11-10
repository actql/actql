///|
// Original fixture DATA only. The larger source remains byte-exact when its
// stale refusal is moved to the success collection.
extern "js" fn request_subgraph_task_captured(
  loader : RequestDiagnosticTestLoader,
  name : String,
) -> NativeJsonValue =
  #|(loader,name)=>{const f=loader('../../../../../scripts/fixtures/subgraph-source-input.mjs');const item=[...f.subgraphSourceSuccesses,...f.subgraphSourceRefusals].find(x=>x.name===name);if(!item)throw new Error('MissingOriginalSubgraphTaskFixture');return {kind:'aql',input:{format:item.format,text:item.text},parameters:null};}

///|
fn request_subgraph_task_count(name : String, max_tasks : Int?) -> Int? raise {
  let loader = request_diagnostic_test_loader(request_diagnostic_test_url())
  // Same existing Graph policy as the ordinary Node default composition.
  let environment = @publication_host.admit_client_check_environment(
    node_closed_carrier_demand_environment,
    "sha256:65b8e4316a5fdf0a0e8d67a38d8d676e915653929bfe1ecdc64d823d177c9261",
    { text_time: true, veca: true, },
    { rela: true, sga: true, tea: true, calendar: false, text_rank: false, },
    numeric_profile_cid=Some(
      "sha256:d771391b2e4f3e52a3cf48810571a09c6c272df64fbb77c245dfabcf456be5df",
    ),
    graph=true,
  ).unwrap()
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" +
    @program_check.checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).unwrap()
  let (parent, receipt) = request_diagnostic_test_parent()
  let captured = request_subgraph_task_captured(loader, name)
  client_program_prepare_request_submitted_intent(parent, receipt, captured).unwrap()
  |> ignore
  client_program_finish_request_submitted_intent(parent, receipt).unwrap()
  let source = request_subgraph_original_fixture_source(captured)
  let checked = match max_tasks {
    None =>
      client_program_prepare_request_source_computation(
        parent,
        receipt,
        source,
        request_diagnostic_test_json("null"),
        environment,
        publication,
        None,
      )
    Some(max_tasks) => {
      // Existing explicit-limit entry, same Source/check/compiler Owner.
      // Standard work, bytes and all unrelated configuration remain exact.
      let limits = {
        ..@publication_host.client_standard_program_preparation_limits(),
        max_tasks,
      }
      @client_local_host.prepare_request_native_source_computation_check(
        parent,
        receipt,
        source,
        native_json_reader,
        environment,
        publication,
        [],
        limits,
        @publication_host.client_standard_effect_computation_limits(),
      )
    }
  }
  let result = match checked {
    Ok(_) =>
      client_program_finish_request_computation(
        parent, receipt, environment, publication,
      )
    Err(issue) => Err(issue)
  }
  match result {
    Ok(kind) => {
      assert_eq(kind, "effect_free")
      let holder = client_program_borrow_request_program_plan_input(
        parent, receipt,
      ).unwrap()
      let prepared = client_program_preparation_borrow_read(holder).unwrap()
      let count = client_program_task_count(prepared)
      assert_false(client_program_preparation_borrow_return(holder).unwrap())
      client_program_abort_request_preparation(parent).unwrap()
      Some(count)
    }
    Err(issue) => {
      let exact_task_budget = issue
        is Preparation(ProgramCheck(Compilation(Graph(TaskLimit))))
      let cause = match issue {
        CheckOutcome(Rejected(diagnostic)) =>
          "check/" +
          @program_check.diagnostic_category(diagnostic).to_repr().to_string()
        CheckOutcome(NeedsInputs(_)) => "needs_inputs"
        CheckOutcome(_) => "check_other"
        Preparation(ProgramCheck(Compilation(Graph(_)))) => "compilation_graph"
        Preparation(ProgramCheck(Compilation(_))) => "compilation_other"
        Preparation(ProgramCheck(_)) => "program_check"
        Preparation(_) => "preparation"
        QueryLowering(_) => "query_lowering"
        QuerySyntax(_) => "query_syntax"
        Publication(_) => "publication"
      }
      client_program_abort_request_preparation(parent).unwrap()
      assert_true(exact_task_budget, msg="OriginalSubgraphBudgetCause:" + cause)
      None
    }
  }
}

///|
test "published Subgraph count boundaries use the actual finite standard and selected one-short budgets" {
  let limits = @publication_host.client_standard_program_preparation_limits()
  assert_eq(limits.max_tasks, limits.max_graph_work)
  assert_eq(limits.max_graph_work, 1000000)
  for name in ["subgraph-task-profile-bound", "subgraph-inline-node-subset"] {
    let count = request_subgraph_task_count(name, None).unwrap()
    assert_true(count > 0 && count <= limits.max_tasks)
    println("SubgraphTaskBudget " + name + " tasks=" + count.to_string())
    assert_eq(request_subgraph_task_count(name, Some(count)), Some(count))
    assert_eq(request_subgraph_task_count(name, Some(count - 1)), None)
  }
}
