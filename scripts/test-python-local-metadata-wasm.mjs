// Pure Core entrance vectors only. Every physical Host import must remain unused.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
const artifact = process.argv[2];
const selected = process.argv[4] ?? 'original_metadata_wbtest.mbt';
assert.match(selected, /^[a-z0-9_]+_wbtest\.mbt$/u);
const bytes = fs.readFileSync(artifact);
const module = new WebAssembly.Module(bytes);
let instance;
let output = '';
let hostCalls = 0;
// The selected non-GC Wasm imports an empty exception tag and void throw.
const tag = new WebAssembly.Tag({parameters: []});
const imports = {
  exception: {tag, throw() {throw new WebAssembly.Exception(tag, []);}},
  __moonbit_fs_unstable: {
    begin_read_string(value) {assert.equal(typeof value, 'string'); return {value, offset: 0};},
    string_read_char(handle) {
      if (handle.offset >= handle.value.length) return -1;
      const cp = handle.value.codePointAt(handle.offset);
      handle.offset += cp > 65535 ? 2 : 1;
      return cp;
    },
    finish_read_string() {},
  },
  wasi_snapshot_preview1: {
    fd_write(fd, vectors, length, written) {
      assert.ok(fd === 1 || fd === 2);
      const memory = instance.exports.memory.buffer;
      const view = new DataView(memory);
      let count = 0;
      for (let i = 0; i < length; i++) {
        const ptr = view.getUint32(vectors + 8 * i, true);
        const size = view.getUint32(vectors + 8 * i + 4, true);
        const data = Buffer.from(memory, ptr, size);
        output += data.toString('utf8');
        process.stdout.write(data);
        count += size;
      }
      view.setUint32(written, count, true);
      return 0;
    },
  },
  actql_host: {},
};
for (const entry of WebAssembly.Module.imports(module)) {
  if (entry.module === 'actql_host') {
    assert.equal(entry.kind, 'function');
    imports.actql_host[entry.name] = () => {
      hostCalls++;
      throw new Error(`Unexpected physical Host call: ${entry.name}`);
    };
  }
}
instance = new WebAssembly.Instance(module, imports);
instance.exports._start();
const info = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'));
const tests = info.tests[selected];
assert.ok(Array.isArray(tests) && tests.length >= 2);
for (const {index} of tests) {
  instance.exports.moonbit_test_driver_internal_execute(selected, index);
}
instance.exports.moonbit_test_driver_finish();
const results = output.split('\n').filter(line => line.startsWith('{')).map(line => JSON.parse(line)).filter(row => row.type === 'result');
assert.equal(hostCalls, 0);
assert.equal(results.length, tests.length);
assert.deepEqual(results.map(row => row.index).sort((a,b)=>a-b), tests.map(row => row.index).sort((a,b)=>a-b));
assert.ok(results.every(row => row.message === ''), 'Selected pure Core entrance assertion failed');
console.log(JSON.stringify({actualTests: results.length, hostCalls, wasmSha256: crypto.createHash('sha256').update(bytes).digest('hex')}));
