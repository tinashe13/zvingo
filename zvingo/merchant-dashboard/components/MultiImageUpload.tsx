"use client";

import * as React from "react";
import { ImagePlus, Star, UploadCloud, X } from "lucide-react";
import { errorMessage } from "@/lib/api";
import { SafeImage } from "@/components/ui/SafeImage";
import { useOptionalToast } from "@/components/ui/Toast";
import { cn } from "@/lib/cn";
import {
  ACCEPTED_IMAGE_TYPES,
  MAX_UPLOAD_BYTES,
  imageFilesFrom,
  rejectReason,
  uploadImage,
  useDropZone,
} from "@/components/ImageUpload";

interface MultiImageUploadProps {
  values: string[];
  onChange: (urls: string[]) => void;
  /** Hard ceiling on how many photos this gallery holds. */
  max?: number;
  disabled?: boolean;
}

interface Pending {
  key: string;
  name: string;
  percent: number;
}

const MAX_UPLOAD_MB = Math.round(MAX_UPLOAD_BYTES / (1024 * 1024));

/**
 * Gallery picker: drop, paste or choose several photos at once, watch each one
 * upload, promote any of them to the cover image, and remove with Undo.
 */
export default function MultiImageUpload({
  values = [],
  onChange,
  max = 8,
  disabled = false,
}: MultiImageUploadProps) {
  const [pending, setPending] = React.useState<Pending[]>([]);
  const [error, setError] = React.useState("");
  const toast = useOptionalToast();
  const inputRef = React.useRef<HTMLInputElement>(null);
  const valuesRef = React.useRef(values);
  React.useEffect(() => {
    valuesRef.current = values;
  }, [values]);

  const remaining = Math.max(0, max - values.length - pending.length);
  const busy = pending.length > 0;

  const handleFiles = React.useCallback(
    async (files: File[]) => {
      if (disabled) return;
      setError("");

      const accepted: File[] = [];
      const refusals: string[] = [];

      for (const file of files) {
        if (valuesRef.current.length + accepted.length >= max) {
          refusals.push(`You can add ${max} photos to one item. "${file.name}" was not added.`);
          continue;
        }
        const reason = await rejectReason(file);
        if (reason) refusals.push(reason);
        else accepted.push(file);
      }
      if (refusals.length) {
        setError(refusals[0]!);
        toast?.error(
          refusals.length === 1 ? "That photo was not accepted" : `${refusals.length} photos were not accepted`,
          { description: refusals[0] },
        );
      }
      if (!accepted.length) return;

      const queued: Pending[] = accepted.map((file, index) => ({
        key: `${Date.now()}-${index}-${file.name}`,
        name: file.name,
        percent: 0,
      }));
      setPending((prev) => [...prev, ...queued]);

      // One at a time: the endpoint is per-user rate limited, and a serial
      // queue keeps the progress bars honest. The running list is tracked here
      // rather than read back from props, so two quick uploads cannot race.
      let running = [...valuesRef.current];
      for (let index = 0; index < accepted.length; index += 1) {
        const file = accepted[index]!;
        const entry = queued[index]!;
        const { promise } = uploadImage(file, (percent) =>
          setPending((prev) => prev.map((p) => (p.key === entry.key ? { ...p, percent } : p))),
        );
        try {
          const url = await promise;
          running = [...running, url];
          valuesRef.current = running;
          onChange(running);
        } catch (err) {
          const message = errorMessage(err, "That photo could not be uploaded. Please try again.");
          setError(message);
          toast?.error("Upload failed", { description: message });
        } finally {
          setPending((prev) => prev.filter((p) => p.key !== entry.key));
        }
      }
    },
    [disabled, max, onChange, toast],
  );

  const { isDragging, zoneProps } = useDropZone(
    (files) => void handleFiles(files),
    disabled || remaining === 0,
  );

  function removeImage(index: number) {
    const removed = values[index];
    const next = values.filter((_, i) => i !== index);
    onChange(next);
    toast?.info(index === 0 ? "Cover photo removed" : "Photo removed", {
      description: index === 0 && next.length ? "The next photo is now the cover." : undefined,
      onUndo: removed
        ? () => {
            const restored = [...valuesRef.current];
            restored.splice(index, 0, removed);
            onChange(restored);
          }
        : undefined,
    });
  }

  function makeCover(index: number) {
    if (index === 0) return;
    const next = [...values];
    const [moved] = next.splice(index, 1);
    if (moved) next.unshift(moved);
    onChange(next);
    toast?.success("Cover photo updated", {
      description: "This is the photo customers see in the menu list.",
    });
  }

  return (
    <div
      {...zoneProps}
      tabIndex={-1}
      className={cn(
        "rounded-lg border bg-neutral-50 p-4 transition-colors",
        isDragging ? "border-action bg-brand-green-surface/40" : "border-border",
        disabled && "opacity-60",
      )}
    >
      <div className="flex flex-wrap gap-3">
        {values.map((url, index) => (
          <figure key={`${url}-${index}`} className="relative h-24 w-24">
            <SafeImage src={url} alt={`Photo ${index + 1}`} containerClassName="h-24 w-24 rounded-md" />
            {index === 0 && (
              <figcaption className="absolute inset-x-0 bottom-0 rounded-b-md bg-neutral-900/75 py-0.5 text-center type-caption font-bold text-neutral-0">
                Cover
              </figcaption>
            )}
            <button
              type="button"
              onClick={() => removeImage(index)}
              disabled={disabled}
              className="absolute right-1 top-1 flex h-8 w-8 items-center justify-center rounded-full bg-neutral-900/80 text-neutral-0 backdrop-blur transition-colors hover:bg-neutral-900 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-neutral-0"
              aria-label={`Remove photo ${index + 1}`}
            >
              <X className="h-4 w-4" aria-hidden="true" />
            </button>
            {index > 0 && (
              <button
                type="button"
                onClick={() => makeCover(index)}
                disabled={disabled}
                className="absolute left-1 top-1 flex h-8 w-8 items-center justify-center rounded-full bg-neutral-0/85 text-neutral-900 backdrop-blur transition-colors hover:bg-neutral-0 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-action"
                aria-label={`Make photo ${index + 1} the cover`}
                title="Make this the cover photo"
              >
                <Star className="h-4 w-4" aria-hidden="true" />
              </button>
            )}
          </figure>
        ))}

        {pending.map((entry) => (
          <div
            key={entry.key}
            className="flex h-24 w-24 flex-col items-center justify-center gap-2 rounded-md border border-border bg-surface px-2"
          >
            <div
              className="h-1.5 w-full overflow-hidden rounded-full bg-neutral-200"
              role="progressbar"
              aria-valuenow={entry.percent}
              aria-valuemin={0}
              aria-valuemax={100}
              aria-label={`Uploading ${entry.name}`}
            >
              <span
                className="block h-full rounded-full bg-action transition-[width] duration-200"
                style={{ width: `${entry.percent}%` }}
              />
            </div>
            <span className="type-caption tabular-figures text-text-secondary">{entry.percent}%</span>
          </div>
        ))}

        {remaining > 0 && (
          <button
            type="button"
            onClick={() => inputRef.current?.click()}
            disabled={disabled || busy}
            className="flex h-24 w-24 cursor-pointer flex-col items-center justify-center rounded-md border-[1.5px] border-dashed border-neutral-300 text-text-secondary transition-colors hover:border-neutral-500 hover:bg-surface focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-action disabled:cursor-not-allowed"
          >
            {isDragging ? (
              <UploadCloud className="h-5 w-5" aria-hidden="true" />
            ) : (
              <ImagePlus className="h-5 w-5" aria-hidden="true" />
            )}
            <span className="type-caption mt-2 font-bold">
              {isDragging ? "Drop here" : "Add photos"}
            </span>
          </button>
        )}
      </div>

      <p className="type-caption mt-3 text-text-secondary">
        {remaining === 0
          ? `All ${max} photo slots are used. Remove one to add another.`
          : `Drag photos in, paste from the clipboard, or choose files. JPG, PNG, WEBP or GIF up to ${MAX_UPLOAD_MB} MB each — ${remaining} ${remaining === 1 ? "slot" : "slots"} left. The first photo is the cover.`}
      </p>

      {error && (
        <p role="alert" className="type-caption mt-2 text-error">
          {error}
        </p>
      )}

      <input
        ref={inputRef}
        type="file"
        multiple
        accept={ACCEPTED_IMAGE_TYPES}
        onChange={(e) => {
          const files = imageFilesFrom(e.target.files);
          e.target.value = "";
          void handleFiles(files);
        }}
        disabled={disabled || busy || remaining === 0}
        className="sr-only"
        aria-label="Add photos to this item"
      />
    </div>
  );
}
