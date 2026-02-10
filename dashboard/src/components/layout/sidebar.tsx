import { NavLink } from "react-router-dom";
import {
  LayoutDashboard,
  Database,
  Shield,
  FileText,
  Search,
  Handshake,
  ArrowRightLeft,
} from "lucide-react";
import { cn } from "@/lib/utils";

const links = [
  { to: "/", label: "Dashboard", icon: LayoutDashboard },
  { to: "/assets", label: "Assets", icon: Database },
  { to: "/policies", label: "Policies", icon: Shield },
  { to: "/contract-defs", label: "Contract Defs", icon: FileText },
  { to: "/catalog", label: "Catalog", icon: Search },
  { to: "/negotiations", label: "Negotiations", icon: Handshake },
  { to: "/transfers", label: "Transfers", icon: ArrowRightLeft },
];

export function Sidebar() {
  return (
    <aside className="flex h-screen w-60 flex-col border-r bg-card">
      <div className="flex h-14 items-center border-b px-4">
        <span className="text-lg font-bold">EDC Dataspace</span>
      </div>
      <nav className="flex-1 space-y-1 p-2">
        {links.map((link) => (
          <NavLink
            key={link.to}
            to={link.to}
            end={link.to === "/"}
            className={({ isActive }) =>
              cn(
                "flex items-center gap-3 rounded-md px-3 py-2 text-sm font-medium transition-colors",
                isActive
                  ? "bg-primary text-primary-foreground"
                  : "text-muted-foreground hover:bg-accent hover:text-accent-foreground"
              )
            }
          >
            <link.icon className="h-4 w-4" />
            {link.label}
          </NavLink>
        ))}
      </nav>
    </aside>
  );
}
