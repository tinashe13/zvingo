// Browser-facing backend base URL for API + SSE calls (inlined at build time).
// When NEXT_PUBLIC_API_URL is unset (local dev), calls go to the same-origin
// '/api' path, which next.config.ts rewrites to the local Nginx gateway.
// In production, either keep the proxy (set API_PROXY_URL at build time) or
// set NEXT_PUBLIC_API_URL to the public gateway URL (e.g. https://host/api).
export const API_BASE = process.env.NEXT_PUBLIC_API_URL || '/api';

// Base URL for direct backend calls (file uploads) that bypass the '/api'
// proxy in dev. Shares NEXT_PUBLIC_API_URL; falls back to the local backend.
export const UPLOAD_API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8000';

export async function apiFetch(path: string, options: RequestInit = {}) {
    const token = typeof window !== 'undefined' ? localStorage.getItem('zvingo_token') : null;

    const headers: Record<string, string> = {
        ...(options.headers as Record<string, string> || {}),
    };

    if (token) {
        headers['Authorization'] = `Bearer ${token}`;
    }

    // Only set Content-Type for JSON bodies (not FormData)
    if (options.body && typeof options.body === 'string') {
        headers['Content-Type'] = 'application/json';
    }

    const res = await fetch(`${API_BASE}${path}`, {
        ...options,
        headers,
    });

    if (res.status === 401) {
        localStorage.removeItem('zvingo_token');
        localStorage.removeItem('zvingo_user');
        if (typeof window !== 'undefined') {
            window.location.href = '/login';
        }
        throw new Error('Unauthorized');
    }

    return res;
}

export async function apiJson(path: string, options: RequestInit = {}) {
    const res = await apiFetch(path, options);
    if (!res.ok) {
        const text = await res.text();
        throw new Error(`API Error ${res.status}: ${text}`);
    }
    return res.json();
}

export function setToken(token: string) {
    localStorage.setItem('zvingo_token', token);
}

export function getToken(): string | null {
    return typeof window !== 'undefined' ? localStorage.getItem('zvingo_token') : null;
}

export function clearAuth() {
    localStorage.removeItem('zvingo_token');
    localStorage.removeItem('zvingo_user');
}
