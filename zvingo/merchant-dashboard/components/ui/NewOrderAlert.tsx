"use client";

import * as React from "react";
import { BellOff, BellRing, Clock3, Volume2 } from "lucide-react";
import { cn } from "@/lib/cn";
import { Button } from "./Button";
import { formatDuration, minutesSince, pluralise } from "@/lib/format";
import { useLocalStorage, useNow } from "@/lib/hooks";

const MUTE_STORAGE_KEY = "zvingo_order_alert_muted";

export interface OrderAlertSound {
  /** True once the browser will actually let us make a sound. */
  ready: boolean;
  muted: boolean;
  setMuted: (muted: boolean) => void;
  /** Play the two-tone chime. No-op when muted or not yet armed. */
  play: () => void;
  /** Call from a real user gesture to satisfy autoplay policy. */
  arm: () => void;
}

/**
 * Audible new-order alert.
 *
 * Browsers refuse to start audio before a user gesture, so the hook stays
 * "not ready" until the merchant interacts with the page once — the UI asks
 * for that interaction explicitly instead of failing silently. The mute choice
 * is persisted per browser so a noisy kitchen can turn it off for good.
 */
export function useOrderAlertSound(): OrderAlertSound {
  const [muted, setMutedState] = useLocalStorage<boolean>(MUTE_STORAGE_KEY, false);
  const [ready, setReady] = React.useState(false);
  const contextRef = React.useRef<AudioContext | null>(null);

  const ensureContext = React.useCallback((): AudioContext | null => {
    if (typeof window === "undefined") return null;
    if (!contextRef.current) {
      const Ctor =
        window.AudioContext ??
        (window as Window & { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
      if (!Ctor) return null;
      try {
        contextRef.current = new Ctor();
      } catch {
        return null;
      }
    }
    return contextRef.current;
  }, []);

  const arm = React.useCallback(() => {
    const context = ensureContext();
    if (!context) return;
    void context
      .resume()
      .then(() => setReady(context.state === "running"))
      .catch(() => setReady(false));
  }, [ensureContext]);

  // Any genuine interaction with the page arms audio for the rest of the session.
  React.useEffect(() => {
    if (ready) return;
    const handler = () => arm();
    window.addEventListener("pointerdown", handler, { once: true });
    window.addEventListener("keydown", handler, { once: true });
    return () => {
      window.removeEventListener("pointerdown", handler);
      window.removeEventListener("keydown", handler);
    };
  }, [ready, arm]);

  React.useEffect(() => {
    const context = contextRef.current;
    return () => {
      void context?.close().catch(() => undefined);
    };
  }, []);

  const play = React.useCallback(() => {
    if (muted) return;
    const context = ensureContext();
    if (!context || context.state !== "running") return;
    // Two rising tones — distinct from a phone notification, audible over a kitchen.
    [
      { at: 0, frequency: 740 },
      { at: 0.18, frequency: 988 },
    ].forEach(({ at, frequency }) => {
      const oscillator = context.createOscillator();
      const gain = context.createGain();
      oscillator.type = "sine";
      oscillator.frequency.value = frequency;
      oscillator.connect(gain);
      gain.connect(context.destination);
      const start = context.currentTime + at;
      gain.gain.setValueAtTime(0.0001, start);
      gain.gain.exponentialRampToValueAtTime(0.22, start + 0.02);
      gain.gain.exponentialRampToValueAtTime(0.0001, start + 0.38);
      oscillator.start(start);
      oscillator.stop(start + 0.4);
    });
  }, [muted, ensureContext]);

  const setMuted = React.useCallback(
    (next: boolean) => {
      setMutedState(next);
      if (!next) arm();
    },
    [setMutedState, arm],
  );

  // Stable identity so consumers can safely depend on it in effects.
  return React.useMemo(
    () => ({ ready, muted, setMuted, play, arm }),
    [ready, muted, setMuted, play, arm],
  );
}

export interface NewOrderAlertProps {
  /** How many orders are waiting to be accepted. 0 hides the alert. */
  count: number;
  /** ISO timestamp of the oldest waiting order — drives the waiting timer. */
  oldestCreatedAt?: string | null;
  /**
   * The only way to clear the alert: it must take the merchant to the orders
   * that need them. Deliberately not a dismiss — a missed order is lost revenue.
   */
  onReview: () => void;
  reviewLabel?: string;
  /** Pass the shared sound controller so one chime serves the whole app. */
  sound?: OrderAlertSound;
  /** Anchor position. `top` sits under the header; `bottom` is a dock bar. */
  position?: "top" | "bottom" | "inline";
  className?: string;
}

/**
 * The revenue-critical alert. Visual pulse + audible chime, persistent until
 * the merchant actually opens the orders. There is no close button: the alert
 * cannot be dismissed by a stray tap, only by acting on it.
 */
export function NewOrderAlert({
  count,
  oldestCreatedAt,
  onReview,
  reviewLabel,
  sound,
  position = "top",
  className,
}: NewOrderAlertProps) {
  const fallbackSound = useOrderAlertSound();
  const audio = sound ?? fallbackSound;
  const now = useNow(15_000);
  const waited = oldestCreatedAt ? minutesSince(oldestCreatedAt, now) : 0;

  // Chime once when the queue grows, then re-chime while orders sit unaccepted
  // so the alert survives a walk away from the counter. Every 20s, no faster.
  const previousCount = React.useRef(0);
  const { play, muted, ready } = audio;

  React.useEffect(() => {
    const grew = count > previousCount.current;
    previousCount.current = count;
    if (count <= 0 || muted || !ready) return;
    if (grew) play();
    const id = window.setInterval(() => play(), 20_000);
    return () => window.clearInterval(id);
  }, [count, muted, ready, play]);

  if (count <= 0) return null;

  const label = reviewLabel ?? `Review ${pluralise(count, "order")}`;

  return (
    <div
      role="alert"
      aria-live="assertive"
      className={cn(
        "z-40",
        position === "top" && "sticky top-0",
        position === "bottom" && "sticky bottom-0 shadow-dock",
        className,
      )}
    >
      <div
        className={cn(
          "zv-alert-ring flex flex-wrap items-center gap-x-4 gap-y-3 border-b border-error/30 bg-error-surface px-4 py-3 sm:px-6",
          position === "bottom" && "border-b-0 border-t",
          position === "inline" && "rounded-lg border",
        )}
      >
        <span
          aria-hidden="true"
          className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-error text-neutral-0"
        >
          <BellRing className="zv-alert-bell h-5 w-5" />
        </span>

        <div className="min-w-0 flex-1">
          <p className="type-h3 text-neutral-900">
            {count === 1 ? "1 new order is waiting" : `${count} new orders are waiting`}
          </p>
          <p className="type-caption mt-0.5 flex flex-wrap items-center gap-x-3 gap-y-1 text-text-secondary">
            {oldestCreatedAt && (
              <span className="inline-flex items-center gap-1.5 tabular-figures">
                <Clock3 className="h-3.5 w-3.5" aria-hidden="true" />
                Oldest waiting {formatDuration(waited)}
              </span>
            )}
            <span>Accept or reject so the customer knows what is happening.</span>
          </p>
        </div>

        <div className="flex shrink-0 items-center gap-2">
          {!audio.ready && !audio.muted && (
            <Button
              variant="secondary"
              size="sm"
              onClick={audio.arm}
              leftIcon={<Volume2 className="h-4 w-4" />}
              title="Browsers need one tap before they will play a sound"
            >
              Turn on sound
            </Button>
          )}

          <Button
            variant="tertiary"
            size="sm"
            aria-pressed={audio.muted}
            onClick={() => audio.setMuted(!audio.muted)}
            leftIcon={
              audio.muted ? <BellOff className="h-4 w-4" /> : <BellRing className="h-4 w-4" />
            }
          >
            {audio.muted ? "Sound off" : "Sound on"}
          </Button>

          <Button variant="destructive" size="md" onClick={onReview}>
            {label}
          </Button>
        </div>
      </div>
    </div>
  );
}
