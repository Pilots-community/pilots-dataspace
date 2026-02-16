import { BrowserRouter, Routes, Route } from "react-router-dom";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { RoleProvider } from "@/hooks/use-role";
import { RootLayout } from "@/components/layout/root-layout";
import DashboardPage from "@/pages/dashboard";
import AssetsPage from "@/pages/assets";
import PoliciesPage from "@/pages/policies";
import ContractDefsPage from "@/pages/contract-defs";
import CatalogPage from "@/pages/catalog";
import NegotiationsPage from "@/pages/negotiations";
import TransfersPage from "@/pages/transfers";

const queryClient = new QueryClient({
  defaultOptions: {
    queries: { refetchOnWindowFocus: false, retry: 1 },
  },
});

export function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <RoleProvider>
        <BrowserRouter>
          <Routes>
            <Route element={<RootLayout />}>
              <Route path="/" element={<DashboardPage />} />
              <Route path="/assets" element={<AssetsPage />} />
              <Route path="/policies" element={<PoliciesPage />} />
              <Route path="/contract-defs" element={<ContractDefsPage />} />
              <Route path="/catalog" element={<CatalogPage />} />
              <Route path="/negotiations" element={<NegotiationsPage />} />
              <Route path="/transfers" element={<TransfersPage />} />
            </Route>
          </Routes>
        </BrowserRouter>
      </RoleProvider>
    </QueryClientProvider>
  );
}
