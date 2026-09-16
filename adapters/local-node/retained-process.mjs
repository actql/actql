// Node execution-process assembly. This file is not part of the portable Local
// contribution; Workers need not resolve file/process dependencies to load it.
import {createProcessStoreLease} from '../store-local/process-client.mjs';
import {processStoreContext} from '../store-local/process-binding.mjs';
import {installLocalRetainedStore} from './retained-store.mjs';

export function configureLocalProcessStore(binding) {
  processStoreContext(binding);
  return installLocalRetainedStore((key, bytes, frame, signal) =>
    createProcessStoreLease(binding, key, bytes, frame, signal));
}
