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

///|
// Actual compiled native originals/semantic functions. The limits constructor
// and namespace envelope are explicit DATA ports, not installed namespace ABI,
// Account authorization, Form HTTP, current backing or ordinary acceptance.
extern "js" fn create_standard_form_check(
  loader : CreateStandardLoader,
  mapping : RecordCreateMapping,
  declaration : RecordDeclaration,
  request : @catalog.RecordCreateRequest,
  batch : @catalog.RecordCreateRequest,
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
  mutation_limits : () -> @catalog.RecordMutationLimits,
  app : (@catalog.RecordCreateRequest) -> String,
  count : (@catalog.RecordCreateRequest) -> Int,
  form_limits : () -> @catalog.FormFieldLimits,
  recheck : (@catalog.RecordCreateRequest, Bytes, @catalog.FormFieldLimits) -> Result[
    Unit,
    @catalog.RecordMutationIssue,
  ],
) -> Bool =
  #|(loader,mapping,declaration,request,batch,mappingDeclaration,mappingRequest,execution,writeLimits,mutationLimits,app,count,formLimits,recheck) => {
  #| const {prepareMappedKintoneCreateFormCheck:prepare}=loader('../../../../../../../adapters/connectors/kintone/site/kintone-create-execution.mjs');
  #| const moon={clientProgramKintoneCreateMappingMatchesDeclaration:mappingDeclaration,clientProgramKintoneCreateMappingMatchesRequest:mappingRequest,
  #|   clientProgramKintoneCreateExecutionRequest:execution,clientProgramKintoneWriteLimits:writeLimits,clientProgramKintoneMutationLimits:mutationLimits,
  #|   clientProgramKintoneCreateApp:app,clientProgramKintoneCreateCount:count,clientProgramKintoneFormLimits:formLimits,clientProgramKintoneCreateRecheckForm:recheck};
  #| const limits={maxRequestBytes:8192,maxResponseBytes:8192,maxNodes:1000,maxDepth:16,maxFields:16,maxNameUnits:512};
  #| const args={moon,mapping,declaration,request,limits},pair=prepare(args);
  #| if(!Object.isFrozen(pair)||pair.body!=='{"app":"12"}')return false;
  #| const bytes=Buffer.from('{"revision":"7","properties":{"Subject":{"code":"Subject","type":"SINGLE_LINE_TEXT","expression":"","required":true,"defaultValue":"server"},"Tags":{"code":"Tags","type":"MULTI_SELECT","required":false,"defaultValue":["server"]},"Optional":{"code":"Optional","type":"MULTI_LINE_TEXT","required":false,"defaultValue":"server"},"Computed":{"code":"Computed","type":"SINGLE_LINE_TEXT","expression":"\\"server\\"","required":true}}}');
  #| moon.clientProgramKintoneCreateRecheckForm=()=>{throw new Error('later method replacement');};
  #| if(pair.project({statusCode:200,body:bytes})!==undefined)return false;
  #| for(const [observation,code] of [[{statusCode:201,body:bytes},'KintoneWriteReadRejected'],[{statusCode:200,body:Buffer.alloc(8193)},'InvalidKintoneCreateFormObservation']]){
  #|   let refused=false;try{pair.project(observation);}catch(error){refused=error.code===code;}if(!refused)return false;
  #| }
  #| let drift=false;try{pair.project({statusCode:200,body:Buffer.from(bytes.toString().replace('"revision":"7"','"revision":"8"'))});}catch{drift=true;}if(!drift)return false;
  #| for(const change of [{request:batch},{request:{...request}},{mapping:{...mapping}}]){
  #|   let refused=false;try{prepare({...args,...change});}catch{refused=true;}if(!refused)return false;
  #| }
  #| return true;
  #| }

