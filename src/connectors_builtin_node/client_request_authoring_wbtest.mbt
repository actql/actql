///|
extern "js" fn original_node_authoring_runtime_view(
  loader : RequestDiagnosticTestLoader,
  prepared : @publication_host.PreparedClientProgram,
  original : @publication_host.ClientAuthoringContextPreparation,
  expected : @publication.RunEvidenceValue,
  project : (
    @publication_host.PreparedClientProgram,
    @publication_host.ClientAuthoringContextPreparation,
    Int,
    Int,
    Int,
  ) -> Result[
    @publication.RunEvidenceValue,
    @publication_host.ClientAuthoringContextIssue,
  ],
  name : (@publication.RunEvidenceValue) -> String,
  identity : (@publication.RunEvidenceValue) -> String,
  wire : (@publication.RunEvidenceValue) -> String,
  remote_kind : () -> String,
) -> Bool =
  #|(loader,prepared,original,expected,project,name,identity,wire,remoteKind)=>{const {runtimeCore}=loader('../../../../../adapters/host-common/runtime-core.mjs');let calls=0;const moon={strategyRemoteManagedOutputEvidenceKind:remoteKind,clientProgramPreparedAuthoringContextEvidence(actual,proof,...bounds){if(this!==moon||actual!==prepared||proof!==original)throw Error('ForeignAuthoringOriginal');calls++;return project(actual,proof,...bounds);},strategyRunEvidenceName:name,strategyRunEvidenceIdentity:identity,strategyRunEvidenceJson:wire};const control=runtimeCore(moon).publicationControl;const limits={maxWireBytes:1000000,maxNodes:100000,maxDepth:64};const view=control.preparedClientAuthoringContextEvidence(prepared,original,limits);let missing=false;try{control.preparedClientAuthoringContextEvidence(prepared,undefined,limits);}catch(error){missing=error.message==='OriginalClientAuthoringContextRequired';}return missing&&calls===1&&Object.isFrozen(view)&&view.name===name(expected)&&view.identity===identity(expected)&&view.wire===wire(expected);}

///|
test "Node authoring bridge and imported Runtime read the same issued Request original without reissue" {
  let (parent, input) = original_node_normalization_parent()
  client_program_prepare_request_program_normalization(parent, input).unwrap()
  |> ignore
  let original = client_program_prepare_request_program_authoring_context(
    parent, input,
  ).unwrap()
  assert_true(
    physical_equal(
      original,
      client_program_prepare_request_program_authoring_context(parent, input).unwrap(),
    ),
  )
  let holder = client_program_borrow_request_program_plan_input(parent, input).unwrap()
  let prepared = client_program_preparation_borrow_read(holder).unwrap()
  let expected = @publication_host.prepared_client_authoring_context_evidence(
    prepared, original, 1000000, 100000, 64,
  ).unwrap()
  let actual = client_program_prepared_authoring_context_evidence(
    prepared, original, 1000000, 100000, 64,
  ).unwrap()
  assert_true(physical_equal(actual, expected))
  assert_true(
    original_node_authoring_runtime_view(
      request_diagnostic_test_loader(request_diagnostic_test_url()),
      prepared,
      original,
      expected,
      (owner, proof, bytes, nodes, depth) => {
        client_program_prepared_authoring_context_evidence(
          owner, proof, bytes, nodes, depth,
        )
      },
      value => @publication.run_evidence_value_name(value),
      value => @publication.run_evidence_value_identity(value),
      value => @publication.run_evidence_value_json(value),
      () => strategy_remote_managed_output_evidence_kind(),
    ),
  )
  assert_true(
    client_program_prepare_request_program_authoring_context(parent, input)
    is Err(Preparation(WrongPhase)),
  )
  ignore(client_program_abort_request_preparation(parent))
  assert_true(client_program_preparation_borrow_retirement_started(holder))
  ignore(client_program_preparation_borrow_return(holder).unwrap())
  client_program_abort_request_preparation(parent).unwrap()
}
