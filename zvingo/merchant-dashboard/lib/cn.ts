import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

/**
 * Merge Tailwind class names, with later classes winning conflicts.
 * Lives outside the component tree so it can be used from both Server and
 * Client Components (a `"use client"` module cannot export it to the server).
 */
export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export type { ClassValue };
