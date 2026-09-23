export type ClientHostOperation =
  | 'connect' | 'submit' | 'attach' | 'lookup-request' | 'status'
  | 'wait' | 'cancel' | 'reconcile' | 'read' | 'delivery-attempt';

export declare const clientHostOperations: readonly ClientHostOperation[];

type WireConnectionBase = Readonly<{
  durability?: 'volatile' | 'durable';
  consentRefs: readonly string[];
  runners: readonly string[];
  movementPolicyRef?: string;
}>;

export type WireConnection =
  | (WireConnectionBase & Readonly<{mode: 'local'; owner: 'local'}>)
  | (WireConnectionBase & Readonly<{mode: 'remote'; owner: 'remote'}>)
  | (WireConnectionBase & Readonly<{mode: 'hybrid';
      owner: 'local' | 'cloud'; movementPolicyRef: string}>);

export type WireRunRef = Readonly<{
  tenantId: string;
  authorityScopeCid: string;
  runDefinitionCid: string;
}>;

export declare function validRunRef(value: unknown): value is WireRunRef;
export declare function validClientConnection(value: unknown):
  value is WireConnection;
export declare function validClientBody(operation: string, body: unknown):
  body is Readonly<Record<string, unknown> & {connection: WireConnection}>;
