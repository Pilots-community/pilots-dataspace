import {
  createContext,
  useContext,
  useState,
  useCallback,
  type ReactNode,
} from "react";
import { createElement } from "react";
import type { Role } from "@/lib/api";

interface RoleContextValue {
  role: Role;
  setRole: (role: Role) => void;
  apiKey: string;
  setApiKey: (key: string) => void;
}

const RoleContext = createContext<RoleContextValue | null>(null);

export function RoleProvider({ children }: { children: ReactNode }) {
  const [role, setRoleState] = useState<Role>(
    () => (localStorage.getItem("edc-role") as Role) || "provider"
  );
  const [apiKey, setApiKeyState] = useState(
    () => localStorage.getItem("edc-api-key") || "password"
  );

  const setRole = useCallback((r: Role) => {
    setRoleState(r);
    localStorage.setItem("edc-role", r);
  }, []);

  const setApiKey = useCallback((k: string) => {
    setApiKeyState(k);
    localStorage.setItem("edc-api-key", k);
  }, []);

  return createElement(
    RoleContext.Provider,
    { value: { role, setRole, apiKey, setApiKey } },
    children
  );
}

export function useRole() {
  const ctx = useContext(RoleContext);
  if (!ctx) throw new Error("useRole must be used within RoleProvider");
  return ctx;
}
