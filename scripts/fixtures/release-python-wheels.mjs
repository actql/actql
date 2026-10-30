// Existing independently authored inert wheel fixture, shared by fixed-set
// and per-project publication controls. No engine/image/install or signing.
import {execFileSync} from 'node:child_process';
import {mkdir} from 'node:fs/promises';

export async function writeInertPythonReleaseCohort(directory, python) {
  await mkdir(directory);
  execFileSync(python, ['-c', `
import pathlib,zipfile,json,hashlib
p=pathlib.Path(__import__('sys').argv[1]);w=p/'wheels';w.mkdir();records=[]
for name in ['actql-sdk','actql-local-runtime','actql']:
 tag='py3-none-macosx_11_0_arm64' if name=='actql-local-runtime' else 'py3-none-any'
 version='0.0.7rc1';stem=name.replace('-','_');path=w/(stem+'-'+version+'-'+tag+'.whl');info=stem+'-'+version+'.dist-info/'
 deps={'actql':['actql-sdk=='+version,'actql-local-runtime=='+version],'actql-sdk':['httpx==0.28.1','rfc8785==0.1.4'],'actql-local-runtime':['wasmtime==38.0.0']}[name]
 with zipfile.ZipFile(path,'w') as z:
  z.writestr(info+'METADATA','Metadata-Version: 2.4\\nName: '+name+'\\nVersion: '+version+'\\n'+''.join('Requires-Dist: '+v+'\\n' for v in deps))
  z.writestr(info+'WHEEL','Wheel-Version: 1.0\\nTag: '+tag+'\\n')
  z.writestr(info+'RECORD','')
  if name=='actql':
   for n in ['__init__.py','__init__.pyi','py.typed']:z.writestr('actql/'+n,'')
 records.append(dict(distribution=name,file=path.name,bytes=path.stat().st_size,sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
cohort=dict(source_sha='a'*40,package_version='0.0.7rc1',artifact_sha256='b'*64,platform='darwin-arm64',core_abi=1,module_sha256='c'*64,duckdb_sha256='d'*64,image_sha256='e'*64,engine_recipe_sha256='f'*64,host_capacity_sha256=None,wheels=records,runtime_executed=False,public_local_accepted=False,recovery_accepted=False,published=False)
(p/'cohort.json').write_text(json.dumps(cohort))
`, directory], {encoding: 'utf8', stdio: 'pipe'});
}
