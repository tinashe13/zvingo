"use client";

import { useState } from 'react';
import { UPLOAD_API_URL } from '@/lib/api';

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
        <div className="space-y-2">
            <div className="flex flex-wrap gap-4">
                {values.map((url, index) => (
                    <div key={index} className="relative h-24 w-24 rounded-lg overflow-hidden border border-gray-200 group">
                        <img src={url} alt={`Preview ${index}`} className="h-full w-full object-cover" />
                        <button
                            type="button"
                            onClick={() => removeImage(index)}
                            className="absolute top-1 right-1 bg-red-500 text-white rounded-full p-1 opacity-0 group-hover:opacity-100 transition-opacity"
                        >
                            <svg xmlns="http://www.w3.org/2000/svg" className="h-3 w-3" viewBox="0 0 20 20" fill="currentColor">
                                <path fillRule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clipRule="evenodd" />
                            </svg>
                        </button>
                    </div>
                ))}

                <label className="h-24 w-24 flex flex-col items-center justify-center border-2 border-dashed border-gray-300 rounded-lg cursor-pointer hover:bg-gray-50 transition-colors">
                    <span className="text-2xl text-gray-400">+</span>
                    <span className="text-xs text-gray-500 mt-1">{uploading ? '...' : 'Add'}</span>
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
