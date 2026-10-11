#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Prepare an isolated copied-source Native-release diagnostic; never edit repo."""
import argparse,datetime,hashlib,json,os,pathlib,resource,shutil,subprocess,sys

FILES=['src/execution_relation/decimal_rounding.mbt','src/execution_relation/round_precision_reference.generated_wbtest.mbt','src/execution_relation/round_precision_powers.generated_wbtest.mbt']

def sha(data):return hashlib.sha256(data).hexdigest()
def identity(path):
 p=pathlib.Path(path).resolve();return {'path':str(p),'sha256':sha(p.read_bytes())}
def command(args,env):return subprocess.check_output(args,env=env,text=True,stderr=subprocess.STDOUT).strip()
def piece(data,start,end):
 a=data.index(start);b=data.index(end,a)
 return data[a:b],{'byte_start':a,'byte_end_exclusive':b,'line_start':data[:a].count(b'\n')+1,'line_end':data[:b].count(b'\n'),'sha256':sha(data[a:b])}

def main():
 ap=argparse.ArgumentParser(description=__doc__)
 for name in ['repo','destination','moon-home','node']:ap.add_argument('--'+name,required=True,type=pathlib.Path)
 ap.add_argument('--home',type=pathlib.Path)
 ap.add_argument('--run',action='store_true')
 args=ap.parse_args();repo=args.repo.resolve();dest=args.destination.resolve()
 if dest==repo or repo in dest.parents:ap.error('destination must be outside the active repository')
 if dest.exists():ap.error('destination must not exist; reuse requires a new explicit diagnostic')
 source={p:(repo/p).read_bytes() for p in FILES}
 scalar=(repo/'src/execution_relation/scalar.mbt').read_bytes()
 finite,finite_meta=piece(scalar,b'fn finite(',b'\n///|')
 unary_arm,arm_meta=piece(scalar,b'    Round | Trunc =>\n',b'    Sign =>\n')
 issues,issues_meta=piece(scalar,b'pub(all) enum ScalarIssue {',b'\n///|')
 dest.mkdir(parents=True);(dest/'src/kernel').mkdir(parents=True);(dest/'src/lower').mkdir()
 for path,data in source.items():(dest/'src/kernel'/pathlib.Path(path).name).write_bytes(data)
 (dest/'moon.mod').write_text('name = "actql/round_precision_isolated"\nversion = "0.0.1"\nlicense = "Apache-2.0"\nsource = "src"\npreferred_target = "native"\nsupported_targets = "+native"\n')
 (dest/'src/kernel/moon.pkg').write_text('supported_targets = "+native"\nimport { "actql/round_precision_isolated/lower" @lower, "moonbitlang/core/bigint", }\n')
 (dest/'src/lower/moon.pkg').write_text('supported_targets = "+native"\n')
 (dest/'src/lower/operators.mbt').write_text('///|\npub(all) enum UnaryOperator {\n  Round\n  Trunc\n} derive(Eq, Debug)\n///|\npub(all) enum BinaryOperator {\n  RoundAt\n  TruncAt\n} derive(Eq, Debug)\n')
 plumbing=b'''// Isolated diagnostic type plumbing only. Captured payload is never exercised.
///|
pub(all) enum Value {
  Null
  Number(Double)
  Boolean(Bool)
  Text(String)
  Captured(Int)
}
///|
'''+issues+b'\n///|\n'+finite+b'''\n///|
pub fn unary(op : @lower.UnaryOperator, value : Value) -> Result[Value, ScalarIssue] {
  match op {
'''+unary_arm+b'''  }
}
///|
pub fn binary(op : @lower.BinaryOperator, left : Value, right : Value) -> Result[Value, ScalarIssue] {
  decimal_round_binary(op, left, right)
}
'''
 (dest/'src/kernel/plumbing.mbt').write_bytes(plumbing)
 helper=repo/'scripts/test-execution.mjs';guard=repo/'scripts/local-checks-guard.mjs'
 code='import {runFocusedTests} from '+json.dumps(helper.as_uri())+'; process.exitCode=runFocusedTests("moon",process.argv.slice(1),{cwd:process.cwd()});'
 run={'root':str(dest),'heavy':False,'timeoutSeconds':180,'graceSeconds':5,'steps':[{'name':'isolated copied numerical Native release vectors','command':str(args.node.resolve()),'args':['--input-type=module','-e',code,'--','--target','native','--release','--frozen','--verbose','src/kernel/round_precision_reference.generated_wbtest.mbt','src/kernel/round_precision_powers.generated_wbtest.mbt']}]}
 (dest/'run-native.mjs').write_text('import {runLocalCheck} from '+json.dumps(guard.as_uri())+';\nprocess.exitCode=await runLocalCheck('+json.dumps(run)+');\n')
 home=(args.home or dest/'home').resolve();home.mkdir(parents=True,exist_ok=True);(dest/'tmp').mkdir()
 env=dict(os.environ);env.update(HOME=str(home),MOON_HOME=str(args.moon_home.resolve()),TMPDIR=str(dest/'tmp'),RUNNER_TEMP=str(dest/'tmp'))
 env['PATH']=str(args.node.resolve().parent)+':'+str(args.moon_home.resolve()/'bin')+':'+env.get('PATH','')
 affinity=sorted(os.sched_getaffinity(0))[:3]
 if len(affinity)!=3:raise RuntimeError('exactly three available CPUs are required')
 os.sched_setaffinity(0,affinity)
 resource.setrlimit(resource.RLIMIT_STACK,(64*1024*1024,resource.getrlimit(resource.RLIMIT_STACK)[1]))
 records={'format':'actql-isolated-round-precision-native-release/0.1','created_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'scope':'Isolated arithmetic only; not expression-owner/accounting or full Native acceptance.','production_sources':{p:sha(data) for p,data in source.items()},'scalar_source':{'path':'src/execution_relation/scalar.mbt','sha256':sha(scalar)},'extractions':{'finite':finite_meta,'Round_Trunc_unary_arm':arm_meta,'ScalarIssue_type':issues_meta},'copies':{p:sha((dest/'src/kernel'/pathlib.Path(p).name).read_bytes()) for p in FILES},'plumbing_sha256':sha(plumbing),'wrappers':{str(p.relative_to(repo)):sha(p.read_bytes()) for p in [helper,guard,repo/'scripts/local-checks-supervisor.mjs',repo/'scripts/packed-query-evidence.mjs']},'cpu_affinity':affinity,'timeout_seconds':180,'grace_seconds':5,'toolchain':{'moon':identity(args.moon_home/'bin/moon'),'moonc':identity(args.moon_home/'bin/moonc'),'node':identity(args.node),'cc':identity(shutil.which('cc',path=env['PATH'])),'moon_version':command([str(args.moon_home/'bin/moon'),'--version'],env),'cc_version':command(['cc','--version'],env).splitlines()[0]},'command':run,'status':'prepared'}
 for path,data in source.items():assert (repo/path).read_bytes()==data and (dest/'src/kernel'/pathlib.Path(path).name).read_bytes()==data
 records['pre_run_hashes_verified']=True
 (dest/'input-manifest.json').write_text(json.dumps(records,indent=2)+'\n')
 print(json.dumps({'status':'prepared','destination':str(dest),'source_sha256':records['production_sources'],'cpu_affinity':affinity}),flush=True)
 if not args.run:return 0
 with (dest/'bounded-native-release.log').open('w') as log:
  result=subprocess.run([str(args.node.resolve()),str(dest/'run-native.mjs')],cwd=dest,env=env,stdout=log,stderr=subprocess.STDOUT)
 after_sources={p:sha((repo/p).read_bytes()) for p in FILES}
 after_copies={p:sha((dest/'src/kernel'/pathlib.Path(p).name).read_bytes()) for p in FILES}
 scalar_after=sha((repo/'src/execution_relation/scalar.mbt').read_bytes())
 records.update(status='run_finished',process_exit_code=result.returncode,post_run_source_hashes=after_sources,post_run_copy_hashes=after_copies,post_run_scalar_sha256=scalar_after,post_run_hashes_verified=after_sources==records['production_sources'] and after_copies==records['production_sources'] and scalar_after==sha(scalar))
 records['completed_at_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat()
 (dest/'input-manifest.json').write_text(json.dumps(records,indent=2)+'\n')
 print(json.dumps({'status':records['status'],'exit_code':result.returncode,'post_run_hashes_verified':records['post_run_hashes_verified'],'log':str(dest/'bounded-native-release.log')}),flush=True)
 return result.returncode or (0 if records['post_run_hashes_verified'] else 1)

if __name__=='__main__':sys.exit(main())
