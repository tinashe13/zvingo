'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { setToken } from '@/lib/api';
import { Button } from '@/components/ui/Button';
import { Input } from '@/components/ui/Input';
import { Card, CardContent, CardHeader, CardTitle, CardDescription, CardFooter } from '@/components/ui/Card';

export default function RegisterPage() {
    const [fullName, setFullName] = useState('');
    const [email, setEmail] = useState('');
    const [phone, setPhone] = useState('');
    const [password, setPassword] = useState('');
    const [confirmPassword, setConfirmPassword] = useState('');
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState('');
    const router = useRouter();

    const handleRegister = async (e: React.FormEvent) => {
        e.preventDefault();
        setLoading(true);
        setError('');

        if (password !== confirmPassword) {
            setError('Passwords do not match');
            setLoading(false);
            return;
        }

        if (password.length < 4) {
            setError('Password must be at least 4 characters');
            setLoading(false);
            return;
        }

        if (!phone.trim()) {
            setError('Phone number is required');
            setLoading(false);
            return;
        }

        try {
            const res = await fetch('/api/auth/register', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    full_name: fullName,
                    email: email || null,
                    phone: phone,
                    password: password,
                    role: 'merchant',
                }),
            });

            if (!res.ok) {
                const data = await res.json().catch(() => ({}));
                throw new Error(data.detail || 'Registration failed');
            }

            const data = await res.json();
            setToken(data.access_token);
            router.push('/dashboard');
        } catch (err: any) {
            setError(err.message || 'Registration failed');
        } finally {
            setLoading(false);
        }
    };

    return (
        <div className="min-h-screen flex items-center justify-center bg-neutral-50 py-12 px-4 sm:px-6 lg:px-8">
            <div className="max-w-md w-full space-y-8">
                <div className="text-center">
                    <h1 className="text-3xl font-bold text-primary mb-2">Zvingo Partner</h1>
                </div>

                <Card className="shadow-lg border-neutral-100">
                    <CardHeader className="space-y-1 text-center">
                        <CardTitle className="text-2xl">Create Account</CardTitle>
                        <CardDescription>
                            Register your restaurant to start receiving orders
                        </CardDescription>
                    </CardHeader>
                    <CardContent>
                        {error && (
                            <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded-xl text-sm mb-6">
                                {error}
                            </div>
                        )}

                        <form className="space-y-6" onSubmit={handleRegister}>
                            <div className="space-y-4">
                                <div>
                                    <label htmlFor="fullName" className="block text-sm font-medium text-neutral-700 mb-1">Restaurant / Business Name</label>
                                    <Input
                                        id="fullName"
                                        name="fullName"
                                        type="text"
                                        required
                                        placeholder="Your Restaurant Name"
                                        value={fullName}
                                        onChange={(e) => setFullName(e.target.value)}
                                    />
                                </div>
                                <div>
                                    <label htmlFor="regEmail" className="block text-sm font-medium text-neutral-700 mb-1">Email Address</label>
                                    <Input
                                        id="regEmail"
                                        name="regEmail"
                                        type="email"
                                        placeholder="your@email.com (optional)"
                                        value={email}
                                        onChange={(e) => setEmail(e.target.value)}
                                    />
                                </div>
                                <div>
                                    <label htmlFor="regPhone" className="block text-sm font-medium text-neutral-700 mb-1">Phone Number *</label>
                                    <Input
                                        id="regPhone"
                                        name="regPhone"
                                        type="tel"
                                        required
                                        placeholder="+263 77 000 0000"
                                        value={phone}
                                        onChange={(e) => setPhone(e.target.value)}
                                    />
                                </div>
                                <div>
                                    <label htmlFor="regPassword" className="block text-sm font-medium text-neutral-700 mb-1">Password *</label>
                                    <Input
                                        id="regPassword"
                                        name="regPassword"
                                        type="password"
                                        required
                                        placeholder="Create a password"
                                        value={password}
                                        onChange={(e) => setPassword(e.target.value)}
                                    />
                                </div>
                                <div>
                                    <label htmlFor="regConfirmPassword" className="block text-sm font-medium text-neutral-700 mb-1">Confirm Password *</label>
                                    <Input
                                        id="regConfirmPassword"
                                        name="regConfirmPassword"
                                        type="password"
                                        required
                                        placeholder="Confirm your password"
                                        value={confirmPassword}
                                        onChange={(e) => setConfirmPassword(e.target.value)}
                                    />
                                </div>
                            </div>

                            <Button
                                type="submit"
                                className="w-full"
                                isLoading={loading}
                            >
                                Create Account
                            </Button>
                        </form>
                    </CardContent>
                    <CardFooter className="flex flex-col space-y-4 border-t border-neutral-100 bg-neutral-50/50 p-6 rounded-b-2xl">
                        <Link href="/forgot-password" className="text-sm text-neutral-500 hover:text-neutral-900 transition-colors">
                            Forgot your password?
                        </Link>
                        <div className="text-sm text-neutral-600">
                            Already have an account?{' '}
                            <Link href="/login" className="font-semibold text-primary hover:text-primary-hover transition-colors">
                                Sign in
                            </Link>
                        </div>
                    </CardFooter>
                </Card>
            </div>
        </div>
    );
}
