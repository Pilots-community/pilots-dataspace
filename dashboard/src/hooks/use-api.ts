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

// ── Generic data fetch (for EDR endpoint) ──

export async function fetchWithAuth(url: string, token: string) {
  const res = await fetch(url, {
    headers: { "X-Edr-Token": token },
  });
  if (!res.ok) throw new Error(`Fetch error ${res.status}`);
  return res.text();
}
