"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";

export default function Home() {
  const router = useRouter();

  useEffect(() => {
    const token = localStorage.getItem("zvingo_token");
    if (token) {
      router.replace("/dashboard");
    } else {
      router.replace("/login");
    }
  }, [router]);

  return (
    <div className="min-h-screen flex items-center justify-center bg-neutral-900">
      <div className="text-center">
        <div className="mx-auto flex h-12 w-12 items-center justify-center rounded-2xl bg-[#d7f654] text-xl font-black text-neutral-900">Z</div>
        <div className="mx-auto mt-5 h-1 w-20 overflow-hidden rounded-full bg-white/10"><div className="h-full w-1/2 animate-pulse rounded-full bg-[#d7f654]" /></div>
        <p className="mt-4 text-sm font-semibold text-neutral-400">Opening Zvingo Partner…</p>
      </div>
    </div>
  );
}