///|
test "pure CREATE Form request projection retains actual native originals without HTTP or grant" {
  let declaration = create_mapping_declaration(create_mapping_catalog())
  let mapping = prepare_record_create_mapping(
    declaration,
    "inquiries",
    create_mapping_sources(),
    "required",
    delete_declaration_limits(),
  ).unwrap()
  let write = create_construction_write(16)
  let mutation = create_construction_request()
  let request = prepare_record_create_execution_request(
    mapping, b"[{\"Subject\":\"intended\",\"Tags\":[\"red\"]}]", 8192, write, mutation,
  ).unwrap()
  let values = @catalog.record_create_request_values(request)[0]
  let batch = @catalog.prepare_record_create_request(
    declaration.catalog,
    [values, values],
    { ..mutation, max_records: 2, },
  ).unwrap()
  assert_true(
    create_standard_form_check(
      create_standard_loader(create_standard_url()),
      mapping,
      declaration,
      request,
      batch,
      record_create_mapping_matches_declaration,
      record_create_mapping_matches_request,
      prepare_record_create_execution_request,
      () => write,
      () => mutation,
      @catalog.record_create_request_app_id,
      @catalog.record_create_request_count,
      () => create_protocol_form_limits(),
      @catalog.recheck_record_create_form,
    ),
  )
}

