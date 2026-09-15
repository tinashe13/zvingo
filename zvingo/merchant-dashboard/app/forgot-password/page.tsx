"use client";

import * as React from "react";
import Link from "next/link";
import { MessageSquareText, Send } from "lucide-react";
import { Button } from "@/components/ui";
import { formatPhone, toE164 } from "@/lib/format";
import { AuthLink, AuthShell } from "../_auth/AuthShell";
import { isAuthRequestError, requestPasswordReset } from "../_auth/session";
import { FormBanner, PhoneField, RateLimitNotice, useRetryCountdown } from "../_auth/ui";

export default function ForgotPasswordPage() {
  const [phone, setPhone] = React.useState("");
  const [sentTo, setSentTo] = React.useState<string | null>(null);
  const [fieldError, setFieldError] = React.useState<string | undefined>();
  const [formError, setFormError] = React.useState<string | null>(null);
  const [retryAfter, setRetryAfter] = React.useState<number | null>(null);
  const [submitting, setSubmitting] = React.useState(false);

  const cooldown = useRetryCountdown(retryAfter);

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    if (submitting || cooldown > 0) return;

    const e164 = toE164(phone);
    if (!phone.trim()) {
      setFieldError("Enter the mobile number on your partner account.");
      return;
    }
    if (!e164) {
      setFieldError("That is not a Zimbabwean mobile number. Try 077 123 4567.");
      return;
    }

    setFieldError(undefined);
    setFormError(null);
    setSubmitting(true);
    try {
      await requestPasswordReset(e164);
      setSentTo(e164);
    } catch (error) {
      if (isAuthRequestError(error) && error.kind === "rate_limited") {
        setRetryAfter(error.retryAfterSeconds ?? 300);
      } else if (isAuthRequestError(error)) {
        setFormError(error.message);
      } else {
        setFormError("Something went wrong sending your reset code. Please try again.");
      }
    } finally {
      setSubmitting(false);
    }
  }

  /* ---------------------------------------------------------------------- */
  /* Confirmation — deliberately identical for a known and unknown number.  */
  /* ---------------------------------------------------------------------- */

  if (sentTo) {
    return (
      <AuthShell
        eyebrow="Password reset"
        title="Check your phone"
        description={
          <>
            If{" "}
            <span className="font-semibold tabular-figures text-neutral-900">{formatPhone(sentTo)}</span>{" "}
            belongs to a Zvingo Partner account, we have just sent it a reset code by SMS.
          </>
        }
        back={{ href: "/login", label: "Back to sign in" }}
      >
        <div className="flex flex-col gap-6">
          <div className="flex gap-3 rounded-md border border-border bg-neutral-50 p-4">
            <MessageSquareText
              className="mt-0.5 h-[18px] w-[18px] shrink-0 text-text-secondary"
              aria-hidden="true"
            />
            <div className="type-caption text-text-secondary">
              <p className="type-body-strong text-neutral-900">The code expires in 15 minutes</p>
              <p className="mt-1">
                It works once. Using it signs you out of Zvingo everywhere, on every device — including
                any device you did not recognise.
              </p>
            </div>
          </div>

          <Button asChild variant="primary" size="lg" fullWidth>
            <Link href="/reset-password">I have my code</Link>
          </Button>

          <div className="flex flex-col gap-3 border-t border-divider pt-5 type-caption text-text-secondary">
            <p>
              No SMS after a minute or two? Check the number, then{" "}
              <button
                type="button"
                onClick={() => {
                  setSentTo(null);
                  setFormError(null);
                }}
                className="rounded-sm font-bold text-neutral-900 underline decoration-neutral-300 underline-offset-4 transition-colors hover:decoration-neutral-900 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-action"
              >
                try a different number
              </button>
              .
            </p>
            <p>
              Remembered it after all? <AuthLink href="/login">Sign in</AuthLink>
            </p>
          </div>
        </div>
      </AuthShell>
    );
  }

  /* ---------------------------------------------------------------------- */
  /* Request                                                                */
  /* ---------------------------------------------------------------------- */

  return (
    <AuthShell
      eyebrow="Password reset"
      title="Reset your password"
      description="Enter the mobile number on your partner account and we will send a reset code by SMS."
      back={{ href: "/login", label: "Back to sign in" }}
      footer={
        <>
          No account yet? <AuthLink href="/register">Add your restaurant</AuthLink>
        </>
      }
    >
      <form className="flex flex-col gap-6" onSubmit={handleSubmit} noValidate>
        {cooldown > 0 && <RateLimitNotice seconds={cooldown} what="a password reset" />}

        {formError && cooldown === 0 && (
          <FormBanner tone="error" title="We could not send your code">
            {formError}
          </FormBanner>
        )}

        <PhoneField
          id="forgot-phone"
          name="tel"
          label="Mobile number"
          required
          autoFocus
          value={phone}
          error={fieldError}
          onValueChange={(value) => {
            setPhone(value);
            if (fieldError) setFieldError(undefined);
          }}
        />

        <Button
          type="submit"
          variant="primary"
          size="lg"
          fullWidth
          loading={submitting}
          disabled={cooldown > 0}
          leftIcon={<Send className="h-[18px] w-[18px]" />}
        >
          Send my reset code
        </Button>

        <p className="type-caption text-text-secondary">
          For your security we answer the same way whether or not that number has an account, so nobody
          can use this page to find out who is on Zvingo.
        </p>
      </form>
    </AuthShell>
  );
}
