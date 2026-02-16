import { HealthCard } from "@/components/health-card";

const services = [
  { name: "Provider Control Plane", endpoint: "provider-cp" },
  { name: "Consumer Control Plane", endpoint: "consumer-cp" },
  { name: "Provider Data Plane", endpoint: "provider-dp" },
  { name: "Consumer Data Plane", endpoint: "consumer-dp" },
  { name: "Provider IdentityHub", endpoint: "provider-ih" },
  { name: "Consumer IdentityHub", endpoint: "consumer-ih" },
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
