import { useAssets } from "@/hooks/use-api";
import { AssetForm } from "@/components/asset-form";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";

export default function AssetsPage() {
  const { data: assets, isLoading, error } = useAssets();

  return (
    <div>
      <div className="mb-6 flex items-center justify-between">
        <h1 className="text-2xl font-bold">Assets</h1>
        <AssetForm />
      </div>
      {isLoading && <p className="text-muted-foreground">Loading...</p>}
      {error && (
        <p className="text-destructive">Error: {String(error)}</p>
      )}
      {assets && assets.length > 0 && (
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>ID</TableHead>
              <TableHead>Name</TableHead>
              <TableHead>Content Type</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {assets.map((asset) => {
              const props = (asset["properties"] ?? {}) as Record<
                string,
                unknown
              >;
              return (
                <TableRow key={String(asset["@id"])}>
                  <TableCell className="font-mono text-sm">
                    {String(asset["@id"] ?? "")}
                  </TableCell>
                  <TableCell>
                    {String(
                      props["name"] ??
                        props["https://w3id.org/edc/v0.0.1/ns/name"] ??
                        ""
                    )}
                  </TableCell>
                  <TableCell>
                    {String(
                      props["contenttype"] ??
                        props[
                          "https://w3id.org/edc/v0.0.1/ns/contenttype"
                        ] ??
                        ""
                    )}
                  </TableCell>
                </TableRow>
              );
            })}
          </TableBody>
        </Table>
      )}
      {assets && assets.length === 0 && (
        <p className="text-muted-foreground">No assets yet.</p>
      )}
    </div>
  );
}
