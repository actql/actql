// Existing independently authored inert wheel fixture, shared by fixed-set
// and per-project publication controls. No engine/image/install or signing.
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';

export async function writeInertPythonReleaseCohort(directory, python,
  {version = '0.0.7rc1', platform = 'darwin-arm64'} = {}) {
  await mkdir(directory);
  execFileSync(python, ['-c', `
import pathlib,zipfile,json,hashlib
import sys
p=pathlib.Path(sys.argv[1]);w=p/'wheels';w.mkdir();records=[]
version,platform=sys.argv[2:4]
runtime_tag={'darwin-arm64':'py3-none-macosx_11_0_arm64','linux-x64':'py3-none-manylinux_2_28_x86_64'}[platform]
for name in ['actql-sdk','actql-local-runtime','actql']:
 tag=runtime_tag if name=='actql-local-runtime' else 'py3-none-any'
 stem=name.replace('-','_');path=w/(stem+'-'+version+'-'+tag+'.whl');info=stem+'-'+version+'.dist-info/'
 deps={'actql':['actql-sdk=='+version,'actql-local-runtime=='+version],'actql-sdk':['httpx==0.28.1','rfc8785==0.1.4'],'actql-local-runtime':['wasmtime==51.0.0']}[name]
 with zipfile.ZipFile(path,'w') as z:
  z.writestr(zipfile.ZipInfo(info+'METADATA'),'Metadata-Version: 2.4\\nName: '+name+'\\nVersion: '+version+'\\n'+''.join('Requires-Dist: '+v+'\\n' for v in deps))
  z.writestr(zipfile.ZipInfo(info+'WHEEL'),'Wheel-Version: 1.0\\nTag: '+tag+'\\n')
  z.writestr(zipfile.ZipInfo(info+'RECORD'),'')
  if name=='actql':
   for n in ['__init__.py','__init__.pyi','py.typed']:z.writestr(zipfile.ZipInfo('actql/'+n),'')
 records.append(dict(distribution=name,file=path.name,bytes=path.stat().st_size,sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
cohort=dict(source_sha='a'*40,package_version=version,artifact_sha256='b'*64,platform=platform,core_abi=1,module_sha256='c'*64,duckdb_sha256='d'*64,image_sha256='e'*64,engine_recipe_sha256='f'*64,host_capacity_sha256=None,wheels=records,runtime_executed=False,public_local_accepted=False,recovery_accepted=False,published=False)
(p/'cohort.json').write_text(json.dumps(cohort))
`, directory, version, platform], {encoding: 'utf8', stdio: 'pipe'});
}

export async function writeInertPairedPythonReleaseCohort(directory, python) {
  const platforms = ['linux-x64', 'darwin-arm64'];
  const version = '0.0.3', source = 'a'.repeat(40), attempt = '1', runId = '100';
  const hash = bytes => createHash('sha256').update(bytes).digest('hex');
  const producerArchives = {}, receipts = [];
  await mkdir(directory);
  for (const [index, platform] of platforms.entries()) {
    const location = join(directory, platform), archive = join(directory, `${platform}.zip`);
    await writeInertPythonReleaseCohort(location, python, {platform, version});
    const manifest = await readFile(join(location, 'cohort.json'));
    const [sdk, runtime, facade] = JSON.parse(manifest).wheels;
    execFileSync(python, ['-I', '-B', '-c', [
      'from pathlib import Path',
      'from sys import argv',
      'from zipfile import ZipFile, ZIP_DEFLATED',
      'root = Path(argv[1])',
      'with ZipFile(argv[2], "x", compression=ZIP_DEFLATED) as archive:',
      '    for path in sorted(root.rglob("*")):',
      '        if path.is_file(): archive.write(path, "cohort/" + path.relative_to(root).as_posix())',
    ].join('\n'), location, archive]);
    producerArchives[platform] = archive;
    receipts.push({platform, producerArtifactId: String(index + 1), producerJobId: index + 1,
      producerRepository: 'actql/actql', producerArtifactName: `python-wheel-acceptance-${platform}-${runId}-${attempt}`,
      archiveSha256: hash(await readFile(archive)), manifestSha256: hash(manifest), gateBSha256: '9'.repeat(64),
      wheels: {sdk, runtime, facade}});
  }
  const [{wheels: linux}, {wheels: darwin}] = receipts;
  const publishWheels = [linux.facade, linux.sdk, linux.runtime, darwin.runtime];
  const publishWheelOrigins = publishWheels.map(({file}) => ({file,
    members: receipts.filter(receipt => Object.values(receipt.wheels).some(pin => pin.file === file))
      .map(({platform, producerArtifactId}) => ({platform, producerArtifactId, member: `cohort/wheels/${file}`}))}));
  const pair = JSON.stringify({sourceSha: source, packageVersion: version, wheelRunId: runId, wheelRunAttempt: attempt,
    platforms: receipts, publishWheels, publishWheelOrigins}) + '\n';
  await writeFile(join(directory, 'python-release-pair.json'), pair);
  return {targetId: 'python', kind: 'python-wheel-pair', directory, pairSha256: hash(pair), producerArchives};
}
