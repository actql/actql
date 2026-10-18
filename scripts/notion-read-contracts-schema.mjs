import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';

const path='spec/contracts/actql-protocol-schemas.json';
const pointer='/schemas/notion_database_read_declaration';
const read=path=>JSON.parse(readFileSync(path,'utf8'));

// Configuration DATA, never an installation issuer or a second logical type
// grammar. Common checks the exact schema/occurrence/configuration originals.
export function notionReadDeclarationSchema(protocol){
  const checked=protocol.schemas.canonical_value_contract;
  const object=checked.$defs.value_contract.oneOf.find(x=>x.properties?.type?.const==='object');
  assert.ok(object,'existing checked object grammar');
  const text={type:'string',minLength:1};
  const column={type:'string',...structuredClone(object.properties.fields.propertyNames)};
  const entry={type:'object',additionalProperties:false,required:['column','projection','contract'],
    properties:{column,projection:{enum:['value','start','end']},contract:{$ref:'#/$defs/value_contract'}}};
  return {$schema:'https://json-schema.org/draft/2020-12/schema',oneOf:[text,
    {type:'object',additionalProperties:false,required:['id'],properties:{id:text,
      unique:text,marker:text,data_source_id:text,read_contracts:{type:'object',
        propertyNames:text,additionalProperties:{type:'array',minItems:1,maxItems:2,items:entry}}}}],
    $defs:structuredClone(checked.$defs)};
}

export function notionReadDeclarationsSchema(protocol){
  const {$schema,$defs,...declaration}=notionReadDeclarationSchema(protocol);
  return {$schema,type:'object',propertyNames:{type:'string',minLength:1},
    additionalProperties:declaration,$defs};
}

export function checkNotionReadDeclarationSchema(protocol){
  const schema=notionReadDeclarationSchema(protocol);
  assert.deepEqual(protocol.schemas.notion_database_read_declaration,schema);
  assert.equal(protocol.schema_cids.notion_database_read_declaration,machineCid(schema));
  const declarations=notionReadDeclarationsSchema(protocol);
  assert.deepEqual(protocol.schemas.notion_database_read_declarations,declarations);
  assert.equal(protocol.schema_cids.notion_database_read_declarations,machineCid(declarations));
  const snapshot=notionReadSnapshotSchema();
  assert.deepEqual(protocol.schemas.notion_database_read_snapshot,snapshot);
  assert.equal(protocol.schema_cids.notion_database_read_snapshot,machineCid(snapshot));
  assert.equal(protocol.registry_cid,machineCid(protocol.schemas));
}

// Exact saved Catalog DATA; the structural body is not authenticated custody,
// current authority, complete acquisition, an installed issuer or funding.
function notionReadSnapshotSchema(){
  const text={type:'string',minLength:1};
  return {$schema:'https://json-schema.org/draft/2020-12/schema',type:'object',
    additionalProperties:false,required:['database_response','declaration_source',
      'schema_cid','schema_wire','selected_data_source_response','system_columns','version'],
    properties:{database_response:text,declaration_source:text,
      schema_cid:{type:'string',pattern:'^sha256:[0-9a-f]{64}$'},schema_wire:text,
      selected_data_source_response:text,system_columns:{type:'boolean'},
      version:{const:'actql-notion-database-read-snapshot/0.1'}}};
}

if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
  const protocol=read(path);
  if(process.argv.includes('--write')){
    const schema=notionReadDeclarationSchema(protocol),cid=machineCid(schema);
    protocol.schemas.notion_database_read_declaration=schema;
    protocol.schema_cids.notion_database_read_declaration=cid;
    const declarations=notionReadDeclarationsSchema(protocol);
    protocol.schemas.notion_database_read_declarations=declarations;
    protocol.schema_cids.notion_database_read_declarations=machineCid(declarations);
    const snapshot=notionReadSnapshotSchema();
    protocol.schemas.notion_database_read_snapshot=snapshot;
    protocol.schema_cids.notion_database_read_snapshot=machineCid(snapshot);
    protocol.registry_cid=machineCid(protocol.schemas);
    const manifestPath='spec/spec-family.json',manifest=read(manifestPath);
    const owner=manifest.documents.find(x=>x.document_id==='contracts');
    const existing=owner.machine_contracts.find(x=>x.path===path&&x.pointer===pointer);
    let source=readFileSync(owner.path,'utf8');
    const prefix=`../../../${path}#${pointer} `;
    if(existing){source=source.replace(prefix+existing.cid,prefix+cid);existing.cid=cid;}
    else{
      assert.ok(source.includes('<a id="notion-read-contracts"></a>'));
      source=source.replace('<a id="notion-read-contracts"></a>',
        `<a id="notion-read-contracts"></a>\n\n<!-- machine-import: ${prefix}${cid} -->`);
      owner.machine_contracts.push({path,pointer,cid,version:protocol.version});
    }
    const declarationsPointer='/schemas/notion_database_read_declarations';
    const declarationsCid=machineCid(declarations);
    const declarationsRef=owner.machine_contracts.find(x=>x.path===path&&x.pointer===declarationsPointer);
    const declarationsPrefix=`../../../${path}#${declarationsPointer} `;
    if(declarationsRef){
      source=source.replace(declarationsPrefix+declarationsRef.cid,declarationsPrefix+declarationsCid);
      declarationsRef.cid=declarationsCid;
    }else{
      assert.ok(source.includes('<a id="notion-read-declarations"></a>'));
      source=source.replace('<a id="notion-read-declarations"></a>',
        `<a id="notion-read-declarations"></a>\n\n<!-- machine-import: ${declarationsPrefix}${declarationsCid} -->`);
      owner.machine_contracts.push({path,pointer:declarationsPointer,cid:declarationsCid,version:protocol.version});
    }
    const snapshotPointer='/schemas/notion_database_read_snapshot';
    const snapshotCid=machineCid(snapshot);
    const snapshotRef=owner.machine_contracts.find(x=>x.path===path&&x.pointer===snapshotPointer);
    const snapshotPrefix=`../../../${path}#${snapshotPointer} `;
    if(snapshotRef){
      source=source.replace(snapshotPrefix+snapshotRef.cid,snapshotPrefix+snapshotCid);
      snapshotRef.cid=snapshotCid;
    }else{
      assert.ok(source.includes('<a id="notion-read-snapshot"></a>'));
      source=source.replace('<a id="notion-read-snapshot"></a>',
        `<a id="notion-read-snapshot"></a>\n\n<!-- machine-import: ${snapshotPrefix}${snapshotCid} -->`);
      owner.machine_contracts.push({path,pointer:snapshotPointer,cid:snapshotCid,version:protocol.version});
    }
    writeFileSync(path,JSON.stringify(protocol,null,2)+'\n');
    writeFileSync(manifestPath,JSON.stringify(manifest,null,2)+'\n');
    writeFileSync(owner.path,source);
  }
  checkNotionReadDeclarationSchema(protocol);
}
