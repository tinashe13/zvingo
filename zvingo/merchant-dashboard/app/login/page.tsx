"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { LogIn } from "lucide-react";
import { Button, Input, Skeleton } from "@/components/ui";
import { clearApiCache } from "@/lib/useApi";
import { toE164 } from "@/lib/format";
import { AuthLink, AuthShell } from "../_auth/AuthShell";
import {
  clearSession,
  DEFAULT_SIGNED_IN_PATH,
  getRefreshToken,
  hasAccessToken,
  isAuthRequestError,
  persistSession,
  readQueryParam,
  refreshSession,
  safeNextPath,
  signIn,
  stripQueryParam,
} from "../_auth/session";
import { FormBanner, PasswordField, RateLimitNotice, useRetryCountdown } from "../_auth/ui";

type Phase = "checking" | "restoring" | "form";
type Notice = "none" | "reset" | "expired" | "restore_failed";

/** A silent refresh that immediately 401s again would loop; only try one per window. */
const RESTORE_GUARD_KEY = "zvingo_session_restore_at";
const RESTORE_GUARD_MS = 15_000;

function restoreAttemptedRecently(): boolean {
  try {
    const raw = window.sessionStorage.getItem(RESTORE_GUARD_KEY);
    const at = raw ? Number(raw) : NaN;
    return Number.isFinite(at) && Date.now() - at < RESTORE_GUARD_MS;
  } catch {
    return false;
  }
}

function markRestoreAttempt() {
  try {
    window.sessionStorage.setItem(RESTORE_GUARD_KEY, String(Date.now()));
  } catch {
    /* session storage blocked — the worst case is one extra refresh attempt */
  }
}

/**
 * `tino@shop.co.zw` stays as typed; `077 123 4567` becomes `+263771234567`,
 * which is the exact string `AuthService.authenticate_user` looks up.
 */
function normaliseIdentifier(raw: string): string {
  const value = raw.trim();
  if (!value) return "";
  if (value.includes("@")) return value.toLowerCase();
  return toE164(value) ?? value;
}

