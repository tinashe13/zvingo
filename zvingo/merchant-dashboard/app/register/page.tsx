"use client";

import * as React from "react";
import Link from "next/link";
import {
  ArrowLeft,
  ArrowRight,
  Check,
  Crosshair,
  MapPin,
  Search,
  Store,
} from "lucide-react";
import { Button, Input, Skeleton, Textarea } from "@/components/ui";
import { clearApiCache } from "@/lib/useApi";
import { cn } from "@/lib/cn";
import { formatPhone, toE164 } from "@/lib/format";
import { AuthLink, AuthShell, NextStepLink } from "../_auth/AuthShell";
import {
  assessPassword,
  createRestaurantForMerchant,
  currentPosition,
  geocodeAddress,
  isAuthRequestError,
  persistSession,
  registerMerchant,
  type GeocodeMatch,
} from "../_auth/session";
import {
  FormBanner,
  PasswordField,
  PhoneField,
  RateLimitNotice,
  StepProgress,
  SuccessMark,
  useRetryCountdown,
} from "../_auth/ui";

/**
 * The same labels consumers browse by in the app, so a category chosen here
 * actually puts the restaurant in front of someone filtering for it.
 */
const CATEGORIES = [
  "Pizza",
  "Burgers",
  "Chicken",
  "Asian",
  "Healthy",
  "Coffee",
  "Desserts",
  "Grocery",
  "Convenience",
  "Pharmacy",
] as const;

const STEP_LABELS = ["Your restaurant", "Your account", "Where you are"] as const;
const TOTAL_STEPS = STEP_LABELS.length;

interface Draft {
  restaurantName: string;
  description: string;
  categories: string[];
  fullName: string;
  phone: string;
  email: string;
  password: string;
  confirmPassword: string;
  addressQuery: string;
  address: string;
  lat: number | null;
  lng: number | null;
  locationLabel: string;
}

const EMPTY_DRAFT: Draft = {
  restaurantName: "",
  description: "",
  categories: [],
  fullName: "",
  phone: "",
  email: "",
  password: "",
  confirmPassword: "",
  addressQuery: "",
  address: "",
  lat: null,
  lng: null,
  locationLabel: "",
};

type FieldErrors = Partial<Record<keyof Draft, string>>;

type Outcome =
  | { kind: "complete"; restaurantName: string }
  | { kind: "account_only"; restaurantName: string; reason: string };

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