///|
// Actual compiled native semantics and complete standard mapper/recovery body.
// Namespace and limit constructors are explicit DATA ports. No Account, grant,
// Resource call, durable claim, terminal settlement or normal backing is made.
extern "js" fn standard_create_declaration(
  loader : CreateStandardLoader,
  mapping : RecordCreateMapping,
  declaration : RecordDeclaration,
  mapping_declaration : (RecordCreateMapping, RecordDeclaration) -> Bool,
  mapping_request : (RecordCreateMapping, @catalog.RecordCreateRequest) -> Bool,
  legacy_execution : (
    RecordCreateMapping,
    Bytes,
    Int,
    @catalog.RecordWriteLimits,
    @catalog.RecordMutationLimits,
  ) -> Result[@catalog.RecordCreateRequest, RecordCreateExecutionIssue],
  write_limits : (Int, Int, Int, Int, Int, Int) -> @catalog.RecordWriteLimits,
  mutation_limits : (Int, Int, Int, Int, Int, Int) -> @catalog.RecordMutationLimits,
  resource : (RecordCreateMapping) -> Result[String, RecordCreateExecutionIssue],
  prepare : (
    RecordCreateMapping,
    Bytes,
    Int,
    @catalog.RecordWriteLimits,
    @catalog.RecordMutationLimits,
  ) -> Result[@catalog.RecordCreateRequest, RecordCreateExecutionIssue],
  restore : (
    RecordCreateMapping,
    Bytes,
    String,
    Int,
    @catalog.RecordWriteLimits,
    @catalog.RecordMutationLimits,
  ) -> Result[@catalog.RecordCreateRequest, RecordCreateExecutionIssue],
  body : (@catalog.RecordCreateRequest) -> String,
  app : (@catalog.RecordCreateRequest) -> String,
  count : (@catalog.RecordCreateRequest) -> Int,
  form_limits : (Int, Int, Int, Int, Int) -> @catalog.FormFieldLimits,
  recheck : (@catalog.RecordCreateRequest, Bytes, @catalog.FormFieldLimits) -> Result[
    Unit,
    @catalog.RecordMutationIssue,
  ],
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
  #|(loader,mapping,declaration,mapping_declaration,mapping_request,legacy_execution,write_limits,mutation_limits,resource,prepare,restore,body,app,count,form_limits,recheck,response,outcome,wire,digest,matches) => {
  #| const assert=loader('node:assert/strict'),fs=loader('node:fs'),crypto=loader('node:crypto'),types=loader('node:util').types;
  #| const site=loader('../../../../../../../adapters/connectors/kintone/site/kintone-create-execution.mjs');
  #| const own=loader('../../../../../../../adapters/host-common/http-exchange.mjs'),invocation=loader('../../../../../../../adapters/host-common/owned-invocation-context.mjs');
  #| const local=loader('../../../../../../../adapters/host-node/local-values-plan.mjs');
  #| const source=fs.readFileSync(loader.resolve('../../../../../../../adapters/host-node/installed-row-effect.mjs'),'utf8');
  #| const start=source.indexOf('function deriveInstalledRowWrite('),end=source.indexOf('\nfunction prepareInstalledCreateRows(',start);
  #| assert(start>=0&&end>start);
  #| const derive=Function('createHash','nodeTypes','ownHttpRequest','ownRequestHeaders','ownResponseHeaderNames','invokeScopedCredentialOperation','localContractLimits','return ('+source.slice(start,end)+');')(crypto.createHash,types,own.ownHttpRequest,own.ownRequestHeaders,own.ownResponseHeaderNames,invocation.invokeScopedCredentialOperation,local.localContractLimits);
  #| let prepares=0,restores=0;
  #| const moon={clientProgramKintoneCreateMappingMatchesDeclaration:mapping_declaration,clientProgramKintoneCreateMappingMatchesRequest:mapping_request,
  #| clientProgramKintoneCreateExecutionRequest:legacy_execution,clientProgramKintoneWriteLimits:write_limits,clientProgramKintoneMutationLimits:mutation_limits,
  #| clientProgramKintoneCreateMappingResource:resource,clientProgramKintonePrepareCreateExecutionProposal:function(...args){assert.equal(this,moon);prepares++;return prepare(...args);},
  #| clientProgramKintoneRestoreCreateExecutionProposal:function(...args){assert.equal(this,moon);restores++;return restore(...args);},
  #| clientProgramKintoneCreateBody:body,clientProgramKintoneCreateApp:app,clientProgramKintoneCreateCount:count,clientProgramKintoneFormLimits:form_limits,
  #| clientProgramKintoneCreateRecheckForm:recheck,clientProgramKintoneCreateResponse:response,clientProgramKintoneCreateEffectOutcome:outcome,
  #| clientProgramKintoneCreateEffectOutcomeWire:wire,clientProgramKintoneCreateEffectOutcomeResponseSha256:digest,clientProgramKintoneCreateEffectOutcomeMatchesRequest:matches};
  #| const limits={maxInputBytes:8192,maxRequestBytes:8192,maxResponseBytes:8192,maxNodes:1000,maxDepth:16,maxFields:16,maxNameUnits:512,maxRows:1,maxIdentityBytes:1000,maxComparisonWork:10000};
  #| const args={moon,mapping,declaration,resource:'inquiries',formResource:'forms',origin:'https://tenant.example.test',boundaryCid:'sha256:'+'b'.repeat(64),limits};
  #| const write=site.createMappedKintoneCreateWrite(args),driver=derive(write,'kintone').driver;
  #| const proposalWire='{"state":"present","value":{"Subject":"next 東京","Tags":["red","red"]}}',value=JSON.parse(proposalWire).value;
  #| const member=Object.freeze({kind:'create',resource:'inquiries'}),prepared=driver.prepareRequest({member,value,proposalWire});
  #| assert.equal(prepared.request.body,'{"app":"12","records":[{"Subject":{"value":"next 東京"},"Tags":{"value":["red","red"]}}]}');
  #| assert.equal(prepared.request.proposalWire,proposalWire);assert.equal(driver.requestFacts(prepared.request).value,value);assert.equal(prepares,1);
  #| const saved=driver.recoveryEntry({member,entries:[{...prepared,value}]}),coldWrite=site.createMappedKintoneCreateWrite(args),cold=derive(coldWrite,'kintone').driver;
  #| moon.clientProgramKintonePrepareCreateExecutionProposal=()=>{throw new Error('later export replacement');};
  #| const restored=cold.recoverRequests({members:[member],durable:{connectorRecovery:[{...saved,memberIndex:0}]}}).requests[0][0];
  #| assert.equal(cold.requestCid(restored),prepared.requestCid);assert.equal(restored.body,prepared.request.body);assert.equal(prepares,1);assert.equal(restores,0);
  #| const restoredValue=cold.requestFacts(restored).value,context={resource:'forms',value:restoredValue,request:restored};
  #| assert.equal(coldWrite.check.body(context),'{"app":"12"}');assert.equal(restores,1);assert.equal(prepares,1);
  #| const form=Buffer.from('{"revision":"7","properties":{"Subject":{"code":"Subject","type":"SINGLE_LINE_TEXT","expression":"","required":true,"defaultValue":"server"},"Tags":{"code":"Tags","type":"MULTI_SELECT","required":false,"defaultValue":["server"]},"Optional":{"code":"Optional","type":"MULTI_LINE_TEXT","required":false,"defaultValue":"server"},"Computed":{"code":"Computed","type":"SINGLE_LINE_TEXT","expression":"\\"server\\"","required":true}}}');
  #| assert.equal(coldWrite.check.project({...context,observation:{statusCode:200,body:form}}),undefined);
  #| const projected=cold.project({request:restored,observation:{statusCode:200,body:Buffer.from('{"ids":["9007199254740993"],"revisions":["0007"]}')}});
  #| assert.equal(JSON.stringify(projected.outcome),'{"result":{"created":true,"record_id":"9007199254740993","revision":"0007"},"state":"applied"}');
  #| assert.equal(prepares,1);assert.equal(restores,1);
  #| for(const change of [{resource:'foreign'},{mapping:{...mapping}},{limits:{...limits,maxRows:2}}])assert.throws(()=>site.createMappedKintoneCreateWrite({...args,...change}));
  #| assert.throws(()=>write.request({resource:'inquiries',value}),{code:'KintoneCreateProposalLimit'});
  #| assert.throws(()=>write.request({resource:'inquiries',value,proposalWire:'x'.repeat(8193)}),{code:'KintoneCreateProposalLimit'});
  #| assert.equal(prepares,1);assert.equal(restores,1);
  #| const changed=Object.freeze({...restored,body:restored.body.replace('next 東京','foreign')});
  #| assert.throws(()=>coldWrite.check.body({...context,request:changed}));assert.equal(prepares,1);
  #| return true;
  #| }

///|
test "standard CREATE declaration consumes original change wire and cold native restoration without fresh prepare" {
  let declaration = create_mapping_declaration(create_mapping_catalog())
  let mapping = prepare_record_create_mapping(
    declaration,
    "inquiries",
    create_mapping_sources(),
    "required",
    delete_declaration_limits(),
  ).unwrap()
  assert_true(
    standard_create_declaration(
      create_standard_loader(create_standard_url()),
      mapping,
      declaration,
      record_create_mapping_matches_declaration,
      record_create_mapping_matches_request,
      prepare_record_create_execution_request,
      (fields, names, nodes, depth, text, output) => {
        max_fields: fields,
        max_name_bytes: names,
        max_nodes: nodes,
        max_depth: depth,
        max_text_bytes: text,
        max_output_bytes: output,
      },
      (rows, identity, work, bytes, nodes, depth) => {
        max_records: rows,
        max_identity_bytes: identity,
        max_comparison_work: work,
        max_output_bytes: bytes,
        max_output_nodes: nodes,
        max_output_depth: depth,
      },
      record_create_mapping_resource,
      prepare_record_create_execution_proposal,
      restore_record_create_execution_proposal,
      @catalog.record_create_request_body,
      @catalog.record_create_request_app_id,
      @catalog.record_create_request_count,
      (bytes, nodes, depth, fields, names) => {
        max_bytes: bytes,
        max_nodes: nodes,
        max_depth: depth,
        max_fields: fields,
        max_name_units: names,
      },
      @catalog.recheck_record_create_form,
      @catalog.project_record_create_acknowledgement,
      @catalog.project_record_create_effect_outcome,
      @catalog.record_create_effect_outcome_wire,
      @catalog.record_create_effect_outcome_response_sha256,
      @catalog.record_create_effect_outcome_matches_request,
    ),
  )
}
