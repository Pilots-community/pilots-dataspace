import { createContext, useContext } from "react";

type ToastFn = (msg: {
  title: string;
  description?: string;
  variant?: "default" | "destructive";
}) => void;

export const ToastContext = createContext<ToastFn | null>(null);

export function useToastContext() {
  const ctx = useContext(ToastContext);
  if (!ctx) throw new Error("useToastContext must be used within RootLayout");
  return ctx;
}
