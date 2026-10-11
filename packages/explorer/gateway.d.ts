import type {Client} from '@actql/sdk';
export const gatewayLimits: Readonly<{bodyBytes: 65536; replyBytes: 262144;
  bodyDepth: 64; bodyNodes: 10000; inFlight: 4; assets: 32;
  assetBytes: number; sessionMs: 300000; bootstrapMs: 60000; requestMs: 15000}>;
export type ExplorerAsset = Readonly<{body: Uint8Array; contentType:
  'text/html; charset=utf-8' | 'text/javascript; charset=utf-8' |
  'text/css; charset=utf-8' | 'image/svg+xml'}>;
export type ExplorerGatewayOptions = Readonly<{
  client: Pick<Client, 'attach'> & Partial<Pick<Client, 'plan'>>;
  assets?: ReadonlyMap<string, ExplorerAsset>; now?: () => number;
  sessionMs?: number; bootstrapMs?: number;
}>;
export type ExplorerBootstrap = Readonly<{origin: string; bootstrap: string; expiresAt: number}>;
export function createExplorerGateway(options: ExplorerGatewayOptions & {origin: string}): Readonly<{
  fetch(request: Request): Response | Promise<Response>;
  issueBootstrap(): ExplorerBootstrap; invalidateScope(): void; close(): void;
}>;
export function startExplorerGateway(options: ExplorerGatewayOptions & {port?: number}): Promise<Readonly<{
  origin: string; issueBootstrap(): ExplorerBootstrap;
  invalidateScope(): void; close(): Promise<void>;
}>>;
