#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Collect already-finished isolated Native evidence; executes no compiler/test."""
import argparse,hashlib,json,pathlib,shlex

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--work',required=True,type=pathlib.Path);p.add_argument('--repo',required=True,type=pathlib.Path);p.add_argument('--plan',required=True,type=pathlib.Path);p.add_argument('--output',required=True,type=pathlib.Path);a=p.parse_args()
 manifest=json.loads((a.work/'input-manifest.json').read_text())
 local_paths=list((a.work/'_build/local-checks/attempts').glob('*/summary.json'));focused_paths=list((a.work/'_build/focused-evidence').glob('*/summary.json'))
 assert len(local_paths)==len(focused_paths)==1
 local=json.loads(local_paths[0].read_text());focused=json.loads(focused_paths[0].read_text());counts=focused['commands'][0]['counts']
 assert local['status']=='passed' and local['complete'] and local['exitCode']==0 and local['timeoutSeconds']==180
 assert focused['status']=='passed' and focused['complete'] and counts['tests']==counts['passed']==6 and counts['failed']==0
 assert manifest['pre_run_hashes_verified'] and manifest['post_run_hashes_verified'] and len(manifest['cpu_affinity'])==3
 for name,digest in manifest['production_sources'].items():
  assert sha(a.repo/name)==digest
  assert sha(a.work/'src/kernel'/pathlib.Path(name).name)==digest
 assert sha(a.repo/manifest['scalar_source']['path'])==manifest['scalar_source']['sha256']
 executable=a.work/'_build/native/release/test/kernel/kernel.whitebox_test.exe';generated=executable.with_suffix('.c')
 lines=a.plan.read_text().splitlines();commands=[shlex.split(line) for line in lines if 'cc -o ' in line and 'kernel.whitebox_test.exe' in line]
 assert len(commands)==1
 compiler_command=commands[0]
 assert '-O2' in compiler_command and not any('fast-math' in x or 'ffp-contract' in x for x in compiler_command)
 installed=pathlib.Path(manifest['toolchain']['moon']['path']).parent.parent/'installed.json'
 report={'format':'actql-isolated-native-release-evidence/0.1','scope':manifest['scope'],'status':'passed','actual_tests':counts,'fixed_expectations':{'input_position_pairs':1000,'scalar_outputs':2000,'power_pairs':647,'counts_non_additive_across_targets':True},'inputs':manifest['production_sources'],'scalar_source':manifest['scalar_source'],'extractions':manifest['extractions'],'pre_run_hashes_verified':True,'post_run_hashes_verified':True,'current_hashes_reverified':True,'toolchain':manifest['toolchain'],'installed_toolchain_manifest_sha256':sha(installed),'installed_toolchain_pin':json.loads(installed.read_text())['pin'],'budget':{'seconds':180,'termination_grace_seconds':5,'cpu_affinity':manifest['cpu_affinity']},'receipts':{'local_attempt':local_paths[0].parent.name,'local_summary_sha256':sha(local_paths[0]),'focused_invocation':focused_paths[0].parent.name,'focused_summary_sha256':sha(focused_paths[0]),'started_at':local['startedAt'],'ended_at':local['endedAt'],'complete':True,'source_revision':focused['source'],'wrapper_sources':manifest['wrappers']},'native_compiler':{'identity':manifest['toolchain']['cc'],'command':compiler_command,'flags_source':'Moon --dry-run for unchanged successful Native --release configuration; no compilation or tests executed by this capture.','plan_sha256':sha(a.plan),'floating_point_flag_overrides':[]},'executed_artifact':{'file':'kernel.whitebox_test.exe','sha256':sha(executable),'bytes':executable.stat().st_size,'generated_c_sha256':sha(generated),'generated_c_bytes':generated.stat().st_size,'binaries_in_pr':False},'preparer_sha256':sha(pathlib.Path(__file__).with_name('prepare_native_release.py')),'plumbing_sha256':manifest['plumbing_sha256'],'warning':'Unused DECIMAL_ROUNDING_SLOTS in the isolated package; expression-owner/accounting code is intentionally absent.','limits':['Isolated copied-source arithmetic evidence, not product-owner/accounting or full Native acceptance.','No full-package Native --release pass; prior run-UQqvxS timed out at 180 seconds before tests.','No clean-commit, other compiler/architecture, public Host, packed distribution or live BigQuery claim.']}
 a.output.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'status':report['status'],'tests':counts,'report':str(a.output),'compiler_flags':[x for x in compiler_command if x.startswith('-')]}))
if __name__=='__main__':main()
