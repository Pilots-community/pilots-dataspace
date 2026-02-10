import { Outlet } from "react-router-dom";
import { Sidebar } from "./sidebar";
import { Topbar } from "./topbar";
import {
  ToastProvider,
  ToastViewport,
  Toast,
  ToastTitle,
  ToastDescription,
  ToastClose,
} from "@/components/ui/toast";
import { useToast } from "@/hooks/use-toast";
import { ToastContext } from "@/hooks/use-toast-context";

export function RootLayout() {
  const { toasts, toast, dismiss } = useToast();

  return (
    <ToastContext.Provider value={toast}>
      <ToastProvider>
        <div className="flex h-screen">
          <Sidebar />
          <div className="flex flex-1 flex-col overflow-hidden">
            <Topbar />
            <main className="flex-1 overflow-auto p-6">
              <Outlet />
            </main>
          </div>
        </div>
        {toasts.map((t) => (
          <Toast
            key={t.id}
            variant={t.variant}
            open
            onOpenChange={(open) => {
              if (!open) dismiss(t.id);
            }}
          >
            <div className="grid gap-1">
              <ToastTitle>{t.title}</ToastTitle>
              {t.description && (
                <ToastDescription>{t.description}</ToastDescription>
              )}
            </div>
            <ToastClose />
          </Toast>
        ))}
        <ToastViewport />
      </ToastProvider>
    </ToastContext.Provider>
  );
}
