///|
#external
priv type CreateStandardLoader

///|
#module("node:module")
extern "js" fn create_standard_loader(url : String) -> CreateStandardLoader = "createRequire"

///|
extern "js" fn create_standard_url() -> String =
  #|() => import.meta.url

///|
// Execute the new Site facade with original compiled Catalog functions. The
// local limits constructors are explicit DATA ports; this is not the generated
// Node namespace, a normal Host, authorization, Preview or physical operation.
extern "js" fn create_standard_projection(
  loader : CreateStandardLoader,
  mapping : RecordCreateMapping,
  declaration : RecordDeclaration,
  request : @catalog.RecordCreateRequest,
  mapping_declaration : (RecordCreateMapping, RecordDeclaration) -> Bool,
  mapping_request : (RecordCreateMapping, @catalog.RecordCreateRequest) -> Bool,
  execution : (
    RecordCreateMapping,
    Bytes,
    Int,
    @catalog.RecordWriteLimits,
    @catalog.RecordMutationLimits,
  ) -> Result[@catalog.RecordCreateRequest, RecordCreateExecutionIssue],
  write_limits : () -> @catalog.RecordWriteLimits,
  mutation_limits : (Int, Int, Int, Int, Int, Int) -> @catalog.RecordMutationLimits,
  response : (
    @catalog.RecordCreateRequest,
    Int,
    Bytes,
    @catalog.RecordMutationLimits,
  ) -> Result[
    @catalog.RecordCreateAcknowledgement,
    @catalog.RecordMutationIssue,
  ],
  outcome : (
    @catalog.RecordCreateRequest,
    @catalog.RecordCreateAcknowledgement,
    @catalog.RecordMutationLimits,
  ) -> Result[@catalog.RecordCreateEffectOutcome, @catalog.RecordMutationIssue],
  wire : (@catalog.RecordCreateEffectOutcome) -> String,
  digest : (@catalog.RecordCreateEffectOutcome) -> String,
  matches : (@catalog.RecordCreateEffectOutcome, @catalog.RecordCreateRequest) -> Bool,
) -> Bool =
  #|(loader,mapping,declaration,request,mappingDeclaration,mappingRequest,execution,writeLimits,mutationLimits,response,outcome,wire,digest,matches) => {
  #| const {projectMappedKintoneCreateResponseOutcome:project}=loader('../../../../../../../adapters/connectors/kintone/site/kintone-create-execution.mjs');
  #| const moon={clientProgramKintoneCreateMappingMatchesDeclaration:mappingDeclaration,clientProgramKintoneCreateMappingMatchesRequest:mappingRequest,
  #|   clientProgramKintoneCreateExecutionRequest:execution,clientProgramKintoneWriteLimits:writeLimits,clientProgramKintoneMutationLimits:mutationLimits,
  #|   clientProgramKintoneCreateResponse:response,clientProgramKintoneCreateEffectOutcome:outcome,clientProgramKintoneCreateEffectOutcomeWire:wire,
  #|   clientProgramKintoneCreateEffectOutcomeResponseSha256:digest,clientProgramKintoneCreateEffectOutcomeMatchesRequest:matches};
  #| const body=Buffer.from('{"ids":["9007199254740993"],"revisions":["0009007199254740994"]}');
  #| const limits={maxResponseBytes:8192,maxNodes:1000,maxDepth:16,maxRows:1,maxIdentityBytes:1000,maxComparisonWork:10000};
  #| const args={moon,mapping,declaration,request,observation:{statusCode:200,body},limits};
  #| const actual=project(args);
  #| const expected='{"result":{"created":true,"record_id":"9007199254740993","revision":"0009007199254740994"},"state":"applied"}';
  #| if(actual.kind!=='typed-success-response'||JSON.stringify(actual.outcome)!==expected||!matches(actual.projected,request)||!Object.isFrozen(actual))return false;
  #| if(actual.responseSha256!==loader('node:crypto').createHash('sha256').update(body).digest('hex'))return false;
  #| for(const change of [{request:{...request}},{mapping:{...mapping}},{observation:{statusCode:201,body}},{observation:{statusCode:200,body:Buffer.from('{"ids":["1"],"revisions":[]}')}}]){
  #|   let refused=false;try{project({...args,...change});}catch{refused=true;}if(!refused)return false;
  #| }
  #| return true;
  #| }

///|
test "standard CREATE Site outcome uses the same actual native Mapping request and acknowledgement" {
  let declaration = create_mapping_declaration(create_mapping_catalog())
  let mapping = prepare_record_create_mapping(
    declaration,
    "inquiries",
    create_mapping_sources(),
    "required",
    delete_declaration_limits(),
  ).unwrap()
  let write : @catalog.RecordWriteLimits = {
    max_fields: 16,
    max_name_bytes: 512,
    max_nodes: 1000,
    max_depth: 16,
    max_text_bytes: 8192,
    max_output_bytes: 8192,
  }
  let mutation : @catalog.RecordMutationLimits = {
    max_records: 1,
    max_identity_bytes: 1000,
    max_comparison_work: 10000,
    max_output_bytes: 8192,
    max_output_nodes: 1000,
    max_output_depth: 16,
  }
  let request = prepare_record_create_execution_request(
    mapping, b"[{\"Subject\":\"requested 東京\",\"Tags\":[\"red\",\"red\"]}]",
    8192, write, mutation,
  ).unwrap()
  assert_true(
    create_standard_projection(
      create_standard_loader(create_standard_url()),
      mapping,
      declaration,
      request,
      record_create_mapping_matches_declaration,
      record_create_mapping_matches_request,
      prepare_record_create_execution_request,
      () => write,
      (records, identity, work, bytes, nodes, depth) => {
        max_records: records,
        max_identity_bytes: identity,
        max_comparison_work: work,
        max_output_bytes: bytes,
        max_output_nodes: nodes,
        max_output_depth: depth,
      },
      @catalog.project_record_create_acknowledgement,
      @catalog.project_record_create_effect_outcome,
      @catalog.record_create_effect_outcome_wire,
      @catalog.record_create_effect_outcome_response_sha256,
      @catalog.record_create_effect_outcome_matches_request,
    ),
  )
}
