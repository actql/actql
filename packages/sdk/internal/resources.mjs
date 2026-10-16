// Authorized Resource catalog/metadata/sample views; no execution authority.
import {ClientError, fail} from './errors.mjs';
import {jsonPayloadWireBytes} from './transport-response.mjs';
import {validClientBody, validResourceInspection, validResourceListing, validResourcePeek} from '@actql/client-wire';

export function createResources(connection, exchange, responseValue) {
  const selected = {wire: connection};
  return {
    resources: async (resourceConnection, {query = '', limit = 100,
      signal} = {}) => {
      const body = {resourceConnection, query, limit};
      if (!validClientBody('resources', {connection: selected.wire,
        ...body})) fail('InvalidResourceListing');
      const response = await exchange('resources', body, signal);
      let listing;
      try { listing = await responseValue(response); }
      catch (cause) {
        if (cause instanceof ClientError) throw cause;
        throw new ClientError('InvalidHostResourceListing', {cause});
      }
      if (!validResourceListing(listing, {resourceConnection, limit})) {
        fail('InvalidHostResourceListing');
      }
      return Object.freeze({...listing, resources: Object.freeze(
        listing.resources.map(item => Object.freeze({...item})))});
    },
    // Typed metadata of one Resource the caller may see. `catalog_required`
    // with a reason means the Host's Catalog cannot answer yet; it is never
    // evidence that the Resource is absent.
    inspectResource: async (resourceConnection, resource, {
      maxBytes = 64 * 1024, signal} = {}) => {
      const body = {resourceConnection, resource, maxBytes};
      if (!validClientBody('resource-inspect', {connection: selected.wire,
        ...body})) fail('InvalidResourceInspection');
      const response = await exchange('resource-inspect', body, signal);
      let inspection;
      try { inspection = await responseValue(response, jsonPayloadWireBytes(maxBytes)); }
      catch (cause) {
        if (cause instanceof ClientError) throw cause;
        throw new ClientError('InvalidHostResourceInspection', {cause});
      }
      if (!validResourceInspection(inspection, body)) {
        fail('InvalidHostResourceInspection');
      }
      const {summaryJson, ...rest} = inspection;
      return Object.freeze({...rest, ...(summaryJson === undefined ? {} :
        {summary: JSON.parse(summaryJson)})});
    },
    // A separately authorized preview of at most `maxRows` rows with exactly
    // `fields`. `limited` marks a prefix; a preview is never a complete read,
    // Acquisition evidence or a Result.
    peekResource: async (resourceConnection, resource, {fields, maxRows = 10,
      maxBytes = 64 * 1024, signal} = {}) => {
      const body = {resourceConnection, resource,
        fields: Array.isArray(fields) ? [...fields] : fields, maxRows,
        maxBytes};
      if (!validClientBody('resource-peek', {connection: selected.wire,
        ...body})) fail('InvalidResourcePeek');
      const response = await exchange('resource-peek', body, signal);
      let peek;
      try { peek = await responseValue(response, jsonPayloadWireBytes(maxBytes)); }
      catch (cause) {
        if (cause instanceof ClientError) throw cause;
        throw new ClientError('InvalidHostResourcePeek', {cause});
      }
      if (!validResourcePeek(peek, body)) fail('InvalidHostResourcePeek');
      const {rowsJson, ...rest} = peek;
      return Object.freeze({...rest, fields: Object.freeze([...peek.fields]),
        rows: Object.freeze(JSON.parse(rowsJson).map(row =>
          Object.freeze(row)))});
    },
  };
}
