import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { useCreateAsset } from "@/hooks/use-api";
import { useToastContext } from "@/hooks/use-toast-context";

export function AssetForm() {
  const [open, setOpen] = useState(false);
  const [id, setId] = useState("");
  const [name, setName] = useState("");
  const [contentType, setContentType] = useState("application/json");
  const [baseUrl, setBaseUrl] = useState("");
  const create = useCreateAsset();
  const toast = useToastContext();

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    create.mutate(
      {
        "@id": id,
        properties: { name, contenttype: contentType },
        dataAddress: {
          type: "HttpData",
          baseUrl,
        },
      },
      {
        onSuccess: () => {
          toast({ title: "Asset created", description: id });
          setOpen(false);
          setId("");
          setName("");
          setBaseUrl("");
        },
        onError: (err) =>
          toast({
            title: "Failed to create asset",
            description: String(err),
            variant: "destructive",
          }),
      }
    );
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button>Create Asset</Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Create Asset</DialogTitle>
        </DialogHeader>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <Label htmlFor="asset-id">Asset ID</Label>
            <Input
              id="asset-id"
              value={id}
              onChange={(e) => setId(e.target.value)}
              required
            />
          </div>
          <div>
            <Label htmlFor="asset-name">Name</Label>
            <Input
              id="asset-name"
              value={name}
              onChange={(e) => setName(e.target.value)}
              required
            />
          </div>
          <div>
            <Label htmlFor="asset-ct">Content Type</Label>
            <Input
              id="asset-ct"
              value={contentType}
              onChange={(e) => setContentType(e.target.value)}
            />
          </div>
          <div>
            <Label htmlFor="asset-url">Data Source URL</Label>
            <Input
              id="asset-url"
              value={baseUrl}
              onChange={(e) => setBaseUrl(e.target.value)}
              placeholder="https://example.com/data"
              required
            />
          </div>
          <Button type="submit" disabled={create.isPending} className="w-full">
            {create.isPending ? "Creating..." : "Create"}
          </Button>
        </form>
      </DialogContent>
    </Dialog>
  );
}