export default function LoginPage() {
  const router = useRouter();

  const [phase, setPhase] = React.useState<Phase>("checking");
  const [notice, setNotice] = React.useState<Notice>("none");
  const [nextPath, setNextPath] = React.useState<string>(DEFAULT_SIGNED_IN_PATH);

  const [identifier, setIdentifier] = React.useState("");
  const [password, setPassword] = React.useState("");
  const [fieldErrors, setFieldErrors] = React.useState<{ identifier?: string; password?: string }>({});
  const [formError, setFormError] = React.useState<string | null>(null);
  const [retryAfter, setRetryAfter] = React.useState<number | null>(null);
  const [submitting, setSubmitting] = React.useState(false);

  const cooldown = useRetryCountdown(retryAfter);

  // Decide, once, whether this visitor needs the form at all: an unexpired
  // session goes straight through, and a session `lib/api.ts` just cleared on a
  // 401 is rebuilt from the rotating refresh token instead of asking a manager
  // to type their password in the middle of service.
  React.useEffect(() => {
    let cancelled = false;
    const nextParam = readQueryParam("next");
    const target = safeNextPath(nextParam);
    setNextPath(target);

    if (readQueryParam("reset") === "1") {
      setNotice("reset");
      stripQueryParam("reset");
    }

    if (hasAccessToken()) {
      router.replace(target);
      return;
    }

    // `?next=` means something bounced the user here mid-task — that is the
    // case worth restoring silently. Arriving at a bare /login is a deliberate
    // visit (signing out lands here), so the stored refresh token is dropped
    // rather than used to sign the user straight back in.
    if (nextParam === null) {
      clearSession();
      setPhase("form");
      return;
    }

    if (!getRefreshToken() || restoreAttemptedRecently()) {
      setPhase("form");
      if (getRefreshToken()) setNotice("restore_failed");
      return;
    }

    markRestoreAttempt();
    setPhase("restoring");
    refreshSession().then((token) => {
      if (cancelled) return;
      if (token) {
        router.replace(target);
        return;
      }
      setPhase("form");
      setNotice((current) => (current === "reset" ? current : "expired"));
    });

    return () => {
      cancelled = true;
    };
  }, [router]);

  const validate = React.useCallback(() => {
    const errors: { identifier?: string; password?: string } = {};
    if (!identifier.trim()) {
      errors.identifier = "Enter the email address or phone number on your account.";
    }
    if (!password) {
      errors.password = "Enter your password.";
    }
    setFieldErrors(errors);
    return Object.keys(errors).length === 0;
  }, [identifier, password]);

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    if (submitting || cooldown > 0) return;
    setFormError(null);
    if (!validate()) return;

    setSubmitting(true);
    try {
      const token = await signIn(normaliseIdentifier(identifier), password);
      persistSession(token);
      // Drop anything the previous session left in the shared SWR cache so the
      // dashboard cannot render the last merchant's name for a frame.
      clearApiCache();
      router.replace(nextPath);
    } catch (error) {
      if (isAuthRequestError(error)) {
        if (error.kind === "rate_limited") {
          setRetryAfter(error.retryAfterSeconds ?? 60);
          setFormError(null);
        } else {
          setRetryAfter(null);
          setFormError(error.message);
        }
      } else {
        setRetryAfter(null);
        setFormError("Something went wrong signing you in. Please try again.");
      }
      setSubmitting(false);
    }
  }

  if (phase !== "form") {
    return (
      <AuthShell
        title={phase === "restoring" ? "Picking up where you left off" : "Checking your session"}
        description="One moment — we are restoring your Zvingo Partner session."
      >
        <div className="flex flex-col gap-4" role="status" aria-busy="true">
          <Skeleton className="h-4 w-32" shape="text" />
          <Skeleton className="h-13 w-full" />
          <Skeleton className="h-4 w-24" shape="text" />
          <Skeleton className="h-13 w-full" />
          <Skeleton className="h-13 w-full" />
          <span className="zv-sr-only">Restoring your session</span>
        </div>
      </AuthShell>
    );
  }

  return (
    <AuthShell
      eyebrow="Zvingo Partner"
      title="Welcome back"
      description="Sign in to take orders, update your menu and watch tonight’s service."
      back={{ href: "/", label: "Back to Zvingo for restaurants" }}
      footer={
        <>
          New to Zvingo? <AuthLink href="/register">Add your restaurant</AuthLink>
        </>
      }
    >
      <form className="flex flex-col gap-6" onSubmit={handleSubmit} noValidate>
        {notice === "reset" && (
          <FormBanner tone="success" title="Password updated">
            Sign in with your new password to get back to your dashboard.
          </FormBanner>
        )}
        {notice === "expired" && (
          <FormBanner tone="info" title="Your session ended">
            You were signed out for security. Sign in once and you will stay signed in on this device.
          </FormBanner>
        )}
        {notice === "restore_failed" && (
          <FormBanner tone="info" title="We could not restore your session">
            Sign in again to carry on where you left off.
          </FormBanner>
        )}

        {cooldown > 0 && <RateLimitNotice seconds={cooldown} what="signing in" />}

        {formError && cooldown === 0 && (
          <FormBanner tone="error" title="We could not sign you in">
            {formError}
          </FormBanner>
        )}

        <Input
          id="login-identifier"
          name="username"
          label="Email or phone number"
          type="text"
          inputMode="email"
          autoComplete="username"
          autoCapitalize="none"
          spellCheck={false}
          required
          placeholder="you@restaurant.co.zw or 077 123 4567"
          value={identifier}
          error={fieldErrors.identifier}
          onChange={(event) => {
            setIdentifier(event.target.value);
            if (fieldErrors.identifier) setFieldErrors((prev) => ({ ...prev, identifier: undefined }));
          }}
        />

        <div className="flex flex-col gap-2">
          <PasswordField
            id="login-password"
            name="password"
            label="Password"
            autoComplete="current-password"
            required
            placeholder="Your password"
            value={password}
            error={fieldErrors.password}
            onChange={(event) => {
              setPassword(event.target.value);
              if (fieldErrors.password) setFieldErrors((prev) => ({ ...prev, password: undefined }));
            }}
          />
          <div className="flex justify-end">
            <AuthLink href="/forgot-password">Forgot your password?</AuthLink>
          </div>
        </div>

        <Button
          type="submit"
          variant="primary"
          size="lg"
          fullWidth
          loading={submitting}
          disabled={cooldown > 0}
          leftIcon={<LogIn className="h-[18px] w-[18px]" />}
        >
          Sign in
        </Button>
      </form>
    </AuthShell>
  );
}
