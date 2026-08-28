"use client";

import { useState } from "react";
import Link from "next/link";
import { ArrowLeft, Check, KeyRound, MessageSquareText, Zap } from "lucide-react";
import { Button } from "@/components/ui/Button";
import { Input } from "@/components/ui/Input";

export default function ForgotPasswordPage() {
    const [phone, setPhone] = useState("");
    const [code, setCode] = useState("");
    const [newPassword, setNewPassword] = useState("");
    const [step, setStep] = useState<"request" | "confirm" | "done">("request");
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState("");
    const [resetToken, setResetToken] = useState("");

    async function handleRequest(event: React.FormEvent) {
        event.preventDefault(); setLoading(true); setError("");
        try { const response = await fetch("/api/auth/reset-password/request", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ phone }) }); if (!response.ok) { const data = await response.json().catch(() => ({})); throw new Error(data.detail || "Failed to send reset code"); } const data = await response.json(); if (data.token) setResetToken(data.token); setStep("confirm"); }
        catch (err) { setError(err instanceof Error ? err.message : "Something went wrong"); }
        finally { setLoading(false); }
    }

    async function handleConfirm(event: React.FormEvent) {
        event.preventDefault(); setLoading(true); setError("");
        try { const response = await fetch("/api/auth/reset-password/confirm", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ token: resetToken || code, new_password: newPassword }) }); if (!response.ok) { const data = await response.json().catch(() => ({})); throw new Error(data.detail || "Failed to reset password"); } setStep("done"); }
        catch (err) { setError(err instanceof Error ? err.message : "Something went wrong"); }
        finally { setLoading(false); }
    }

    return (
        <main className="relative flex min-h-screen items-center justify-center overflow-hidden bg-neutral-900 px-4 py-12">
            <div className="absolute -left-24 -top-24 h-80 w-80 rounded-full bg-[#d7f654]/10 blur-3xl" /><div className="absolute -bottom-32 -right-20 h-96 w-96 rounded-full bg-primary/20 blur-3xl" />
            <div className="relative w-full max-w-md">
                <Link href="/login" className="mb-6 inline-flex items-center gap-2 text-sm font-bold text-neutral-300 hover:text-white"><ArrowLeft className="h-4 w-4" />Back to sign in</Link>
                <div className="rounded-3xl bg-white p-7 shadow-2xl sm:p-8">
                    <div className="mb-7 flex items-center justify-between"><div className="flex h-11 w-11 items-center justify-center rounded-2xl bg-[#d7f654] text-neutral-900"><Zap className="h-5 w-5" fill="currentColor" /></div><div className="flex gap-2">{["request", "confirm", "done"].map((entry, index) => <span key={entry} className={`h-1.5 rounded-full transition-all ${["request", "confirm", "done"].indexOf(step) >= index ? "w-7 bg-neutral-900" : "w-3 bg-neutral-200"}`} />)}</div></div>
                    {step === "request" && <AuthStep icon={MessageSquareText} title="Reset your password" description="Enter the phone number on your partner account and we’ll send a secure reset code."><form className="mt-7 space-y-5" onSubmit={handleRequest}><ErrorMessage message={error} /><label className="block"><span className="mb-2 block text-sm font-bold text-neutral-800">Phone number</span><Input type="tel" required value={phone} onChange={(event) => setPhone(event.target.value)} placeholder="+263 77 000 0000" autoComplete="tel" /></label><Button type="submit" className="w-full" isLoading={loading}>Send reset code</Button></form></AuthStep>}
                    {step === "confirm" && <AuthStep icon={KeyRound} title="Choose a new password" description={`Enter the code sent to ${phone || "your phone"}, then create a new password.`}><form className="mt-7 space-y-5" onSubmit={handleConfirm}><ErrorMessage message={error} />{!resetToken && <label className="block"><span className="mb-2 block text-sm font-bold text-neutral-800">Reset code</span><Input required value={code} onChange={(event) => setCode(event.target.value)} placeholder="6-digit code" inputMode="numeric" /></label>}<label className="block"><span className="mb-2 block text-sm font-bold text-neutral-800">New password</span><Input type="password" required minLength={6} value={newPassword} onChange={(event) => setNewPassword(event.target.value)} placeholder="At least 6 characters" autoComplete="new-password" /></label><Button type="submit" className="w-full" isLoading={loading}>Reset password</Button></form></AuthStep>}
                    {step === "done" && <AuthStep icon={Check} title="Password updated" description="Your account is secure and your new password is ready to use."><Link href="/login" className="mt-7 flex h-12 items-center justify-center rounded-xl bg-neutral-900 text-sm font-bold text-white hover:bg-neutral-800">Return to sign in</Link></AuthStep>}
                </div>
            </div>
        </main>
    );
}

function AuthStep({ icon: Icon, title, description, children }: { icon: typeof KeyRound; title: string; description: string; children: React.ReactNode }) { return <section><span className="flex h-10 w-10 items-center justify-center rounded-xl bg-primary-light text-primary"><Icon className="h-5 w-5" /></span><h1 className="mt-5 text-3xl font-black tracking-[-0.04em] text-neutral-900">{title}</h1><p className="mt-3 text-sm leading-6 text-neutral-500">{description}</p>{children}</section>; }
function ErrorMessage({ message }: { message: string }) { return message ? <div role="alert" className="rounded-xl bg-red-50 px-4 py-3 text-sm font-semibold text-red-700">{message}</div> : null; }