export default function RegisterPage() {
  const [step, setStep] = React.useState(1);
  const [draft, setDraft] = React.useState<Draft>(EMPTY_DRAFT);
  const [errors, setErrors] = React.useState<FieldErrors>({});
  const [formError, setFormError] = React.useState<string | null>(null);
  const [retryAfter, setRetryAfter] = React.useState<number | null>(null);
  const [submitting, setSubmitting] = React.useState(false);
  const [outcome, setOutcome] = React.useState<Outcome | null>(null);
  const [accountExists, setAccountExists] = React.useState(false);

  // Address lookup
  const [matches, setMatches] = React.useState<GeocodeMatch[] | null>(null);
  const [searching, setSearching] = React.useState(false);
  const [locationError, setLocationError] = React.useState<string | null>(null);
  const [locating, setLocating] = React.useState(false);

  const cooldown = useRetryCountdown(retryAfter);
  const stepRef = React.useRef<HTMLDivElement>(null);
  const firstRender = React.useRef(true);

  // Moving between steps is a navigation: put focus at the top of the new step
  // so a keyboard or screen-reader user is not left at the bottom of the form.
  React.useEffect(() => {
    if (firstRender.current) {
      firstRender.current = false;
      return;
    }
    stepRef.current?.focus();
  }, [step]);

  const update = React.useCallback(<K extends keyof Draft>(key: K, value: Draft[K]) => {
    setDraft((prev) => ({ ...prev, [key]: value }));
    setErrors((prev) => (prev[key] ? { ...prev, [key]: undefined } : prev));
  }, []);

  function validateStep(target: number): boolean {
    const next: FieldErrors = {};

    if (target === 1) {
      const name = draft.restaurantName.trim();
      if (!name) next.restaurantName = "Tell customers what your restaurant is called.";
      else if (name.length < 2) next.restaurantName = "That looks too short to be a restaurant name.";
      else if (name.length > 80) next.restaurantName = "Keep the name under 80 characters.";
    }

    if (target === 2) {
      const fullName = draft.fullName.trim();
      if (!fullName) next.fullName = "We need a name for whoever runs this account.";
      else if (fullName.length < 2) next.fullName = "Enter your full name.";

      if (!draft.phone.trim()) next.phone = "Enter the mobile number Zvingo should reach you on.";
      else if (!toE164(draft.phone)) next.phone = "That is not a Zimbabwean mobile number. Try 077 123 4567.";

      const email = draft.email.trim();
      if (email && !EMAIL_PATTERN.test(email)) next.email = "Check this email address — it looks incomplete.";

      const assessment = assessPassword(draft.password);
      if (!draft.password) next.password = "Create a password for your account.";
      else if (!assessment.meetsMinimum) next.password = "Your password needs at least 8 characters.";
      else if (assessment.tooLong) next.password = "That password is too long.";

      if (!draft.confirmPassword) next.confirmPassword = "Type your password once more to confirm it.";
      else if (draft.confirmPassword !== draft.password) next.confirmPassword = "These two passwords do not match.";
    }

    if (target === 3) {
      if (draft.lat === null || draft.lng === null) {
        next.address = "Find your restaurant on the map so drivers can get to you.";
      } else if (!draft.address.trim()) {
        next.address = "Add the street address drivers should look for.";
      }
    }

    setErrors(next);
    return Object.keys(next).length === 0;
  }

  function goBack() {
    setFormError(null);
    setStep((current) => Math.max(1, current - 1));
  }

  async function runSearch() {
    const query = draft.addressQuery.trim();
    if (query.length < 3) {
      setLocationError("Type at least three characters — a street, suburb or a nearby landmark.");
      return;
    }
    setSearching(true);
    setLocationError(null);
    try {
      const results = await geocodeAddress(query);
      setMatches(results);
      if (results.length === 0) {
        setLocationError(
          "No match for that. Try a suburb and city (for example “Avondale, Harare”), or use your current location.",
        );
      }
    } catch {
      setMatches(null);
      setLocationError("Address lookup is not responding. Try again, or use your current location.");
    } finally {
      setSearching(false);
    }
  }

  function chooseMatch(match: GeocodeMatch) {
    setDraft((prev) => ({
      ...prev,
      lat: match.lat,
      lng: match.lng,
      locationLabel: match.display_name,
      address: prev.address.trim() || match.display_name,
    }));
    setErrors((prev) => ({ ...prev, address: undefined }));
    setMatches(null);
    setLocationError(null);
  }

  async function useMyLocation() {
    setLocating(true);
    setLocationError(null);
    try {
      const position = await currentPosition();
      setDraft((prev) => ({
        ...prev,
        lat: position.lat,
        lng: position.lng,
        locationLabel: "Your current location",
      }));
      setErrors((prev) => ({ ...prev, address: undefined }));
      setMatches(null);
    } catch (error) {
      setLocationError(error instanceof Error ? error.message : "We could not get your location.");
    } finally {
      setLocating(false);
    }
  }

  async function createRestaurant(): Promise<Outcome> {
    const restaurantName = draft.restaurantName.trim();
    try {
      await createRestaurantForMerchant({
        name: restaurantName,
        description: draft.description.trim() || undefined,
        categories: draft.categories,
        address: draft.address.trim(),
        lat: draft.lat as number,
        lng: draft.lng as number,
      });
      return { kind: "complete", restaurantName };
    } catch (error) {
      const reason =
        error instanceof Error && error.message
          ? error.message
          : "We could not save your restaurant listing.";
      return { kind: "account_only", restaurantName, reason };
    }
  }

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    if (submitting || cooldown > 0) return;
    setFormError(null);

    if (step < TOTAL_STEPS) {
      if (validateStep(step)) setStep(step + 1);
      return;
    }

    if (!validateStep(TOTAL_STEPS)) return;

    setSubmitting(true);
    try {
      // The account first: without a merchant token there is nothing that may
      // create a restaurant. `role` is pinned to "merchant" inside
      // registerMerchant and is never a form control.
      if (!accountExists) {
        const token = await registerMerchant({
          full_name: draft.fullName.trim(),
          phone: toE164(draft.phone) as string,
          password: draft.password,
          email: draft.email.trim() || undefined,
        });
        persistSession(token);
        clearApiCache();
        setAccountExists(true);
      }
      setOutcome(await createRestaurant());
    } catch (error) {
      if (isAuthRequestError(error)) {
        if (error.kind === "rate_limited") {
          setRetryAfter(error.retryAfterSeconds ?? 300);
        } else if (error.kind === "conflict") {
          const detail = error.detail ?? "";
          const onEmail = /email/i.test(detail);
          setStep(2);
          setErrors({
            [onEmail ? "email" : "phone"]: onEmail
              ? "This email address already has a Zvingo account."
              : "This number already has a Zvingo account.",
          });
          setFormError(
            onEmail
              ? "That email address is already registered. Sign in instead, or use a different address."
              : "That phone number is already registered. Sign in instead, or use a different number.",
          );
        } else {
          setFormError(error.message);
        }
      } else {
        setFormError("Something went wrong creating your account. Please try again.");
      }
    } finally {
      setSubmitting(false);
    }
  }

  /* ---------------------------------------------------------------------- */
  /* Success                                                                */
  /* ---------------------------------------------------------------------- */

  if (outcome) {
    const complete = outcome.kind === "complete";
    return (
      <AuthShell
        eyebrow="Zvingo Partner"
        title={complete ? "You’re in." : "Your account is ready"}
        description={
          complete ? (
            <>
              <span className="font-semibold text-neutral-900">{outcome.restaurantName}</span> now has a
              Zvingo Partner account. Three short jobs and you can take your first order.
            </>
          ) : (
            <>
              You can sign in to Zvingo Partner right now. We could not finish your restaurant listing,
              so that is the one thing left to do.
            </>
          )
        }
      >
        <div className="flex flex-col gap-6">
          <div className="flex justify-center">
            <SuccessMark />
          </div>

          {!complete && (
            <FormBanner tone="warning" title="Your restaurant listing is not saved yet">
              {outcome.reason} You can finish it from Settings — nothing you entered is lost.
            </FormBanner>
          )}

          <div className="zv-stagger flex flex-col gap-3">
            {complete ? (
              <>
                <NextStepLink href="/dashboard/menu">1. Add your first menu items</NextStepLink>
                <NextStepLink href="/dashboard/settings">2. Set your opening hours and photo</NextStepLink>
                <NextStepLink href="/dashboard">3. Switch your store open and take orders</NextStepLink>
              </>
            ) : (
              <>
                <NextStepLink href="/dashboard/settings">1. Finish your restaurant details</NextStepLink>
                <NextStepLink href="/dashboard/menu">2. Add your first menu items</NextStepLink>
              </>
            )}
          </div>

          <Button asChild variant="primary" size="lg" fullWidth>
            <Link href={complete ? "/dashboard" : "/dashboard/settings"}>
              {complete ? "Open my dashboard" : "Finish setting up in Settings"}
            </Link>
          </Button>

          <p className="type-caption text-text-secondary">
            Zvingo takes no commission on your food. You keep your full menu total; Zvingo earns a share
            of the delivery fee the customer pays.
          </p>
        </div>
      </AuthShell>
    );
  }

  /* ---------------------------------------------------------------------- */
  /* Form                                                                   */
  /* ---------------------------------------------------------------------- */

  const primaryLabel = step < TOTAL_STEPS ? "Continue" : "Create my partner account";

  return (
    <AuthShell
      width="lg"
      title={STEP_LABELS[step - 1] ?? "Add your restaurant"}
      description={
        step === 1
          ? "Start with the basics. You can change any of this later in Settings."
          : step === 2
            ? "This is the account you will sign in with, and how Zvingo reaches you about an order."
            : "Drivers and customers both need to find you. Search for your address or share your current location."
      }
      progress={<StepProgress step={step} total={TOTAL_STEPS} label={STEP_LABELS[step - 1] ?? ""} />}
      back={
        step === 1
          ? { href: "/", label: "Back to Zvingo for restaurants" }
          : undefined
      }
      footer={
        <>
          Already a partner? <AuthLink href="/login">Sign in</AuthLink>
        </>
      }
    >
      <form className="flex flex-col gap-6" onSubmit={handleSubmit} noValidate>
        <div ref={stepRef} tabIndex={-1} className="flex flex-col gap-6 focus:outline-none">
          {cooldown > 0 && <RateLimitNotice seconds={cooldown} what="creating an account" />}

          {formError && cooldown === 0 && (
            <FormBanner
              tone="error"
              title="We could not finish that"
              action={
                /already/i.test(formError) ? (
                  <Button asChild variant="secondary" size="sm">
                    <Link href="/login">Go to sign in</Link>
                  </Button>
                ) : undefined
              }
            >
              {formError}
            </FormBanner>
          )}

          {step === 1 && (
            <>
              <Input
                id="register-restaurant-name"
                name="organization"
                label="Restaurant name"
                autoComplete="organization"
                required
                placeholder="Gogo’s Kitchen"
                maxLength={80}
                value={draft.restaurantName}
                error={errors.restaurantName}
                help="Exactly how customers should see it in the app."
                onChange={(event) => update("restaurantName", event.target.value)}
              />

              <fieldset className="flex flex-col gap-2 border-0 p-0">
                <legend className="type-caption font-semibold text-neutral-800">
                  What do you serve?
                </legend>
                <p className="type-caption text-text-secondary">
                  These are the filters customers browse by. Pick as many as fit — you can change them later.
                </p>
                <div className="mt-1 flex flex-wrap gap-2">
                  {CATEGORIES.map((category) => {
                    const selected = draft.categories.includes(category);
                    return (
                      <button
                        key={category}
                        type="button"
                        aria-pressed={selected}
                        onClick={() =>
                          update(
                            "categories",
                            selected
                              ? draft.categories.filter((entry) => entry !== category)
                              : [...draft.categories, category],
                          )
                        }
                        className={cn(
                          "zv-touch inline-flex min-h-11 items-center gap-1.5 rounded-full px-4 type-caption font-bold transition-colors",
                          "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-action",
                          selected
                            ? "bg-action text-neutral-0"
                            : "bg-neutral-100 text-neutral-800 hover:bg-neutral-200",
                        )}
                      >
                        {selected && <Check className="h-3.5 w-3.5" aria-hidden="true" />}
                        {category}
                      </button>
                    );
                  })}
                </div>
              </fieldset>

              <Textarea
                id="register-description"
                label="Short description"
                hint="Optional"
                rows={3}
                maxLength={200}
                showCount
                placeholder="Home-style sadza, grills and takeaways in Avondale."
                value={draft.description}
                onChange={(event) => update("description", event.target.value)}
                help="One line customers see under your name."
              />
            </>
          )}

          {step === 2 && (
            <>
              <Input
                id="register-full-name"
                name="name"
                label="Your full name"
                autoComplete="name"
                required
                placeholder="Tinashe Moyo"
                value={draft.fullName}
                error={errors.fullName}
                onChange={(event) => update("fullName", event.target.value)}
              />

              <PhoneField
                id="register-phone"
                name="tel"
                label="Contact mobile number"
                required
                value={draft.phone}
                error={errors.phone}
                onValueChange={(value) => update("phone", value)}
              />

              <Input
                id="register-email"
                name="email"
                label="Email address"
                hint="Optional"
                type="email"
                inputMode="email"
                autoComplete="email"
                autoCapitalize="none"
                spellCheck={false}
                placeholder="orders@restaurant.co.zw"
                value={draft.email}
                error={errors.email}
                help="You can sign in with either your email or your phone number."
                onChange={(event) => update("email", event.target.value)}
              />

              <PasswordField
                id="register-password"
                name="new-password"
                label="Create a password"
                autoComplete="new-password"
                required
                showRules
                placeholder="At least 8 characters"
                value={draft.password}
                error={errors.password}
                onChange={(event) => update("password", event.target.value)}
              />

              <PasswordField
                id="register-confirm-password"
                name="confirm-password"
                label="Confirm password"
                autoComplete="new-password"
                required
                placeholder="Type it once more"
                value={draft.confirmPassword}
                error={errors.confirmPassword}
                onChange={(event) => update("confirmPassword", event.target.value)}
              />
            </>
          )}

          {step === 3 && (
            <>
              <div className="flex flex-col gap-2">
                <label
                  htmlFor="register-address-search"
                  className="type-caption font-semibold text-neutral-800"
                >
                  Find your restaurant
                </label>
                <div className="flex gap-2">
                  <div className="min-w-0 flex-1">
                    <Input
                      id="register-address-search"
                      name="address-search"
                      type="search"
                      autoComplete="street-address"
                      placeholder="Street, suburb or landmark"
                      value={draft.addressQuery}
                      onChange={(event) => update("addressQuery", event.target.value)}
                      onKeyDown={(event) => {
                        if (event.key === "Enter") {
                          // Enter searches; it must not skip the step.
                          event.preventDefault();
                          void runSearch();
                        }
                      }}
                    />
                  </div>
                  <Button
                    type="button"
                    variant="secondary"
                    size="lg"
                    loading={searching}
                    onClick={() => void runSearch()}
                    leftIcon={<Search className="h-[18px] w-[18px]" />}
                  >
                    <span className="max-sm:hidden">Search</span>
                    <span className="sm:hidden zv-sr-only">Search</span>
                  </Button>
                </div>
                <button
                  type="button"
                  onClick={() => void useMyLocation()}
                  disabled={locating}
                  className="zv-touch inline-flex w-fit items-center gap-2 rounded-md py-2 type-caption font-bold text-neutral-900 underline decoration-neutral-300 underline-offset-4 transition-colors hover:decoration-neutral-900 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-action disabled:text-action-disabled-fg"
                >
                  <Crosshair className="h-4 w-4" aria-hidden="true" />
                  {locating ? "Getting your location…" : "Use my current location instead"}
                </button>
              </div>

              {searching && (
                <div className="flex flex-col gap-2" role="status" aria-busy="true">
                  <Skeleton className="h-16 w-full" />
                  <Skeleton className="h-16 w-full" />
                  <span className="zv-sr-only">Searching for addresses</span>
                </div>
              )}

              {locationError && (
                <FormBanner tone="info" title="We need a bit more to go on">
                  {locationError}
                </FormBanner>
              )}

              {matches && matches.length > 0 && (
                <ul className="zv-stagger flex flex-col gap-2">
                  {matches.map((match) => (
                    <li key={`${match.lat},${match.lng},${match.display_name}`}>
                      <button
                        type="button"
                        onClick={() => chooseMatch(match)}
                        className="zv-tap flex w-full items-start gap-3 rounded-md border border-border bg-surface p-4 text-left transition-colors hover:bg-neutral-50 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-action"
                      >
                        <MapPin className="mt-0.5 h-[18px] w-[18px] shrink-0 text-text-tertiary" aria-hidden="true" />
                        <span className="type-body text-neutral-900">{match.display_name}</span>
                      </button>
                    </li>
                  ))}
                </ul>
              )}

              {draft.lat !== null && draft.lng !== null && (
                <div className="zv-enter flex items-start gap-3 rounded-md border border-success/25 bg-success-surface p-4">
                  <Check className="mt-0.5 h-[18px] w-[18px] shrink-0 text-success" aria-hidden="true" />
                  <div className="min-w-0">
                    <p className="type-body-strong text-neutral-900">Location set</p>
                    <p className="mt-1 type-caption text-text-secondary">{draft.locationLabel}</p>
                    <p className="mt-1 type-caption tabular-figures text-text-tertiary">
                      {draft.lat.toFixed(5)}, {draft.lng.toFixed(5)}
                    </p>
                  </div>
                </div>
              )}

              <Input
                id="register-address"
                name="street-address"
                label="Address drivers should look for"
                autoComplete="street-address"
                required
                placeholder="12 King George Rd, Avondale, Harare"
                value={draft.address}
                error={errors.address}
                help="Include the shop or unit number if you have one."
                onChange={(event) => update("address", event.target.value)}
              />
            </>
          )}
        </div>

        <div className="flex flex-col-reverse gap-3 sm:flex-row sm:items-center sm:justify-between">
          {step > 1 ? (
            <Button
              type="button"
              variant="tertiary"
              size="lg"
              onClick={goBack}
              leftIcon={<ArrowLeft className="h-[18px] w-[18px]" />}
            >
              Back
            </Button>
          ) : (
            <span aria-hidden="true" className="hidden sm:block" />
          )}

          <Button
            type="submit"
            variant="primary"
            size="lg"
            loading={submitting}
            disabled={cooldown > 0}
            className="sm:min-w-56"
            fullWidth={step === 1}
            rightIcon={
              step < TOTAL_STEPS ? (
                <ArrowRight className="h-[18px] w-[18px]" />
              ) : (
                <Store className="h-[18px] w-[18px]" />
              )
            }
          >
            {primaryLabel}
          </Button>
        </div>

        {step === TOTAL_STEPS && (
          <p className="type-caption text-text-secondary">
            Creating an account signs you in on this device as{" "}
            <span className="font-semibold text-neutral-900">
              {toE164(draft.phone) ? formatPhone(draft.phone) : "your number"}
            </span>
            . Zvingo takes no commission on your food.
          </p>
        )}
      </form>
    </AuthShell>
  );
}
