import { useApiKey } from "@/hooks/use-role";
import { Input } from "@/components/ui/input";

export function Topbar() {
  const { apiKey, setApiKey } = useApiKey();

  return (
    <header className="flex h-14 items-center justify-between border-b bg-card px-6">
      <div className="text-sm text-muted-foreground">
        Connector Dashboard
      </div>
      <div className="flex items-center gap-4">
        <Input
          className="w-[200px]"
          placeholder="API Key"
          value={apiKey}
          onChange={(e) => setApiKey(e.target.value)}
        />
      </div>
    </header>
  );
}
