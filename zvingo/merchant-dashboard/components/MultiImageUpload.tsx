"use client";

import { useState } from "react";
import { ImagePlus, X } from "lucide-react";
import { UPLOAD_API_URL, api, errorMessage } from "@/lib/api";
import { SafeImage } from "@/components/ui/SafeImage";
import { Spinner } from "@/components/ui/Spinner";
import { useOptionalToast } from "@/components/ui/Toast";

interface MultiImageUploadProps {
    values: string[];
    onChange: (urls: string[]) => void;
}

const MAX_BYTES = 5 * 1024 * 1024;

/** Gallery picker: add photos one at a time, remove any of them. */
export default function MultiImageUpload({ values = [], onChange }: MultiImageUploadProps) {
    const [uploading, setUploading] = useState(false);
    const [error, setError] = useState("");
    const toast = useOptionalToast();

    const handleFileChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
        const file = e.target.files?.[0];
        if (!file) return;

        if (file.size > MAX_BYTES) {
            const message = "That image is over 5 MB. Try a smaller photo.";
            setError(message);
            toast?.error("Image too large", { description: message });
            e.target.value = "";
            return;
        }

        setError("");
        setUploading(true);
        try {
            const form = new FormData();
            form.append("file", file);
            const data = await api.upload<{ url: string }>("/upload/", form);
            const url = data.url.startsWith("/") ? `${UPLOAD_API_URL}${data.url}` : data.url;
            onChange([...values, url]);
        } catch (err) {
            const message = errorMessage(err, "The image could not be uploaded. Please try again.");
            setError(message);
            toast?.error("Upload failed", { description: message });
        } finally {
            setUploading(false);
            e.target.value = "";
        }
    };

    const removeImage = (index: number) => {
        const removed = values[index];
        const next = values.filter((_, i) => i !== index);
        onChange(next);
        toast?.info("Photo removed", {
            onUndo: removed
                ? () => {
                      const restored = [...next];
                      restored.splice(index, 0, removed);
                      onChange(restored);
                  }
                : undefined,
        });
    };

    return (
        <div className="rounded-lg border border-border bg-neutral-50 p-4">
            <div className="flex flex-wrap gap-3">
                {values.map((url, index) => (
                    <div key={`${url}-${index}`} className="group relative h-24 w-24">
                        <SafeImage
                            src={url}
                            alt={`Photo ${index + 1}`}
                            containerClassName="h-24 w-24 rounded-md"
                        />
                        <button
                            type="button"
                            onClick={() => removeImage(index)}
                            className="absolute right-1.5 top-1.5 flex h-8 w-8 items-center justify-center rounded-full bg-neutral-900/80 text-neutral-0 backdrop-blur transition-opacity hover:bg-neutral-900 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-neutral-0"
                            aria-label={`Remove photo ${index + 1}`}
                        >
                            <X className="h-4 w-4" aria-hidden="true" />
                        </button>
                    </div>
                ))}

                <label className="flex h-24 w-24 cursor-pointer flex-col items-center justify-center rounded-md border-[1.5px] border-dashed border-neutral-300 text-text-secondary transition-colors hover:border-neutral-500 hover:bg-surface focus-within:outline-2 focus-within:outline-offset-2 focus-within:outline-action">
                    {uploading ? (
                        <Spinner size={20} label="Uploading" />
                    ) : (
                        <ImagePlus className="h-5 w-5" aria-hidden="true" />
                    )}
                    <span className="type-caption mt-2 font-bold">
                        {uploading ? "Uploading" : "Add photo"}
                    </span>
                    <input
                        type="file"
                        accept="image/*"
                        onChange={handleFileChange}
                        disabled={uploading}
                        className="sr-only"
                    />
                </label>
            </div>

            {error && (
                <p role="alert" className="type-caption mt-3 text-error">
                    {error}
                </p>
            )}
        </div>
    );
}
