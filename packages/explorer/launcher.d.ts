import type {OpenOptions, LocalSession} from '@actql/node';
import type {ExplorerGatewayOptions, startExplorerGateway} from './gateway.js';
type Gateway = Awaited<ReturnType<typeof startExplorerGateway>>;
export function startExplorer(options: Omit<ExplorerGatewayOptions, 'assets'> &
  {port?: number}): Promise<Gateway>;
export function openLocalExplorer(options?: Omit<ExplorerGatewayOptions, 'assets' | 'client'> &
  {port?: number; local?: OpenOptions}): Promise<Gateway & {readonly local: LocalSession['info']}>;
