import { useContractDefs } from "@/hooks/use-api";
import { ContractDefForm } from "@/components/contract-def-form";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";

export default function ContractDefsPage() {
  const { data: defs, isLoading, error } = useContractDefs();

  return (
    <div>
      <div className="mb-6 flex items-center justify-between">
        <h1 className="text-2xl font-bold">Contract Definitions</h1>
        <ContractDefForm />
      </div>
      {isLoading && <p className="text-muted-foreground">Loading...</p>}
      {error && (
        <p className="text-destructive">Error: {String(error)}</p>
      )}
      {defs && defs.length > 0 && (
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>ID</TableHead>
              <TableHead>Access Policy</TableHead>
              <TableHead>Contract Policy</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {defs.map((def) => (
              <TableRow key={String(def["@id"])}>
                <TableCell className="font-mono text-sm">
                  {String(def["@id"] ?? "")}
                </TableCell>
                <TableCell className="font-mono text-sm">
                  {String(def["accessPolicyId"] ?? "")}
                </TableCell>
                <TableCell className="font-mono text-sm">
                  {String(def["contractPolicyId"] ?? "")}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      )}
      {defs && defs.length === 0 && (
        <p className="text-muted-foreground">No contract definitions yet.</p>
      )}
    </div>
  );
}
