"use client";

import { useState } from 'react';
import { UPLOAD_API_URL } from '@/lib/api';

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
            const token = localStorage.getItem('token');
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
        <div className="mt-1 flex items-center space-x-4">
            <div className="h-20 w-20 rounded bg-gray-100 flex items-center justify-center overflow-hidden border border-gray-300">
                {value ? (
                    <img src={value} alt="Preview" className="h-full w-full object-cover" />
                ) : (
                    <span className="text-gray-400 text-xs text-center p-1">{placeholder || "No Image"}</span>
                )}
            </div>
            <div>
                <label className="block text-sm font-medium text-gray-700">
                    {uploading ? 'Uploading...' : 'Change'}
                </label>
                <input
                    type="file"
                    accept="image/*"
                    onChange={handleFileChange}
                    disabled={uploading}
                    className="block w-full text-sm text-gray-500
                        file:mr-4 file:py-2 file:px-4
                        file:rounded-full file:border-0
                        file:text-sm file:font-semibold
                        file:bg-green-50 file:text-green-700
                        hover:file:bg-green-100"
                />
            </div>
        </div>
    );
}
