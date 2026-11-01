// Normal shared native image selection for Files and Store-owner custody.
import {createRequire} from 'node:module';
import {existsSync} from 'node:fs';
const require = createRequire(import.meta.url);
export function localProjectFilesystem() {
  // Normal native delivery and Node's ABI checks, not a selected-preload image
  // recipe. Load failure stays a supported-backend gap; it never selects a
  // weaker pathname reader or another installation's resource original.
  if (process.platform === 'darwin' && process.arch === 'arm64') {
    if (existsSync(new URL('../../_build/native/directory-darwin-arm64.node', import.meta.url))) {
      return require('../../_build/native/directory-darwin-arm64.node');
    }
    if (existsSync(new URL('../../packages/local-node/_build/native/directory-darwin-arm64.node', import.meta.url))) {
      return require('../../packages/local-node/_build/native/directory-darwin-arm64.node');
    }
  } else if (process.platform === 'darwin' && process.arch === 'x64') {
    if (existsSync(new URL('../../_build/native/directory-darwin-x64.node', import.meta.url))) {
      return require('../../_build/native/directory-darwin-x64.node');
    }
    if (existsSync(new URL('../../packages/local-node/_build/native/directory-darwin-x64.node', import.meta.url))) {
      return require('../../packages/local-node/_build/native/directory-darwin-x64.node');
    }
  }
  if (process.platform === 'linux' && process.arch === 'x64') {
    if (existsSync(new URL('../../_build/native/local-files-linux-x64.node', import.meta.url))) {
      return require('../../_build/native/local-files-linux-x64.node');
    }
    if (existsSync(new URL('../../packages/local-node/_build/native/local-files-linux-x64.node', import.meta.url))) {
      return require('../../packages/local-node/_build/native/local-files-linux-x64.node');
    }
  }
  throw Object.assign(new Error('LocalFilesNativeUnavailable'), {code: 'LocalFilesNativeUnavailable'});
}
