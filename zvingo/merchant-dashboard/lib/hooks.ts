"use client";

import * as React from "react";

/** `useLayoutEffect` on the client, `useEffect` on the server (no SSR warning). */
export const useIsomorphicLayoutEffect =
  typeof window !== "undefined" ? React.useLayoutEffect : React.useEffect;

/** True once the component has mounted in the browser. */
export function useIsMounted(): boolean {
  const [mounted, setMounted] = React.useState(false);
  React.useEffect(() => setMounted(true), []);
  return mounted;
}

/** Subscribe to a media query, e.g. `useMediaQuery("(min-width: 1024px)")`. */
export function useMediaQuery(query: string): boolean {
  const subscribe = React.useCallback(
    (onChange: () => void) => {
      if (typeof window === "undefined" || !window.matchMedia) return () => {};
      const mql = window.matchMedia(query);
      mql.addEventListener("change", onChange);
      return () => mql.removeEventListener("change", onChange);
    },
    [query],
  );
  const getSnapshot = React.useCallback(() => {
    if (typeof window === "undefined" || !window.matchMedia) return false;
    return window.matchMedia(query).matches;
  }, [query]);
  // Server renders the "narrow" branch; the client corrects on hydration.
  return React.useSyncExternalStore(subscribe, getSnapshot, () => false);
}

/** DESIGN_SYSTEM §4.4 — honour the OS reduced-motion preference in JS-driven motion. */
export function usePrefersReducedMotion(): boolean {
  return useMediaQuery("(prefers-reduced-motion: reduce)");
}

/**
 * State backed by localStorage. Falls back to in-memory state when storage is
 * unavailable (private mode) so nothing ever throws during render.
 */
export function useLocalStorage<T>(key: string, initialValue: T) {
  const [value, setValue] = React.useState<T>(initialValue);
  const [hydrated, setHydrated] = React.useState(false);

  React.useEffect(() => {
    try {
      const raw = window.localStorage.getItem(key);
      if (raw !== null) setValue(JSON.parse(raw) as T);
    } catch {
      /* storage blocked — keep the initial value */
    }
    setHydrated(true);
  }, [key]);

  const set = React.useCallback(
    (next: T | ((prev: T) => T)) => {
      setValue((prev) => {
        const resolved = typeof next === "function" ? (next as (p: T) => T)(prev) : next;
        try {
          window.localStorage.setItem(key, JSON.stringify(resolved));
        } catch {
          /* storage blocked — value still lives in memory for this session */
        }
        return resolved;
      });
    },
    [key],
  );

  return [value, set, hydrated] as const;
}

/** Call `handler` on a pointer press outside every supplied ref. */
export function useOnClickOutside(
  refs: Array<React.RefObject<HTMLElement | null>>,
  handler: (event: MouseEvent | TouchEvent) => void,
  enabled = true,
) {
  const saved = React.useRef(handler);
  useIsomorphicLayoutEffect(() => {
    saved.current = handler;
  });

  React.useEffect(() => {
    if (!enabled) return;
    const listener = (event: MouseEvent | TouchEvent) => {
      const target = event.target as Node | null;
      if (!target) return;
      for (const ref of refs) {
        if (ref.current?.contains(target)) return;
      }
      saved.current(event);
    };
    document.addEventListener("mousedown", listener);
    document.addEventListener("touchstart", listener, { passive: true });
    return () => {
      document.removeEventListener("mousedown", listener);
      document.removeEventListener("touchstart", listener);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [enabled, ...refs]);
}

/** Run `handler` when Escape is pressed anywhere. */
export function useEscapeKey(handler: () => void, enabled = true) {
  const saved = React.useRef(handler);
  useIsomorphicLayoutEffect(() => {
    saved.current = handler;
  });
  React.useEffect(() => {
    if (!enabled) return;
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        event.stopPropagation();
        saved.current();
      }
    };
    document.addEventListener("keydown", onKeyDown);
    return () => document.removeEventListener("keydown", onKeyDown);
  }, [enabled]);
}

