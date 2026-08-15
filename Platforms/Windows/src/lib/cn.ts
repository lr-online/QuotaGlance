// Concatenate class names; rejects falsy values. Mirrors the `cn`
// utility baked into shadcn/ui. Used everywhere a className is built
// dynamically.

import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]): string {
  return twMerge(clsx(inputs));
}
