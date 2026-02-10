import { usePolicies } from "@/hooks/use-api";
import { PolicyForm } from "@/components/policy-form";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";

export default function PoliciesPage() {
  const { data: policies, isLoading, error } = usePolicies();

  return (
    <div>
      <div className="mb-6 flex items-center justify-between">
        <h1 className="text-2xl font-bold">Policy Definitions</h1>
        <PolicyForm />
      </div>
      {isLoading && <p className="text-muted-foreground">Loading...</p>}
      {error && (
        <p className="text-destructive">Error: {String(error)}</p>
      )}
      {policies && policies.length > 0 && (
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>ID</TableHead>
              <TableHead>Type</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {policies.map((policy) => {
              const inner = (policy["policy"] ?? {}) as Record<
                string,
                unknown
              >;
              return (
                <TableRow key={String(policy["@id"])}>
                  <TableCell className="font-mono text-sm">
                    {String(policy["@id"] ?? "")}
                  </TableCell>
                  <TableCell>{String(inner["@type"] ?? "")}</TableCell>
                </TableRow>
              );
            })}
          </TableBody>
        </Table>
      )}
      {policies && policies.length === 0 && (
        <p className="text-muted-foreground">No policies yet.</p>
      )}
    </div>
  );
}
