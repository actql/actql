import {mkdirSync, mkdtempSync, statSync, symlinkSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {join} from 'node:path';
import {nativeFilesystemObservationFixtures} from './native-filesystem-observation-fixture.mjs';

// A fresh filesystem test Root must satisfy the same private-mode admission
// as production. Never adopt or chmod an existing caller directory.
export function nativeFilesystemTestRoot(parent) {
  const root = join(parent, 'filesystem-test');
  mkdirSync(root, {mode: 0o700});
  if ((statSync(root).mode & 0o777) !== 0o700) {
    throw new Error('Native filesystem fixture requires private mode 0700');
  }
  return root;
}

// Each independently executed package owns a fresh Store namespace. Reopens
// inside that package retain this path; unrelated packages never inherit it.
export function nativePackageStoreRoot(parent) {
  return mkdtempSync(join(parent, 'package-store-'));
}

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
  const env={...nativeFilesystemObservationFixtures(parent),
    ACTQL_TEST_NATIVE_PRIVATE_ROOT:privateRoot,
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