/** Prevent background scroll while an overlay is open, without layout shift. */
export function useLockBodyScroll(locked: boolean) {
  React.useEffect(() => {
    if (!locked) return;
    const { body, documentElement } = document;
    const previousOverflow = body.style.overflow;
    const previousPadding = body.style.paddingRight;
    const scrollbar = window.innerWidth - documentElement.clientWidth;
    body.style.overflow = "hidden";
    if (scrollbar > 0) body.style.paddingRight = `${scrollbar}px`;
    return () => {
      body.style.overflow = previousOverflow;
      body.style.paddingRight = previousPadding;
    };
  }, [locked]);
}

const FOCUSABLE = [
  "a[href]",
  "button:not([disabled])",
  "input:not([disabled]):not([type=hidden])",
  "select:not([disabled])",
  "textarea:not([disabled])",
  "[tabindex]:not([tabindex='-1'])",
].join(",");

export function getFocusable(container: HTMLElement): HTMLElement[] {
  return Array.from(container.querySelectorAll<HTMLElement>(FOCUSABLE)).filter(
    (el) => el.offsetParent !== null || el === document.activeElement,
  );
}

/**
 * Trap focus inside `ref` while `active`, move focus in on open and restore it
 * to the previously focused element on close (DESIGN_SYSTEM §5.4 / WCAG 2.4.3).
 */
export function useFocusTrap(ref: React.RefObject<HTMLElement | null>, active: boolean) {
  React.useEffect(() => {
    if (!active) return;
    const container = ref.current;
    if (!container) return;

    const previouslyFocused = document.activeElement as HTMLElement | null;

    const focusFirst = () => {
      const targets = getFocusable(container);
      const initial =
        container.querySelector<HTMLElement>("[data-autofocus]") ?? targets[0] ?? container;
      initial.focus({ preventScroll: true });
    };
    // Wait a frame so entrance animations do not fight the scroll-into-view.
    const raf = requestAnimationFrame(focusFirst);

    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key !== "Tab") return;
      const targets = getFocusable(container);
      if (!targets.length) {
        event.preventDefault();
        return;
      }
      const first = targets[0]!;
      const last = targets[targets.length - 1]!;
      const active2 = document.activeElement;
      if (event.shiftKey && (active2 === first || !container.contains(active2))) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && active2 === last) {
        event.preventDefault();
        first.focus();
      }
    };

    container.addEventListener("keydown", onKeyDown);
    return () => {
      cancelAnimationFrame(raf);
      container.removeEventListener("keydown", onKeyDown);
      previouslyFocused?.focus?.({ preventScroll: true });
    };
  }, [ref, active]);
}

/**
 * Animate a number towards `value` over `duration` (DESIGN_SYSTEM §4.3 —
 * money and counters cross-fade/count, never hard-swap). Returns the current
 * display value. Honours reduced motion by snapping immediately.
 */
export function useCountUp(value: number, duration = 260): number {
  const reduced = usePrefersReducedMotion();
  const [display, setDisplay] = React.useState(value);
  const fromRef = React.useRef(value);
  const frameRef = React.useRef<number | null>(null);

  React.useEffect(() => {
    if (reduced || duration <= 0) {
      fromRef.current = value;
      setDisplay(value);
      return;
    }
    const from = fromRef.current;
    if (from === value) return;
    const start = performance.now();

    const tick = (now: number) => {
      const t = Math.min(1, (now - start) / duration);
      // ease/standard, approximated for scalar interpolation
      const eased = 1 - Math.pow(1 - t, 3);
      const next = from + (value - from) * eased;
      setDisplay(next);
      if (t < 1) {
        frameRef.current = requestAnimationFrame(tick);
      } else {
        fromRef.current = value;
        setDisplay(value);
      }
    };

    frameRef.current = requestAnimationFrame(tick);
    return () => {
      if (frameRef.current !== null) cancelAnimationFrame(frameRef.current);
      fromRef.current = value;
    };
  }, [value, duration, reduced]);

  return display;
}

/** A ticking clock for "x min ago" labels. Re-renders every `intervalMs`. */
export function useNow(intervalMs = 30_000): number {
  const [now, setNow] = React.useState(() => Date.now());
  React.useEffect(() => {
    const id = window.setInterval(() => setNow(Date.now()), intervalMs);
    return () => window.clearInterval(id);
  }, [intervalMs]);
  return now;
}
