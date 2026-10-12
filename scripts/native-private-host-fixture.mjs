import {mkdirSync, statSync, symlinkSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {join} from 'node:path';

// Only the caller's already-owned invocation namespace is populated. These
// paths never become product Host configuration, grants or adoption records.
export function nativePrivateHostFixture(parent) {
  const privateRoot=join(parent,'private-host-root');
  const broadRoot=join(parent,'broad-host-root');
  const alias=join(parent,'private-host-alias');
  mkdirSync(privateRoot,{mode:0o700});
  mkdirSync(join(privateRoot,'nested'),{mode:0o700});
  mkdirSync(broadRoot,{mode:0o750});
  symlinkSync(privateRoot,alias,'dir');
  const env={ACTQL_TEST_NATIVE_PRIVATE_ROOT:privateRoot,
    ACTQL_TEST_NATIVE_BROAD_ROOT:broadRoot,ACTQL_TEST_NATIVE_PRIVATE_ALIAS:alias};
  if(process.platform==='darwin') {
    const aclRoot=join(parent,'private-host-acl');
    mkdirSync(aclRoot,{mode:0o700});
    execFileSync('/bin/chmod',['+a','everyone allow read',aclRoot],
      {timeout:5000,maxBuffer:65536,stdio:'pipe'});
    // The ACL counterexample must not become the existing broad-mode case.
    if((statSync(aclRoot).mode&0o777)!==0o700) throw new Error('ACL fixture changed private POSIX mode');
    env.ACTQL_TEST_NATIVE_PRIVATE_ACL_ROOT=aclRoot;
  }
  return env;
}
