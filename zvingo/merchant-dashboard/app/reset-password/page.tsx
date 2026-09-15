"use client";

import * as React from "react";
import Link from "next/link";
import { KeyRound, ShieldCheck } from "lucide-react";
import { Button, Input } from "@/components/ui";
import { clearApiCache } from "@/lib/useApi";
import { AuthLink, AuthShell } from "../_auth/AuthShell";
import {
  assessPassword,
  clearSession,
  confirmPasswordReset,
  isAuthRequestError,
  readQueryParam,
  stripQueryParam,
} from "../_auth/session";
import {
  FormBanner,
  PasswordField,
  RateLimitNotice,
  SuccessMark,
  useRetryCountdown,
} from "../_auth/ui";

/** `token` in `PasswordResetConfirm` is `min_length=8`. */
const MIN_TOKEN_LENGTH = 8;

export default function ResetPasswordPage() {
  const [token, setToken] = React.useState("");
  const [password, setPassword] = React.useState("");
  const [confirmPassword, setConfirmPassword] = React.useState("");
  const [errors, setErrors] = React.useState<{ token?: string; password?: string; confirm?: string }>({});
  const [formError, setFormError] = React.useState<string | null>(null);
  const [tokenRejected, setTokenRejected] = React.useState(false);
  const [retryAfter, setRetryAfter] = React.useState<number | null>(null);
  const [submitting, setSubmitting] = React.useState(false);
  const [done, setDone] = React.useState(false);

  const cooldown = useRetryCountdown(retryAfter);

  // A reset link carries the code in the query string. Lift it into the form
  // and take it straight back out of the address bar so it does not sit in
  // browser history, a shared screen or the next screenshot.
  React.useEffect(() => {
    const fromLink = readQueryParam("token");
    if (fromLink) {
      setToken(fromLink);
      stripQueryParam("token");
    }
  }, []);

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    if (submitting || cooldown > 0) return;

    const next: typeof errors = {};
    const code = token.trim();
    if (!code) next.token = "Paste the reset code from your SMS.";
    else if (code.length < MIN_TOKEN_LENGTH) next.token = "That code looks too short — paste the whole thing.";

    const assessment = assessPassword(password);
    if (!password) next.password = "Choose a new password.";
    else if (!assessment.meetsMinimum) next.password = "Your password needs at least 8 characters.";
    else if (assessment.tooLong) next.password = "That password is too long.";

    if (!confirmPassword) next.confirm = "Type your new password once more.";
    else if (confirmPassword !== password) next.confirm = "These two passwords do not match.";

    setErrors(next);
    if (Object.keys(next).length > 0) return;

    setFormError(null);
    setTokenRejected(false);
    setSubmitting(true);
    try {
      await confirmPasswordReset(code, password);
      // The backend moves `tokens_valid_from` forward and revokes every
      // refresh token, so anything cached on this device is already dead.
      clearSession();
      clearApiCache();
      setDone(true);
    } catch (error) {
      if (isAuthRequestError(error)) {
        if (error.kind === "rate_limited") {
          setRetryAfter(error.retryAfterSeconds ?? 300);
        } else if (error.status === 400 || error.status === 401 || error.status === 404) {
          setTokenRejected(true);
        } else {
          setFormError(error.message);
        }
      } else {
        setFormError("Something went wrong updating your password. Please try again.");
      }
    } finally {
      setSubmitting(false);
    }
  }

  if (done) {
    return (
      <AuthShell
        eyebrow="Password reset"
        title="Your new password is live"
        description="Every device that was signed in to this account has been signed out. Sign in again to carry on."
      >
        <div className="flex flex-col gap-6">
          <div className="flex justify-center">
            <SuccessMark />
          </div>
          <Button asChild variant="primary" size="lg" fullWidth>
            <Link href="/login?reset=1">Sign in with my new password</Link>
          </Button>
        </div>
      </AuthShell>
    );
  }

  return (
    <AuthShell
      eyebrow="Password reset"
      title="Choose a new password"
      description="Paste the code from your SMS, then pick the password you will use from now on."
      back={{ href: "/forgot-password", label: "Back to reset request" }}
      footer={
        <>
          Remembered your password? <AuthLink href="/login">Sign in</AuthLink>
        </>
      }
    >
      <form className="flex flex-col gap-6" onSubmit={handleSubmit} noValidate>
        {cooldown > 0 && <RateLimitNotice seconds={cooldown} what="a password reset" />}

        {tokenRejected && cooldown === 0 && (
          <FormBanner
            tone="error"
            title="That code no longer works"
            action={
              <Button asChild variant="secondary" size="sm">
                <Link href="/forgot-password">Send me a new code</Link>
              </Button>
            }
          >
            Reset codes expire after 15 minutes and can only be used once. Request a fresh one and it will
            arrive by SMS in a moment.
          </FormBanner>
        )}

        {formError && cooldown === 0 && (
          <FormBanner tone="error" title="We could not update your password">
            {formError}
          </FormBanner>
        )}

        <Input
          id="reset-token"
          name="one-time-code"
          label="Reset code"
          autoComplete="one-time-code"
          autoCapitalize="none"
          spellCheck={false}
          required
          placeholder="Paste the code from your SMS"
          value={token}
          error={errors.token}
          help="Copy the whole code exactly as it appears in the message."
          leftIcon={<KeyRound className="h-[18px] w-[18px]" />}
          onChange={(event) => {
            setToken(event.target.value);
            setErrors((prev) => ({ ...prev, token: undefined }));
            setTokenRejected(false);
          }}
        />

        <PasswordField
          id="reset-password"
          name="new-password"
          label="New password"
          autoComplete="new-password"
          required
          showRules
          placeholder="At least 8 characters"
          value={password}
          error={errors.password}
          onChange={(event) => {
            setPassword(event.target.value);
            setErrors((prev) => ({ ...prev, password: undefined }));
          }}
        />

        <PasswordField
          id="reset-confirm-password"
          name="confirm-password"
          label="Confirm new password"
          autoComplete="new-password"
          required
          placeholder="Type it once more"
          value={confirmPassword}
          error={errors.confirm}
          onChange={(event) => {
            setConfirmPassword(event.target.value);
            setErrors((prev) => ({ ...prev, confirm: undefined }));
          }}
        />

        <Button
          type="submit"
          variant="primary"
          size="lg"
          fullWidth
          loading={submitting}
          disabled={cooldown > 0}
          leftIcon={<ShieldCheck className="h-[18px] w-[18px]" />}
        >
          Update my password
        </Button>
      </form>
    </AuthShell>
  );
}
