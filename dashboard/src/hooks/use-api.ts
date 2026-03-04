import {
  useQuery,
  useMutation,
  useQueryClient,
} from "@tanstack/react-query";
import { edcFetch } from "@/lib/api";
import { useApiKey } from "./use-role";

// ── Assets ──

export function useAssets() {
  const { apiKey } = useApiKey();
  return useQuery({
    queryKey: ["assets"],
    queryFn: () =>
      edcFetch<Record<string, unknown>[]>("/v3/assets/request", {
        method: "POST",
        body: { "@type": "QuerySpec" },
        apiKey,
      }),
  });
}

export function useCreateAsset() {
  const { apiKey } = useApiKey();
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (asset: Record<string, unknown>) =>
      edcFetch("/v3/assets", { method: "POST", body: asset, apiKey }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["assets"] }),
  });
}

// ── Policies ──

export function usePolicies() {
  const { apiKey } = useApiKey();
  return useQuery({
    queryKey: ["policies"],
    queryFn: () =>
      edcFetch<Record<string, unknown>[]>("/v3/policydefinitions/request", {
        method: "POST",
        body: { "@type": "QuerySpec" },
        apiKey,
      }),
  });
}

export function useCreatePolicy() {
  const { apiKey } = useApiKey();
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (policy: Record<string, unknown>) =>
      edcFetch("/v3/policydefinitions", {
        method: "POST",
        body: policy,
        apiKey,
      }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["policies"] }),
  });
}

// ── Contract Definitions ──

export function useContractDefs() {
  const { apiKey } = useApiKey();
  return useQuery({
    queryKey: ["contractdefs"],
    queryFn: () =>
      edcFetch<Record<string, unknown>[]>(
        "/v3/contractdefinitions/request",
        { method: "POST", body: { "@type": "QuerySpec" }, apiKey }
      ),
  });
}

export function useCreateContractDef() {
  const { apiKey } = useApiKey();
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (def: Record<string, unknown>) =>
      edcFetch("/v3/contractdefinitions", {
        method: "POST",
        body: def,
        apiKey,
      }),
    onSuccess: () =>
      qc.invalidateQueries({ queryKey: ["contractdefs"] }),
  });
}

// ── Catalog ──

export function useCatalog() {
  const { apiKey } = useApiKey();
  return useMutation({
    mutationFn: (params: {
      counterPartyAddress: string;
      counterPartyId: string;
    }) =>
      edcFetch<Record<string, unknown>>("/v3/catalog/request", {
        method: "POST",
        body: {
          "@type": "CatalogRequest",
          counterPartyAddress: params.counterPartyAddress,
          counterPartyId: params.counterPartyId,
          protocol: "dataspace-protocol-http",
        },
        apiKey,
      }),
  });
}

// ── Negotiations ──

export function useNegotiations() {
  const { apiKey } = useApiKey();
  return useQuery({
    queryKey: ["negotiations"],
    queryFn: () =>
      edcFetch<Record<string, unknown>[]>(
        "/v3/contractnegotiations/request",
        { method: "POST", body: { "@type": "QuerySpec" }, apiKey }
      ),
    refetchInterval: 3000,
  });
}

export function useNegotiation(id: string | null) {
  const { apiKey } = useApiKey();
  return useQuery({
    queryKey: ["negotiation", id],
    queryFn: () =>
      edcFetch<Record<string, unknown>>(
        `/v3/contractnegotiations/${id}`,
        { apiKey }
      ),
    enabled: !!id,
    refetchInterval: (query) => {
      const state = query.state.data?.["state"];
      return state === "FINALIZED" || state === "TERMINATED"
        ? false
        : 2000;
    },
  });
}

export function useCreateNegotiation() {
  const { apiKey } = useApiKey();
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (negotiation: Record<string, unknown>) =>
      edcFetch<Record<string, unknown>>(
        "/v3/contractnegotiations",
        { method: "POST", body: negotiation, apiKey }
      ),
    onSuccess: () =>
      qc.invalidateQueries({ queryKey: ["negotiations"] }),
  });
}

// ── Transfers ──

