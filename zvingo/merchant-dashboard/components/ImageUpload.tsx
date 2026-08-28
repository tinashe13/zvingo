"use client";

import { useState } from 'react';
import { ImagePlus, Loader2 } from 'lucide-react';
import { getToken, UPLOAD_API_URL } from '@/lib/api';

interface ImageUploadProps {
    value: string;
    onChange: (url: string) => void;
    placeholder?: string;
}

export default function ImageUpload({ value, onChange, placeholder }: ImageUploadProps) {
    const [uploading, setUploading] = useState(false);

    const handleFileChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
        const file = e.target.files?.[0];
        if (!file) return;

        try {
            setUploading(true);
            const formData = new FormData();
            formData.append('file', file);

            // Use direct fetch since apiJson handles JSON
            const token = getToken();
            const res = await fetch(`${UPLOAD_API_URL}/upload/`, {
                method: 'POST',
                headers: {
                    'Authorization': `Bearer ${token}`
                },
                body: formData
            });

            if (!res.ok) throw new Error('Upload failed');

            const data = await res.json();
            // Ensure we get a full URL. If backend returns relative, prepend API URL
            // specific to this implementation where static runs on same port
            let url = data.url;
            if (url.startsWith('/')) {
                url = `${UPLOAD_API_URL}${url}`;
            }

            onChange(url);
        } catch (err) {
            console.error(err);
            alert('Failed to upload image');
        } finally {
            setUploading(false);
        }
    };

    return (
        <div className="flex items-center gap-4 rounded-2xl bg-neutral-50 p-3">
            <div className="flex h-20 w-20 shrink-0 items-center justify-center overflow-hidden rounded-xl bg-neutral-200">
                {value ? (
                    <img src={value} alt="Preview" className="h-full w-full object-cover" />
                ) : (
                    <ImagePlus className="h-6 w-6 text-neutral-400" aria-label={placeholder || "No image"} />
                )}
            </div>
            <div className="min-w-0 flex-1">
                <label className="mb-2 flex items-center gap-2 text-sm font-bold text-neutral-800">
                    {uploading && <Loader2 className="h-4 w-4 animate-spin" />}{uploading ? 'Uploading image' : value ? 'Replace image' : 'Choose image'}
                </label>
                <input
                    type="file"
                    accept="image/*"
                    onChange={handleFileChange}
                    disabled={uploading}
                    className="block w-full text-xs text-neutral-500 file:mr-3 file:rounded-lg file:border-0 file:bg-neutral-900 file:px-3 file:py-2 file:text-xs file:font-bold file:text-white hover:file:bg-neutral-800"
                />
            </div>
        </div>
    );
}
