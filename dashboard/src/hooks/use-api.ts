import {
  useQuery,
  useMutation,
  useQueryClient,
} from "@tanstack/react-query";
import { edcFetch } from "@/lib/api";
import { useRole } from "./use-role";

// ── Assets ──

export function useAssets() {
  const { role, apiKey } = useRole();
  return useQuery({
    queryKey: ["assets", role],
    queryFn: () =>
      edcFetch<Record<string, unknown>[]>(role, "/v3/assets/request", {
        method: "POST",
        body: { "@type": "QuerySpec" },
        apiKey,
      }),
  });
}

export function useCreateAsset() {
  const { role, apiKey } = useRole();
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (asset: Record<string, unknown>) =>
      edcFetch(role, "/v3/assets", { method: "POST", body: asset, apiKey }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["assets", role] }),
  });
}

// ── Policies ──

export function usePolicies() {
  const { role, apiKey } = useRole();
  return useQuery({
    queryKey: ["policies", role],
    queryFn: () =>
      edcFetch<Record<string, unknown>[]>(role, "/v3/policydefinitions/request", {
        method: "POST",
        body: { "@type": "QuerySpec" },
        apiKey,
      }),
  });
}

export function useCreatePolicy() {
  const { role, apiKey } = useRole();
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (policy: Record<string, unknown>) =>
      edcFetch(role, "/v3/policydefinitions", {
        method: "POST",
        body: policy,
        apiKey,
      }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["policies", role] }),
  });
}

// ── Contract Definitions ──

export function useContractDefs() {
  const { role, apiKey } = useRole();
  return useQuery({
    queryKey: ["contractdefs", role],
    queryFn: () =>
      edcFetch<Record<string, unknown>[]>(
        role,
        "/v3/contractdefinitions/request",
        { method: "POST", body: { "@type": "QuerySpec" }, apiKey }
      ),
  });
}

export function useCreateContractDef() {
  const { role, apiKey } = useRole();
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (def: Record<string, unknown>) =>
      edcFetch(role, "/v3/contractdefinitions", {
        method: "POST",
        body: def,
        apiKey,
      }),
    onSuccess: () =>
      qc.invalidateQueries({ queryKey: ["contractdefs", role] }),
  });
}

// ── Catalog ──

export function useCatalog() {
  const { role, apiKey } = useRole();
  return useMutation({
    mutationFn: (params: {
      counterPartyAddress: string;
      counterPartyId: string;
    }) =>
      edcFetch<Record<string, unknown>>(role, "/v3/catalog/request", {
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
  const { role, apiKey } = useRole();
  return useQuery({
    queryKey: ["negotiations", role],
    queryFn: () =>
      edcFetch<Record<string, unknown>[]>(
        role,
        "/v3/contractnegotiations/request",
        { method: "POST", body: { "@type": "QuerySpec" }, apiKey }
      ),
    refetchInterval: 3000,
  });
}

export function useNegotiation(id: string | null) {
  const { role, apiKey } = useRole();
  return useQuery({
    queryKey: ["negotiation", role, id],
    queryFn: () =>
      edcFetch<Record<string, unknown>>(
        role,
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
  const { role, apiKey } = useRole();
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (negotiation: Record<string, unknown>) =>
      edcFetch<Record<string, unknown>>(
        role,
        "/v3/contractnegotiations",
        { method: "POST", body: negotiation, apiKey }
      ),
    onSuccess: () =>
      qc.invalidateQueries({ queryKey: ["negotiations", role] }),
  });
}

// ── Transfers ──

export function useTransfers() {
  const { role, apiKey } = useRole();
  return useQuery({
    queryKey: ["transfers", role],
    queryFn: () =>
      edcFetch<Record<string, unknown>[]>(
        role,
        "/v3/transferprocesses/request",
        { method: "POST", body: { "@type": "QuerySpec" }, apiKey }
      ),
    refetchInterval: 3000,
  });
}

export function useTransfer(id: string | null) {
  const { role, apiKey } = useRole();
  return useQuery({
    queryKey: ["transfer", role, id],
    queryFn: () =>
      edcFetch<Record<string, unknown>>(
        role,
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
  const { role, apiKey } = useRole();
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (transfer: Record<string, unknown>) =>
      edcFetch<Record<string, unknown>>(role, "/v3/transferprocesses", {
        method: "POST",
        body: transfer,
        apiKey,
      }),
    onSuccess: () =>
      qc.invalidateQueries({ queryKey: ["transfers", role] }),
  });
}

// ── EDR ──

export function useEdrs(transferId: string | null) {
  const { role, apiKey } = useRole();
  return useQuery({
    queryKey: ["edrs", role, transferId],
    queryFn: () =>
      edcFetch<Record<string, unknown>>(
        role,
        `/v3/edrs/${transferId}/dataaddress`,
        { apiKey }
      ),
    enabled: !!transferId,
  });
}

// ── Generic data fetch (for EDR endpoint) ──

export async function fetchWithAuth(url: string, token: string) {
  const res = await fetch(url, {
    headers: { Authorization: `${token}` },
  });
  if (!res.ok) throw new Error(`Fetch error ${res.status}`);
  return res.text();
}