export function useTransfers() {
  const { apiKey } = useApiKey();
  return useQuery({
    queryKey: ["transfers"],
    queryFn: () =>
      edcFetch<Record<string, unknown>[]>(
        "/v3/transferprocesses/request",
        { method: "POST", body: { "@type": "QuerySpec" }, apiKey }
      ),
    refetchInterval: 3000,
  });
}

export function useTransfer(id: string | null) {
  const { apiKey } = useApiKey();
  return useQuery({
    queryKey: ["transfer", id],
    queryFn: () =>
      edcFetch<Record<string, unknown>>(
        `/v3/transferprocesses/${id}`,
        { apiKey }
      ),
    enabled: !!id,
    refetchInterval: (query) => {
      const state = query.state.data?.["state"];
      return state === "COMPLETED" ||
        state === "TERMINATED" ||
        state === "STARTED"
        ? false
        : 2000;
    },
  });
}

export function useCreateTransfer() {
  const { apiKey } = useApiKey();
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (transfer: Record<string, unknown>) =>
      edcFetch<Record<string, unknown>>("/v3/transferprocesses", {
        method: "POST",
        body: transfer,
        apiKey,
      }),
    onSuccess: () =>
      qc.invalidateQueries({ queryKey: ["transfers"] }),
  });
}

// ── EDR ──

export function useEdrs(transferId: string | null) {
  const { apiKey } = useApiKey();
  return useQuery({
    queryKey: ["edrs", transferId],
    queryFn: () =>
      edcFetch<Record<string, unknown>>(
        `/v3/edrs/${transferId}/dataaddress`,
        { apiKey }
      ),
    enabled: !!transferId,
  });
}

// ── Trusted Issuers ──

async function plainFetch<T>(
  path: string,
  options: { method?: string; body?: Record<string, unknown>; apiKey?: string } = {}
): Promise<T> {
  const { method = "GET", body, apiKey } = options;
  const url = `/api/management${path}`;
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (apiKey) headers["x-api-key"] = apiKey;
  const res = await fetch(url, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`API error ${res.status}: ${text}`);
  }
  const text = await res.text();
  if (!text) return undefined as T;
  return JSON.parse(text) as T;
}

export interface TrustedIssuer {
  did: string;
  credentialTypes: string[];
  name: string;
  organization: string;
  email: string;
  dspEndpoint: string;
  participantDid: string;
}

export interface AddTrustedIssuerParams {
  did: string;
  name?: string;
  organization?: string;
  email?: string;
  dspEndpoint?: string;
  participantDid?: string;
}

export function useTrustedIssuerHealth() {
  const { apiKey } = useApiKey();
  return useQuery({
    queryKey: ["trusted-issuer-health"],
    queryFn: () =>
      plainFetch<Record<string, string>>(
        "/v1/trusted-issuers/health",
        { apiKey }
      ),
    refetchInterval: 15000,
  });
}

export function useTrustedIssuers() {
  const { apiKey } = useApiKey();
  return useQuery({
    queryKey: ["trusted-issuers"],
    queryFn: () =>
      plainFetch<TrustedIssuer[]>(
        "/v1/trusted-issuers",
        { apiKey }
      ),
  });
}

export function useAddTrustedIssuer() {
  const { apiKey } = useApiKey();
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (params: AddTrustedIssuerParams) =>
      plainFetch("/v1/trusted-issuers", {
        method: "POST",
        body: params as unknown as Record<string, unknown>,
        apiKey,
      }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["trusted-issuers"] }),
  });
}

export function useUpdateTrustedIssuer() {
  const { apiKey } = useApiKey();
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (params: AddTrustedIssuerParams) =>
      plainFetch("/v1/trusted-issuers", {
        method: "PUT",
        body: params as unknown as Record<string, unknown>,
        apiKey,
      }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["trusted-issuers"] }),
  });
}

export function useDeleteTrustedIssuer() {
  const { apiKey } = useApiKey();
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (did: string) =>
      plainFetch("/v1/trusted-issuers", {
        method: "DELETE",
        body: { did },
        apiKey,
      }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["trusted-issuers"] }),
  });
}

// ── Generic data fetch (for EDR endpoint) ──

export async function fetchWithAuth(url: string, token: string) {
  const res = await fetch(url, {
    headers: { "X-Edr-Token": token },
  });
  if (!res.ok) throw new Error(`Fetch error ${res.status}`);
  return res.text();
}
