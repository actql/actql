import assert from 'node:assert/strict';
import {test} from 'node:test';
import fs from 'node:fs';
import {syncBuiltinESMExports} from 'node:module';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {scaffoldProject} from '../packages/native-cli/lib/project-scaffold.mjs';

// Inject failures into operations on real, fresh handles. Every original
// binding is restored before releasing only this probe's own resources.
for (const primaryFails of [true, false]) {
  test(`file close failure retains its original descriptor and ${primaryFails ? 'primary plus cleanup causes' : 'cleanup-only cause'}`, () => {
    const root = fs.mkdtempSync(join(tmpdir(), 'actql-project-file-cleanup-'));
    const original = {writeSync: fs.writeSync, closeSync: fs.closeSync};
    const primary = Object.assign(new Error('Write failed'), {code: 'ENOSPC'});
    const cleanup = Object.assign(new Error('Close unconfirmed'), {code: 'EIO'});
    let descriptor, caught;
    try {
      if (primaryFails) fs.writeSync = () => { throw primary; };
      fs.closeSync = fd => { descriptor = fd; throw cleanup; };
      syncBuiltinESMExports();
      try { scaffoldProject(join(root, 'project')); } catch (error) { caught = error; }
      assert.equal(caught?.code, 'ACTQL_E_PROJECT_CLEANUP_PENDING');
      assert.equal(caught.descriptor, descriptor);
      assert.equal(caught.cause, primaryFails ? primary : cleanup);
      assert.equal(caught.cleanupCause, cleanup);
      assert(fs.fstatSync(caught.descriptor).isFile());
      const project = join(root, 'project');
      assert.deepEqual(fs.readdirSync(project), ['actql.config.json']);
      assert.throws(() => scaffoldProject(project), {code: 'ACTQL_E_PROJECT_EXISTS'});
      assert.equal(fs.readFileSync(join(project, 'actql.config.json'), 'utf8'), primaryFails ? '' :
        '{\n  "version": "actql-config/0.1",\n  "connectors": "./connectors.json",\n  "model_tasks": "./model-tasks.json",\n  "state_dir": "./.actql"\n}\n');
    } finally {
      Object.assign(fs, original); syncBuiltinESMExports();
      if (descriptor !== undefined) original.closeSync(descriptor);
      fs.rmSync(root, {recursive: true});
    }
  });

  test(`directory close failure retains its original Dir and ${primaryFails ? 'primary plus cleanup causes' : 'cleanup-only cause'}`, () => {
    const root = fs.mkdtempSync(join(tmpdir(), 'actql-project-dir-cleanup-'));
    const opendir = fs.opendirSync;
    const primary = Object.assign(new Error('Read failed'), {code: 'EIO'});
    const cleanup = Object.assign(new Error('Close unconfirmed'), {code: 'EBUSY'});
    let directory, release, caught;
    try {
      fs.opendirSync = path => {
        directory = opendir(path);
        release = directory.closeSync.bind(directory);
        if (primaryFails) directory.readSync = () => { throw primary; };
        directory.closeSync = () => { throw cleanup; };
        return directory;
      };
      syncBuiltinESMExports();
      try { scaffoldProject(join(root, 'project')); } catch (error) { caught = error; }
      assert.equal(caught?.code, 'ACTQL_E_PROJECT_CLEANUP_PENDING');
      assert.equal(caught.directory, directory);
      assert.equal(caught.cause, primaryFails ? primary : cleanup);
      assert.equal(caught.cleanupCause, cleanup);
      assert.deepEqual(fs.readdirSync(join(root, 'project')), []);
    } finally {
      fs.opendirSync = opendir; syncBuiltinESMExports();
      release?.(); fs.rmSync(root, {recursive: true});
    }
  });
}

test('a failed write is returned unchanged after its original descriptor closes successfully', () => {
  const root = fs.mkdtempSync(join(tmpdir(), 'actql-project-write-failure-'));
  const original = {writeSync: fs.writeSync, closeSync: fs.closeSync};
  const primary = Object.assign(new Error('Write failed'), {code: 'ENOSPC'});
  let descriptor, closes = 0;
  try {
    fs.writeSync = () => { throw primary; };
    fs.closeSync = fd => { descriptor = fd; closes++; original.closeSync(fd); };
    syncBuiltinESMExports();
    assert.throws(() => scaffoldProject(join(root, 'project')), error => error === primary);
    assert.equal(closes, 1);
    assert.throws(() => fs.fstatSync(descriptor), {code: 'EBADF'});
    assert.deepEqual(fs.readdirSync(join(root, 'project')), ['actql.config.json']);
  } finally {
    Object.assign(fs, original); syncBuiltinESMExports();
    fs.rmSync(root, {recursive: true});
  }
});

test('a failed directory read is returned unchanged after its original Dir closes successfully', () => {
  const root = fs.mkdtempSync(join(tmpdir(), 'actql-project-read-failure-'));
  const opendir = fs.opendirSync;
  const primary = Object.assign(new Error('Read failed'), {code: 'EIO'});
  let directory, closes = 0;
  try {
    fs.opendirSync = path => {
      directory = opendir(path);
      const close = directory.closeSync.bind(directory);
      directory.readSync = () => { throw primary; };
      directory.closeSync = () => { closes++; close(); };
      return directory;
    };
    syncBuiltinESMExports();
    assert.throws(() => scaffoldProject(join(root, 'project')), error => error === primary);
    assert.equal(closes, 1);
    assert.throws(() => directory.closeSync(), {code: 'ERR_DIR_CLOSED'});
    assert.deepEqual(fs.readdirSync(join(root, 'project')), []);
  } finally {
    fs.opendirSync = opendir; syncBuiltinESMExports();
    fs.rmSync(root, {recursive: true});
  }
});
