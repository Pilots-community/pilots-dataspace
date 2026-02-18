import { HealthCard } from "@/components/health-card";

const services = [
  { name: "Control Plane", endpoint: "cp" },
  { name: "Data Plane", endpoint: "dp" },
  { name: "Identity Hub", endpoint: "ih" },
];

export default function DashboardPage() {
  return (
    <div>
      <h1 className="mb-6 text-2xl font-bold">Service Health</h1>
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {services.map((s) => (
          <HealthCard key={s.endpoint} name={s.name} endpoint={s.endpoint} />
        ))}
      </div>
    </div>
  );
}
