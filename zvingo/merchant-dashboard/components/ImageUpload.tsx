"use client";

import * as React from "react";
import { ImagePlus, Trash2, UploadCloud } from "lucide-react";
import { UPLOAD_API_URL, errorMessage, getToken } from "@/lib/api";
import { Button } from "@/components/ui/Button";
import { SafeImage } from "@/components/ui/SafeImage";
import { useOptionalToast } from "@/components/ui/Toast";
import { cn } from "@/lib/cn";

/* -------------------------------------------------------------------------- */
/* Client-side contract with POST /upload/                                    */
/* -------------------------------------------------------------------------- */

/**
 * The backend (`backend/app/upload/router.py`) requires authentication, sniffs
 * magic bytes, refuses polyglots and markup, randomises the stored filename and
 * caps the size *while streaming*. Everything below mirrors those rules so the
 * merchant is told what is wrong before a byte leaves the browser.
 */

/** Extensions the server writes. Anything else is refused with a 400. */
const ALLOWED_EXTENSIONS = [".jpg", ".jpeg", ".png", ".webp", ".gif"] as const;

/** MIME types the file picker offers. */
export const ACCEPTED_IMAGE_TYPES = "image/jpeg,image/png,image/webp,image/gif";

/** Matches `settings.MAX_UPLOAD_SIZE_BYTES` (5 MB by default). */
const MAX_UPLOAD_MB = Math.max(1, Number(process.env.NEXT_PUBLIC_MAX_UPLOAD_MB || "5") || 5);
export const MAX_UPLOAD_BYTES = MAX_UPLOAD_MB * 1024 * 1024;

/** Magic-byte signatures the server accepts, checked here first. */
const SIGNATURES: Array<{ bytes: number[]; offset: number; label: string }> = [
  { bytes: [0xff, 0xd8, 0xff], offset: 0, label: "JPEG" },
  { bytes: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a], offset: 0, label: "PNG" },
  { bytes: [0x47, 0x49, 0x46, 0x38, 0x37, 0x61], offset: 0, label: "GIF" },
  { bytes: [0x47, 0x49, 0x46, 0x38, 0x39, 0x61], offset: 0, label: "GIF" },
];

