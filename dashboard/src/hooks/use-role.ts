import {
  createContext,
  useContext,
  useState,
  useCallback,
  type ReactNode,
} from "react";
import { createElement } from "react";

interface ApiKeyContextValue {
  apiKey: string;
  setApiKey: (key: string) => void;
}

const ApiKeyContext = createContext<ApiKeyContextValue | null>(null);

export function ApiKeyProvider({ children }: { children: ReactNode }) {
  const [apiKey, setApiKeyState] = useState(
    () => localStorage.getItem("edc-api-key") || "password"
  );

  const setApiKey = useCallback((k: string) => {
    setApiKeyState(k);
    localStorage.setItem("edc-api-key", k);
  }, []);

  return createElement(
    ApiKeyContext.Provider,
    { value: { apiKey, setApiKey } },
    children
  );
}

export function useApiKey() {
  const ctx = useContext(ApiKeyContext);
  if (!ctx) throw new Error("useApiKey must be used within ApiKeyProvider");
  return ctx;
}
