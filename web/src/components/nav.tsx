"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

const NAV = [
  { href: "/", label: "Dashboard" },
  { href: "/stats", label: "Stats" },
  { href: "/food", label: "Food" },
  { href: "/workouts", label: "Workouts" },
  { href: "/programs", label: "Programs" },
  { href: "/routines", label: "Routines" },
  { href: "/exercises", label: "Exercises" },
  { href: "/import", label: "Import" },
  { href: "/settings", label: "Settings" },
];

export function Nav() {
  const path = usePathname();
  const active = (href: string) => (href === "/" ? path === "/" : path.startsWith(href));
  return (
    <header className="sticky top-0 z-20 border-b border-border bg-background/80 backdrop-blur">
      <div className="mx-auto flex max-w-6xl items-center gap-2 px-4 py-2.5">
        <Link href="/" className="mr-2 flex items-center gap-2 font-semibold tracking-tight">
          <span className="grid h-7 w-7 place-items-center rounded-lg bg-accent text-sm text-white">L</span>
          <span className="hidden sm:inline">LiftLog</span>
        </Link>
        <nav className="-mx-1 flex flex-1 gap-1 overflow-x-auto text-sm [scrollbar-width:none]">
          {NAV.map((n) => (
            <Link
              key={n.href}
              href={n.href}
              className={`whitespace-nowrap rounded-lg px-3 py-1.5 transition ${
                active(n.href) ? "bg-accent-soft font-medium text-accent" : "text-muted hover:text-foreground"
              }`}
            >
              {n.label}
            </Link>
          ))}
        </nav>
        <form action="/auth/signout" method="post">
          <button className="whitespace-nowrap rounded-lg px-2 py-1.5 text-sm text-muted hover:text-foreground">Sign out</button>
        </form>
      </div>
    </header>
  );
}
