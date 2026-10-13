from pathlib import Path
import json,gzip,hashlib
root=Path(__file__).resolve().parents[3]
f=root/'scripts/fixtures/native-local-scalar-predecessor'
def text(x): return json.dumps(x,ensure_ascii=False,separators=(',',':'),sort_keys=True)
def sha(x): return hashlib.sha256(x).hexdigest()
def cid(x): return 'sha256:'+sha(text(x).encode())
def ptr(x,p):
 for k in p.split('/')[1:] if p else []: x=x[int(k)] if isinstance(x,list) else x[k.replace('~1','/').replace('~0','~')]
 return x
def differences(a,b,p=''):
 if a==b: return []
 if isinstance(a,dict) and isinstance(b,dict):
  assert set(a)==set(b)
  return sum((differences(a[k],b[k],p+'/'+k.replace('~','~0').replace('/','~1')) for k in sorted(a)),[])
 if isinstance(a,list) and isinstance(b,list):
  assert len(a)==len(b)
  return sum((differences(x,y,p+'/'+str(i)) for i,(x,y) in enumerate(zip(a,b))),[])
 return [{'path':p,'original':a,'current':b}]
index=json.loads((f/'manifest.json').read_bytes())
old={r['role']:json.loads(gzip.decompress((f/r['fixture']).read_bytes())) for r in index['records']}
current={r['role']:ptr(json.loads((root/r['git_path']).read_bytes()),r['pointer']) for r in index['records']}
# Fixed input order in the reviewed evidence domain; full identities are read
# from the normative bodies, never from the product's generated evidence.
roles=['registry','values','fragment','ordered','expression','value-contract','text-time','text-time-dependencies','unicode-data','derive-binding','rows-to-graph']
impl=[{'path':r['path'],'sha256':sha(gzip.decompress((f/r['fixture']).read_bytes()))} for r in index['implementation_records']]
changes=[{'role':r,'differences':differences(old[r],current[r])} for r in sorted(roles)]
for row in changes:
 for d in row['differences']:
  assert (d['original']=='artifact_ref' and d['current']=='content_ref') or (isinstance(d['original'],str) and d['original'].startswith('sha256:') and d['current'].startswith('sha256:'))
original_runtime=gzip.decompress((f/'local-runtime.json.gz').read_bytes())
manifest=json.loads(original_runtime)
aoa=json.loads((root/'spec/contracts/actql-aoa.json').read_bytes())
raw_current={'environment':json.loads((root/'spec/local-check-environment.json').read_bytes()),'registry':json.loads((root/aoa['pipeline_registry_file']).read_bytes()),'values':aoa['execution_contracts']['REL.values'],'fragment':aoa['execution_contracts']['ACTQL.expression_fragment/0.1'],'ordered':aoa['execution_contracts']['REL.derive.ordered'],'result-policy':{'classification':'unknown','source_data_policy_cids':[],'source_response_policy_cids':[],'unknown_provenance':True,'version':'actql-effective-data-policy/0.1'}}
current_raw={r:json.dumps(x,ensure_ascii=False,separators=(',',':')).encode() for r,x in raw_current.items()}
asset_pairs=[{'role':r,'original_sha256':sha(gzip.decompress((f/(r+'.json.gz')).read_bytes())),'current_sha256':sha(current_raw[r])} for r in raw_current]
evidence={'version':'actql-native-local-scalar-pair-evidence/0.1','predecessor_source_sha':index['source'],'predecessor_runtime_sha256':sha(original_runtime),'profile':'primitive-scalar-values','reachable_operations':['REL.values','REL.derive','REL.where','REL.select'],'excluded':['references','json','containers','graph','vector','event','infer','effect','serialization','unknown','unresolved-obligations'],'body_pairs':[{'role':r,'original_cid':cid(old[r]),'current_cid':cid(current[r]),'original_canonical_body_sha256':sha(text(old[r]).encode()),'current_canonical_body_sha256':sha(text(current[r]).encode())} for r in roles],'exact_difference_cid':cid(changes),'implementation_evidence_cid':cid(impl),'asset_pairs':asset_pairs}
manifest['sourceSha']='b'*40
for a in manifest['assets']: a.update(bytes=len(current_raw[a['role']]),sha256=sha(current_raw[a['role']]))
current_manifest=json.dumps(manifest,ensure_ascii=False,separators=(',',':')).encode()
body={'current_manifest_sha256':sha(current_manifest),'current_source_sha':'b'*40,'evidence_cid':cid(evidence),'original_manifest_sha256':sha(original_runtime),'original_source_sha':index['source'],'platform':'darwin-arm64','profile':'primitive-scalar-values','version':'actql-native-local-scalar-runtime-pair/0.1'}
vector={'body':text(body),'cid':cid(body),'bytes':len(text(body).encode()),'evidence_cid':cid(evidence),'evidence_bytes':len(text(evidence).encode()),'exact_difference_cid':cid(changes),'current_manifest_sha256':sha(current_manifest),'note':'Independent Python source/fixture oracle. Synthetic current manifest; physical/adoption/installed success is not asserted.'}
out=root/'reviews/2026-10-12-d-native-local-expiry-1701/scalar-runtime-pair-vector.json';out.write_text(json.dumps(vector,indent=2)+'\n')
print(json.dumps(vector))
