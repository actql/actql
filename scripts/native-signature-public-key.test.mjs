// Explicit public-fixture C/FFI diagnostic, not a Native Host or signing test.
import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {createOwnedScratch} from './owned-scratch.mjs';
import {createCommandEvidence, commandSource} from './packed-query-evidence.mjs';

test('selected Library public-only raw32 projection and refusal cases', async () => {
  assert.equal(process.platform, 'darwin');
  assert.equal(process.arch, 'arm64');
  const root=process.cwd(), moon=process.env.MOON_HOME;
  const library=process.env.ACTQL_TEST_PUBLIC_CRYPTO_LIBRARY;
  assert(moon && library, 'explicit pinned toolchain and public fixture Library required');
  assert.equal(createHash('sha256').update(readFileSync(library)).digest('hex'),
    '125a8de6bf7ab462a0f2f8f53358a9560555e94cd3331d4a6d41a95f1536b0a1');
  const scratch=await createOwnedScratch({parent:join(root,'_build'),
    prefix:'public-key-c-',label:'public key C fixture',digests:()=>['comparison']});
  const evidence=createCommandEvidence({scratch:join(root,'_build/public-key-evidence'),
    revision:commandSource(root).revision,cwd:root});
  try {
    const compile=['-Wl,-dead_strip','-std=c11','-O0','-DMOONBIT_ALLOCATOR=2',
      `-I${moon}/include`,join(root,'scripts/fixtures/native-signature-public-key.c'),
      `${moon}/lib/runtime/runtime.c`,`${moon}/lib/runtime/backtrace.c`,
      `${moon}/lib/libmoonbitrun.o`,'-isysroot',
      '/Library/Developer/CommandLineTools/SDKs/MacOSX26.2.sdk',
      '-o',join(scratch.path,'comparison')];
    const built=evidence.capture('/Library/Developer/CommandLineTools/usr/bin/clang',
      compile,{timeout:20000,killSignal:'SIGTERM',maxBuffer:2*1024*1024});
    assert.equal(built.result.status,0,built.result.stderr);assert(!built.result.error);
    assert.equal(built.result.signal,null);assert(!built.writeFailure);
    const actual=evidence.capture(join(scratch.path,'comparison'),[library],
      {timeout:20000,killSignal:'SIGTERM',maxBuffer:2*1024*1024}, result=>{
        const matches=[...(result.stdout??'').matchAll(/^.+: PASS$/gm)];
        const valid=result.status===0&&!result.signal&&!result.error&&
          matches.length===12&&(result.stdout??'').includes('Public key comparison cases: 12/12');
        return {status:valid?0:1,counts:{tests:matches.length,passed:valid?12:0,
          failed:valid?0:matches.length,cancelled:0,skipped:0,todo:0}};
      });
    process.stdout.write(actual.result.stdout??'');
    process.stderr.write(actual.result.stderr??'');
    assert.equal(actual.result.status,0);assert(!actual.result.error);
    assert.equal(actual.checked.status,0);assert.equal(actual.checked.counts.tests,12);
    assert(!actual.writeFailure);evidence.finish('passed');assert(evidence.summary.complete);
    scratch.passed();
  } catch(error) {evidence.finish('failed');throw error;}
});