function formatBytes(bytes: number): string {
  if (bytes >= 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${Math.max(1, Math.round(bytes / 1024))} KB`;
}

function extensionOf(name: string): string {
  const dot = name.lastIndexOf(".");
  return dot === -1 ? "" : name.slice(dot).toLowerCase();
}

/**
 * Cheap checks that need no network: type, extension and size.
 * Returns a plain-language reason, or `null` when the file looks fine.
 */
export function quickRejectReason(file: File): string | null {
  const extension = extensionOf(file.name);

  if (file.type === "image/svg+xml" || extension === ".svg") {
    return "SVG files can carry scripts, so Zvingo does not accept them. Export the picture as a JPG or PNG instead.";
  }
  if (file.type && !file.type.startsWith("image/")) {
    return `That file is a ${file.type.split("/").pop()?.toUpperCase() || "document"}, not a photo. Choose a JPG, PNG, WEBP or GIF.`;
  }
  if (extension && !ALLOWED_EXTENSIONS.includes(extension as (typeof ALLOWED_EXTENSIONS)[number])) {
    return `${extension} files are not supported. Choose a JPG, PNG, WEBP or GIF.`;
  }
  if (file.size === 0) {
    return "That file is empty. Choose a different photo.";
  }
  if (file.size > MAX_UPLOAD_BYTES) {
    return `That photo is ${formatBytes(file.size)}. The limit is ${MAX_UPLOAD_MB} MB — try a smaller version or a screenshot of it.`;
  }
  return null;
}

/**
 * Read the first bytes and confirm they really are an image, the same way the
 * server does. Catches a `.png` that is actually a PDF before the round trip.
 * Fails open (returns `null`) if the browser cannot read the slice.
 */
async function signatureRejectReason(file: File): Promise<string | null> {
  let head: Uint8Array;
  try {
    head = new Uint8Array(await file.slice(0, 16).arrayBuffer());
  } catch {
    return null;
  }
  if (head.length < 4) return "That file is too small to be a photo.";

  const matches = SIGNATURES.some(({ bytes, offset }) =>
    bytes.every((byte, index) => head[offset + index] === byte),
  );
  const isWebp =
    head.length >= 12 &&
    head[0] === 0x52 &&
    head[1] === 0x49 &&
    head[2] === 0x46 &&
    head[3] === 0x46 &&
    head[8] === 0x57 &&
    head[9] === 0x45 &&
    head[10] === 0x42 &&
    head[11] === 0x50;

  if (matches || isWebp) return null;
  return "That file is not a JPG, PNG, WEBP or GIF, whatever its name says. Re-save it as a photo and try again.";
}

/** Full pre-flight. Returns a plain-language reason, or `null` to proceed. */
export async function rejectReason(file: File): Promise<string | null> {
  return quickRejectReason(file) ?? (await signatureRejectReason(file));
}

export class UploadRejected extends Error {}

function friendlyUploadError(status: number, payload: unknown): string {
  const detail =
    payload && typeof payload === "object"
      ? (payload as { detail?: unknown }).detail
      : undefined;
  if (typeof detail === "string" && detail.trim()) {
    // The upload router writes merchant-readable refusals already.
    return detail.trim().replace(/^\w/, (c) => c.toUpperCase());
  }
  if (status === 401) return "Your session has expired. Sign in again to upload photos.";
  if (status === 403) return "You do not have permission to upload photos.";
  if (status === 413) return `That photo is over ${MAX_UPLOAD_MB} MB. Try a smaller version.`;
  if (status === 429) return "You have uploaded a lot of photos just now. Wait a minute and try again.";
  if (status >= 500) return "Zvingo could not store the photo just now. Please try again.";
  return "The photo could not be uploaded. Please try again.";
}

/**
 * Upload one image, reporting real byte-level progress.
 *
 * `fetch` cannot report upload progress, so this uses `XMLHttpRequest` — the
 * one place in the dashboard that does. Resolves with the stored image URL.
 */
export function uploadImage(
  file: File,
  onProgress?: (percent: number) => void,
): { promise: Promise<string>; abort: () => void } {
  const xhr = new XMLHttpRequest();

  const promise = new Promise<string>((resolve, reject) => {
    const form = new FormData();
    form.append("file", file);

    xhr.open("POST", `${UPLOAD_API_URL}/upload/`);
    xhr.responseType = "text";
    const token = getToken();
    if (token) xhr.setRequestHeader("Authorization", `Bearer ${token}`);
    xhr.setRequestHeader("Accept", "application/json");

    xhr.upload.onprogress = (event) => {
      if (!event.lengthComputable) return;
      // Hold at 99% until the server answers — the bytes are sent, but the
      // magic-byte check and disk write still have to succeed.
      onProgress?.(Math.min(99, Math.round((event.loaded / event.total) * 100)));
    };

    xhr.onerror = () =>
      reject(new UploadRejected("We could not reach Zvingo. Check your connection and try again."));
    xhr.ontimeout = () =>
      reject(new UploadRejected("The upload took too long. Check your connection and try again."));
    xhr.onabort = () => reject(new UploadRejected("Upload cancelled."));

    xhr.onload = () => {
      let payload: unknown = null;
      try {
        payload = xhr.responseText ? JSON.parse(xhr.responseText) : null;
      } catch {
        payload = null;
      }
      if (xhr.status < 200 || xhr.status >= 300) {
        reject(new UploadRejected(friendlyUploadError(xhr.status, payload)));
        return;
      }
      const url = (payload as { url?: string } | null)?.url;
      if (!url) {
        reject(new UploadRejected("Zvingo stored the photo but did not return a link. Please try again."));
        return;
      }
      onProgress?.(100);
      // The backend may answer with a path; make it absolute for the browser.
      resolve(url.startsWith("/") ? `${UPLOAD_API_URL}${url}` : url);
    };

    xhr.timeout = 60_000;
    xhr.send(form);
  });

  return { promise, abort: () => xhr.abort() };
}

/* -------------------------------------------------------------------------- */
/* Shared drop-zone behaviour                                                 */
/* -------------------------------------------------------------------------- */

/** Pull image files out of a drop or paste event. */
export function imageFilesFrom(
  source: DataTransfer | DataTransferItemList | FileList | null | undefined,
): File[] {
  if (!source) return [];
  if (source instanceof DataTransfer) return Array.from(source.files);
  if (typeof (source as FileList).length === "number" && (source as FileList).item) {
    const list = source as FileList;
    return Array.from({ length: list.length }, (_, i) => list.item(i)).filter(
      (f): f is File => Boolean(f),
    );
  }
  const items = source as DataTransferItemList;
  return Array.from(items)
    .filter((item) => item.kind === "file")
    .map((item) => item.getAsFile())
    .filter((f): f is File => Boolean(f));
}

export interface DropZoneHandlers {
  isDragging: boolean;
  /** Spread onto the element that should accept drops and pastes. */
  zoneProps: {
    onDragOver: (e: React.DragEvent) => void;
    onDragEnter: (e: React.DragEvent) => void;
    onDragLeave: (e: React.DragEvent) => void;
    onDrop: (e: React.DragEvent) => void;
    onPaste: (e: React.ClipboardEvent) => void;
  };
}

/** Drag-and-drop + paste plumbing shared by both pickers. */
export function useDropZone(onFiles: (files: File[]) => void, disabled = false): DropZoneHandlers {
  const [isDragging, setIsDragging] = React.useState(false);
  const depth = React.useRef(0);
  const onFilesRef = React.useRef(onFiles);
  React.useEffect(() => {
    onFilesRef.current = onFiles;
  });

  const reset = React.useCallback(() => {
    depth.current = 0;
    setIsDragging(false);
  }, []);

  return {
    isDragging,
    zoneProps: {
      onDragOver: (e) => {
        if (disabled) return;
        e.preventDefault();
      },
      onDragEnter: (e) => {
        if (disabled) return;
        e.preventDefault();
        depth.current += 1;
        setIsDragging(true);
      },
      onDragLeave: (e) => {
        if (disabled) return;
        e.preventDefault();
        depth.current -= 1;
        if (depth.current <= 0) reset();
      },
      onDrop: (e) => {
        if (disabled) return;
        e.preventDefault();
        reset();
        const files = imageFilesFrom(e.dataTransfer);
        if (files.length) onFilesRef.current(files);
      },
      onPaste: (e) => {
        if (disabled) return;
        const files = imageFilesFrom(e.clipboardData?.items);
        if (!files.length) return;
        e.preventDefault();
        onFilesRef.current(files);
      },
    },
  };
}

/** Slim determinate progress bar. Never a spinner — the merchant wants bytes. */
export function UploadProgress({ percent, label }: { percent: number; label: string }) {
  return (
    <div className="mt-2.5">
      <div
        className="h-1.5 w-full overflow-hidden rounded-full bg-neutral-200"
        role="progressbar"
        aria-valuenow={percent}
        aria-valuemin={0}
        aria-valuemax={100}
        aria-label={label}
      >
        <span
          className="block h-full rounded-full bg-action transition-[width] duration-200 ease-[var(--ease-standard)]"
          style={{ width: `${percent}%` }}
        />
      </div>
      <p className="type-caption mt-1.5 tabular-figures text-text-secondary">
        {percent < 100 ? `Uploading… ${percent}%` : "Checking the photo…"}
      </p>
    </div>
  );
}

/* -------------------------------------------------------------------------- */
/* Single image picker                                                        */
/* -------------------------------------------------------------------------- */

export interface ImageUploadProps {
  value: string;
  onChange: (url: string) => void;
  placeholder?: string;
  /** Short line describing what this image is for. */
  help?: string;
  disabled?: boolean;
}

/** Single-image picker with a live preview, used for logos and item photos. */
export default function ImageUpload({
  value,
  onChange,
  placeholder,
  help,
  disabled = false,
}: ImageUploadProps) {
  const [percent, setPercent] = React.useState<number | null>(null);
  const [error, setError] = React.useState("");
  const inputRef = React.useRef<HTMLInputElement>(null);
  const abortRef = React.useRef<(() => void) | null>(null);
  const toast = useOptionalToast();
  const uploading = percent !== null;

  React.useEffect(() => () => abortRef.current?.(), []);

  const handleFiles = React.useCallback(
    async (files: File[]) => {
      const file = files[0];
      if (!file || disabled) return;

      const reason = await rejectReason(file);
      if (reason) {
        setError(reason);
        toast?.error("That photo was not accepted", { description: reason });
        return;
      }

      setError("");
      setPercent(0);
      const { promise, abort } = uploadImage(file, setPercent);
      abortRef.current = abort;
      try {
        const url = await promise;
        onChange(url);
        toast?.success("Photo updated");
      } catch (err) {
        const message = errorMessage(err, "The photo could not be uploaded. Please try again.");
        if (message !== "Upload cancelled.") {
          setError(message);
          toast?.error("Upload failed", { description: message });
        }
      } finally {
        abortRef.current = null;
        setPercent(null);
      }
    },
    [disabled, onChange, toast],
  );

  const { isDragging, zoneProps } = useDropZone(
    (files) => void handleFiles(files),
    disabled || uploading,
  );

  const describedBy = error ? "image-upload-error" : undefined;

  return (
    <div
      {...zoneProps}
      tabIndex={-1}
      className={cn(
        "flex items-start gap-4 rounded-lg border bg-neutral-50 p-3 transition-colors",
        isDragging ? "border-action bg-brand-green-surface/40" : "border-border",
        disabled && "opacity-60",
      )}
    >
      <SafeImage
        src={value}
        alt={value ? "Current image" : placeholder || "No image chosen yet"}
        containerClassName="h-20 w-20 shrink-0 rounded-md"
        fallbackIcon={isDragging ? UploadCloud : ImagePlus}
      />

      <div className="min-w-0 flex-1">
        <p className="type-caption font-semibold text-neutral-800">
          {isDragging ? "Drop the photo here" : value ? "Replace photo" : "Add a photo"}
        </p>
        <p className="type-caption mt-0.5 text-text-secondary">
          {help || `JPG, PNG, WEBP or GIF up to ${MAX_UPLOAD_MB} MB. Drag one in or paste from your clipboard.`}
        </p>

        {uploading ? (
          <UploadProgress percent={percent ?? 0} label="Uploading photo" />
        ) : (
          <div className="mt-2.5 flex flex-wrap items-center gap-2">
            <Button
              type="button"
              variant="secondary"
              size="sm"
              disabled={disabled}
              onClick={() => inputRef.current?.click()}
            >
              {value ? "Choose a different photo" : "Choose photo"}
            </Button>
            {value && (
              <Button
                type="button"
                variant="tertiary"
                size="sm"
                disabled={disabled}
                onClick={() => {
                  const removed = value;
                  onChange("");
                  toast?.info("Photo removed", { onUndo: () => onChange(removed) });
                }}
                leftIcon={<Trash2 className="h-4 w-4" />}
              >
                Remove
              </Button>
            )}
          </div>
        )}

        {error && (
          <p id={describedBy} role="alert" className="type-caption mt-2 text-error">
            {error}
          </p>
        )}

        <input
          ref={inputRef}
          type="file"
          accept={ACCEPTED_IMAGE_TYPES}
          onChange={(e) => {
            const files = imageFilesFrom(e.target.files);
            e.target.value = "";
            void handleFiles(files);
          }}
          disabled={disabled || uploading}
          className="sr-only"
          aria-describedby={describedBy}
          aria-label={placeholder || "Upload a photo"}
        />
      </div>
    </div>
  );
}
