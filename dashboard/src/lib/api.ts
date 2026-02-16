const EDC_CONTEXT = { "@vocab": "https://w3id.org/edc/v0.0.1/ns/" };

export type Role = "provider" | "consumer";

export async function edcFetch<T>(
  role: Role,
  path: string,
  options: {
    method?: string;
    body?: Record<string, unknown>;
    apiKey?: string;
  } = {}
): Promise<T> {
  const { method = "GET", body, apiKey } = options;
  const url = `/api/${role}${path}`;

  const headers: Record<string, string> = {
    "Content-Type": "application/json",
  };
  if (apiKey) {
    headers["x-api-key"] = apiKey;
  }

  const res = await fetch(url, {
    method,
    headers,
    body: body
      ? JSON.stringify({ "@context": EDC_CONTEXT, ...body })
      : undefined,
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`EDC API error ${res.status}: ${text}`);
  }

  const text = await res.text();
  if (!text) return undefined as T;
  return JSON.parse(text) as T;
}

export async function healthFetch(
  endpoint: string
): Promise<{ isSystemHealthy: boolean }> {
  try {
    const res = await fetch(`/api/health/${endpoint}`, {
      signal: AbortSignal.timeout(3000),
    });
    if (!res.ok) return { isSystemHealthy: false };
    return await res.json();
  } catch {
    return { isSystemHealthy: false };
  }
}
