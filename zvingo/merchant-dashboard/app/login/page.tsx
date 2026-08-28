'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { setToken } from '@/lib/api';
import { Button } from '@/components/ui/Button';
import { Input } from '@/components/ui/Input';
import { Card, CardContent, CardHeader, CardTitle, CardDescription, CardFooter } from '@/components/ui/Card';

export default function LoginPage() {
    const [email, setEmail] = useState('');
    const [password, setPassword] = useState('');
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState('');
    const router = useRouter();

    const handleLogin = async (e: React.FormEvent) => {
        e.preventDefault();
        setLoading(true);
        setError('');

        try {
            const res = await fetch('/api/auth/token', {
                method: 'POST',
                headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                body: new URLSearchParams({ username: email, password }),
            });

            if (!res.ok) {
                // Try to parse JSON, but handle cases where it fails (like 500 errors)
                let errorMessage = 'Invalid credentials';
                try {
                    const data = await res.json();
                    errorMessage = data.detail || errorMessage;
                } catch {
                    // ignore json parse error
                }
                throw new Error(errorMessage);
            }

            const data = await res.json();
            setToken(data.access_token);
            router.push('/dashboard');
        } catch (err: unknown) {
            setError(err instanceof Error ? err.message : 'Login failed');
        } finally {
            setLoading(false);
        }
    };

    return (
        <div className="min-h-screen flex items-center justify-center bg-neutral-900 py-12 px-4 sm:px-6 lg:px-8 relative overflow-hidden">
            <div className="absolute -left-24 -top-24 h-80 w-80 rounded-full bg-[#d7f654]/10 blur-3xl" />
            <div className="absolute -bottom-32 -right-20 h-96 w-96 rounded-full bg-primary/20 blur-3xl" />
            <div className="max-w-md w-full space-y-8">
                <div className="text-center">
                    <h1 className="text-3xl font-black tracking-[-0.04em] text-white mb-2">zvingo<span className="text-[#d7f654]">partner</span></h1>
                </div>

                <Card className="shadow-2xl border-0 rounded-3xl">
                    <CardHeader className="space-y-1 text-center">
                        <CardTitle className="text-3xl font-black tracking-tight">Welcome back</CardTitle>
                        <CardDescription>
                            Sign in to run tonight&apos;s service
                        </CardDescription>
                    </CardHeader>
                    <CardContent>
                        {error && (
                            <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded-xl text-sm mb-6">
                                {error}
                            </div>
                        )}

                        <form className="space-y-6" onSubmit={handleLogin}>
                            <div className="space-y-4">
                                <div>
                                    <label htmlFor="email" className="block text-sm font-medium text-neutral-700 mb-1">Email or Phone</label>
                                    <Input
                                        id="email"
                                        name="email"
                                        type="text"
                                        required
                                        placeholder="Email or Phone Number"
                                        value={email}
                                        onChange={(e) => setEmail(e.target.value)}
                                    />
                                </div>
                                <div>
                                    <label htmlFor="password" className="block text-sm font-medium text-neutral-700 mb-1">Password</label>
                                    <Input
                                        id="password"
                                        name="password"
                                        type="password"
                                        required
                                        placeholder="Password"
                                        value={password}
                                        onChange={(e) => setPassword(e.target.value)}
                                    />
                                </div>
                            </div>

                            <Button
                                type="submit"
                                className="w-full"
                                isLoading={loading}
                            >
                                Sign in
                            </Button>
                        </form>
                    </CardContent>
                    <CardFooter className="flex flex-col space-y-4 border-t border-neutral-100 bg-neutral-50/50 p-6 rounded-b-2xl">
                        <Link href="/forgot-password" className="text-sm text-neutral-500 hover:text-neutral-900 transition-colors">
                            Forgot your password?
                        </Link>
                        <div className="text-sm text-neutral-600">
                            Don&apos;t have an account?{' '}
                            <Link href="/register" className="font-semibold text-primary hover:text-primary-hover transition-colors">
                                Register here
                            </Link>
                        </div>
                    </CardFooter>
                </Card>
            </div>
        </div>
    );
}
