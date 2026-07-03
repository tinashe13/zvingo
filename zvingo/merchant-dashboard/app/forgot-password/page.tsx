"use client";

import { useState } from 'react';
import Link from 'next/link';

export default function ForgotPasswordPage() {
    const [phone, setPhone] = useState('');
    const [code, setCode] = useState('');
    const [newPassword, setNewPassword] = useState('');
    const [step, setStep] = useState<'request' | 'confirm' | 'done'>('request');
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState('');
    const [resetToken, setResetToken] = useState('');

    const handleRequest = async (e: React.FormEvent) => {
        e.preventDefault();
        setLoading(true);
        setError('');

        try {
            const res = await fetch('/api/auth/reset-password/request', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ phone }),
            });

            if (!res.ok) {
                const data = await res.json().catch(() => ({}));
                throw new Error(data.detail || 'Failed to send reset code');
            }

            const data = await res.json();
            if (data.token) {
                setResetToken(data.token);
            }
            setStep('confirm');
        } catch (err: any) {
            setError(err.message || 'Something went wrong');
        } finally {
            setLoading(false);
        }
    };

    const handleConfirm = async (e: React.FormEvent) => {
        e.preventDefault();
        setLoading(true);
        setError('');

        try {
            const res = await fetch('/api/auth/reset-password/confirm', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    token: resetToken || code,
                    new_password: newPassword,
                }),
            });

            if (!res.ok) {
                const data = await res.json().catch(() => ({}));
                throw new Error(data.detail || 'Failed to reset password');
            }

            setStep('done');
        } catch (err: any) {
            setError(err.message || 'Something went wrong');
        } finally {
            setLoading(false);
        }
    };

    return (
        <div className="min-h-screen flex items-center justify-center bg-gray-50 py-12 px-4 sm:px-6 lg:px-8">
            <div className="max-w-md w-full space-y-8">
                <div>
                    <h1 className="text-center text-2xl font-bold text-green-600">Zvingo Partner</h1>
                    <h2 className="mt-4 text-center text-3xl font-extrabold text-gray-900">
                        Reset Password
                    </h2>
                </div>

                {error && (
                    <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded-md text-sm">
                        {error}
                    </div>
                )}

                {step === 'request' && (
                    <form className="mt-8 space-y-6" onSubmit={handleRequest}>
                        <p className="text-sm text-gray-600 text-center">
                            Enter your phone number and we&apos;ll send you a reset code via SMS.
                        </p>
                        <div>
                            <label htmlFor="phone" className="block text-sm font-medium text-gray-700 mb-1">Phone Number</label>
                            <input
                                id="phone"
                                type="text"
                                required
                                className="appearance-none relative block w-full px-3 py-2 border border-gray-300 placeholder-gray-500 text-gray-900 rounded-md focus:outline-none focus:ring-green-500 focus:border-green-500 sm:text-sm"
                                placeholder="+263 7X XXX XXXX"
                                value={phone}
                                onChange={(e) => setPhone(e.target.value)}
                            />
                        </div>
                        <button
                            type="submit"
                            disabled={loading}
                            className="w-full flex justify-center py-2 px-4 border border-transparent text-sm font-medium rounded-md text-white bg-green-600 hover:bg-green-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500 disabled:opacity-50"
                        >
                            {loading ? 'Sending...' : 'Send Reset Code'}
                        </button>
                        <div className="text-center">
                            <Link href="/login" className="text-sm text-green-600 hover:text-green-500 font-medium">
                                Back to Login
                            </Link>
                        </div>
                    </form>
                )}

                {step === 'confirm' && (
                    <form className="mt-8 space-y-6" onSubmit={handleConfirm}>
                        <p className="text-sm text-gray-600 text-center">
                            Check your phone for the reset code and enter your new password.
                        </p>
                        <div className="space-y-4">
                            <div>
                                <label htmlFor="code" className="block text-sm font-medium text-gray-700 mb-1">Reset Code</label>
                                <input
                                    id="code"
                                    type="text"
                                    required={!resetToken}
                                    className="appearance-none relative block w-full px-3 py-2 border border-gray-300 placeholder-gray-500 text-gray-900 rounded-md focus:outline-none focus:ring-green-500 focus:border-green-500 sm:text-sm"
                                    placeholder="Enter reset code"
                                    value={code}
                                    onChange={(e) => setCode(e.target.value)}
                                />
                            </div>
                            <div>
                                <label htmlFor="newPassword" className="block text-sm font-medium text-gray-700 mb-1">New Password</label>
                                <input
                                    id="newPassword"
                                    type="password"
                                    required
                                    minLength={6}
                                    className="appearance-none relative block w-full px-3 py-2 border border-gray-300 placeholder-gray-500 text-gray-900 rounded-md focus:outline-none focus:ring-green-500 focus:border-green-500 sm:text-sm"
                                    placeholder="New password (min 6 characters)"
                                    value={newPassword}
                                    onChange={(e) => setNewPassword(e.target.value)}
                                />
                            </div>
                        </div>
                        <button
                            type="submit"
                            disabled={loading}
                            className="w-full flex justify-center py-2 px-4 border border-transparent text-sm font-medium rounded-md text-white bg-green-600 hover:bg-green-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500 disabled:opacity-50"
                        >
                            {loading ? 'Resetting...' : 'Reset Password'}
                        </button>
                    </form>
                )}

                {step === 'done' && (
                    <div className="text-center space-y-4">
                        <div className="bg-green-50 border border-green-200 text-green-700 px-4 py-3 rounded-md text-sm">
                            Password reset successfully!
                        </div>
                        <Link href="/login" className="inline-block py-2 px-6 bg-green-600 text-white text-sm font-medium rounded-md hover:bg-green-700">
                            Back to Login
                        </Link>
                    </div>
                )}
            </div>
        </div>
    );
}
