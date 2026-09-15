"use client";

import { useRef, useState } from "react";
import { ImagePlus, Trash2 } from "lucide-react";
import { UPLOAD_API_URL, api, errorMessage } from "@/lib/api";
import { Button } from "@/components/ui/Button";
import { SafeImage } from "@/components/ui/SafeImage";
import { useOptionalToast } from "@/components/ui/Toast";

interface ImageUploadProps {
    value: string;
    onChange: (url: string) => void;
    placeholder?: string;
}

const MAX_BYTES = 5 * 1024 * 1024;

/** Single-image picker with a live preview, used for logos and item photos. */
export default function ImageUpload({ value, onChange, placeholder }: ImageUploadProps) {
    const [uploading, setUploading] = useState(false);
    const [error, setError] = useState("");
    const inputRef = useRef<HTMLInputElement>(null);
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
            // The backend may answer with a path; make it absolute for the browser.
            const url = data.url.startsWith("/") ? `${UPLOAD_API_URL}${data.url}` : data.url;
            onChange(url);
            toast?.success("Image uploaded");
        } catch (err) {
            const message = errorMessage(err, "The image could not be uploaded. Please try again.");
            setError(message);
            toast?.error("Upload failed", { description: message });
        } finally {
            setUploading(false);
            e.target.value = "";
        }
    };

    return (
        <div className="flex items-center gap-4 rounded-lg border border-border bg-neutral-50 p-3">
            <SafeImage
                src={value}
                alt={value ? "Current image" : placeholder || "No image chosen yet"}
                containerClassName="h-20 w-20 shrink-0 rounded-md"
                fallbackIcon={ImagePlus}
            />

            <div className="min-w-0 flex-1">
                <p className="type-caption font-semibold text-neutral-800">
                    {value ? "Replace image" : "Add an image"}
                </p>
                <p className="type-caption mt-0.5 text-text-secondary">
                    JPG or PNG, up to 5 MB. Square photos look best.
                </p>

                <div className="mt-2.5 flex flex-wrap items-center gap-2">
                    <Button
                        variant="secondary"
                        size="sm"
                        loading={uploading}
                        onClick={() => inputRef.current?.click()}
                    >
                        {value ? "Choose a different image" : "Choose image"}
                    </Button>
                    {value && !uploading && (
                        <Button
                            variant="tertiary"
                            size="sm"
                            onClick={() => onChange("")}
                            leftIcon={<Trash2 className="h-4 w-4" />}
                        >
                            Remove
                        </Button>
                    )}
                </div>

                {error && (
                    <p role="alert" className="type-caption mt-2 text-error">
                        {error}
                    </p>
                )}

                <input
                    ref={inputRef}
                    type="file"
                    accept="image/*"
                    onChange={handleFileChange}
                    disabled={uploading}
                    className="sr-only"
                    aria-label={placeholder || "Upload an image"}
                />
            </div>
        </div>
    );
}
