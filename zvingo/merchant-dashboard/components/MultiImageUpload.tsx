"use client";

import { useState } from 'react';
import { ImagePlus, Loader2, X } from 'lucide-react';
import { getToken, UPLOAD_API_URL } from '@/lib/api';

interface MultiImageUploadProps {
    values: string[];
    onChange: (urls: string[]) => void;
}

export default function MultiImageUpload({ values = [], onChange }: MultiImageUploadProps) {
    const [uploading, setUploading] = useState(false);

    const handleFileChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
        const file = e.target.files?.[0];
        if (!file) return;

        try {
            setUploading(true);
            const formData = new FormData();
            formData.append('file', file);

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
            let url = data.url;
            if (url.startsWith('/')) {
                url = `${UPLOAD_API_URL}${url}`;
            }

            onChange([...values, url]);
        } catch (err) {
            console.error(err);
            alert('Failed to upload image');
        } finally {
            setUploading(false);
            // Reset input
            e.target.value = '';
        }
    };

    const removeImage = (index: number) => {
        const newValues = [...values];
        newValues.splice(index, 1);
        onChange(newValues);
    };

    return (
        <div className="rounded-2xl bg-neutral-50 p-4">
            <div className="flex flex-wrap gap-3">
                {values.map((url, index) => (
                    <div key={index} className="group relative h-24 w-24 overflow-hidden rounded-xl bg-neutral-200">
                        <img src={url} alt={`Preview ${index}`} className="h-full w-full object-cover" />
                        <button
                            type="button"
                            onClick={() => removeImage(index)}
                            className="absolute right-1.5 top-1.5 flex h-7 w-7 items-center justify-center rounded-full bg-neutral-900/80 text-white opacity-0 backdrop-blur transition-opacity group-hover:opacity-100 focus:opacity-100"
                            aria-label={`Remove image ${index + 1}`}
                        >
                            <X className="h-3.5 w-3.5" />
                        </button>
                    </div>
                ))}

                <label className="flex h-24 w-24 cursor-pointer flex-col items-center justify-center rounded-xl border-2 border-dashed border-neutral-300 text-neutral-500 transition-colors hover:border-neutral-500 hover:bg-white">
                    {uploading ? <Loader2 className="h-5 w-5 animate-spin" /> : <ImagePlus className="h-5 w-5" />}
                    <span className="mt-2 text-xs font-bold">{uploading ? 'Uploading' : 'Add image'}</span>
                    <input
                        type="file"
                        accept="image/*"
                        onChange={handleFileChange}
                        disabled={uploading}
                        className="hidden"
                    />
                </label>
            </div>
        </div>
    );
}
