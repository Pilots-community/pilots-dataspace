import { useQuery } from "@tanstack/react-query";
import { healthFetch } from "@/lib/api";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";

interface HealthCardProps {
  name: string;
  endpoint: string;
}

export function HealthCard({ name, endpoint }: HealthCardProps) {
  const { data, isLoading } = useQuery({
    queryKey: ["health", endpoint],
    queryFn: () => healthFetch(endpoint),
    refetchInterval: 5000,
  });

  const healthy = data?.isSystemHealthy === true;

  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-base">{name}</CardTitle>
      </CardHeader>
      <CardContent>
        {isLoading ? (
          <Badge variant="secondary">Checking...</Badge>
        ) : healthy ? (
          <Badge variant="success">Healthy</Badge>
        ) : (
          <Badge variant="destructive">Unhealthy</Badge>
        )}
      </CardContent>
    </Card>
  );
}
