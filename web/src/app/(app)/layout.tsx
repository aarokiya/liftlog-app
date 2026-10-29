import { Nav } from "@/components/nav";
import { TimeZoneCookie } from "@/components/time-zone-cookie";

export default function AppLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="min-h-screen">
      <TimeZoneCookie />
      <Nav />
      <main className="mx-auto max-w-6xl px-4 py-6 md:py-8">{children}</main>
    </div>
  );
}
