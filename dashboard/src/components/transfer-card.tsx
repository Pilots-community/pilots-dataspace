import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";

const stateVariant: Record<
  string,
  "default" | "info" | "warning" | "success" | "destructive" | "secondary"
> = {
  INITIAL: "secondary",
  PROVISIONING: "info",
  PROVISIONED: "info",
  REQUESTING: "info",
  REQUESTED: "info",
  STARTING: "warning",
  STARTED: "success",
  SUSPENDING: "warning",
  SUSPENDED: "warning",
  COMPLETING: "warning",
  COMPLETED: "success",
  TERMINATING: "destructive",
  TERMINATED: "destructive",
  DEPROVISIONING: "warning",
  DEPROVISIONED: "secondary",
};

interface TransferCardProps {
  transfer: Record<string, unknown>;
  onViewEdr?: (transferId: string) => void;
}

export function TransferCard({ transfer, onViewEdr }: TransferCardProps) {
  const id = String(transfer["@id"] ?? "");
  const state = String(transfer["state"] ?? "UNKNOWN");
  const type = String(transfer["type"] ?? "");

  return (
    <Card>
      <CardHeader className="pb-2">
        <div className="flex items-center justify-between">
          <CardTitle className="text-sm font-mono truncate max-w-[300px]">
            {id}
          </CardTitle>
          <div className="flex items-center gap-2">
            {type && (
              <Badge variant="outline">{type}</Badge>
            )}
            <Badge variant={stateVariant[state] ?? "secondary"}>{state}</Badge>
          </div>
        </div>
      </CardHeader>
      <CardContent>
        {(state === "STARTED" || state === "COMPLETED") && onViewEdr && (
          <Button size="sm" variant="outline" onClick={() => onViewEdr(id)}>
            View EDR
          </Button>
        )}
      </CardContent>
    </Card>
  );
}
