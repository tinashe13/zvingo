"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { Building2, Clock3, ExternalLink, LogOut, MapPin, Save, ShieldCheck, Store } from "lucide-react";
import { apiJson, clearAuth } from "@/lib/api";
import ImageUpload from "@/components/ImageUpload";
import { Button } from "@/components/ui/Button";
import { Input } from "@/components/ui/Input";
import { Field, LoadingState, PageHeader, PageShell, Panel, StatusBadge, Toggle } from "@/components/merchant/Page";

const IS_DEV = process.env.NODE_ENV === "development";
type Profile = { full_name?: string; email?: string; phone?: string; role?: string };
type Restaurant = { id?: string; _id?: string; name?: string; description?: string; image_url?: string; banner_url?: string; is_active?: boolean; operating_hours?: string; location?: { coordinates?: number[] } };

export default function SettingsPage() {
    const [profile, setProfile] = useState<Profile | null>(null);
    const [restaurant, setRestaurant] = useState<Restaurant | null>(null);
    const [loading, setLoading] = useState(true);
    const [name, setName] = useState("");
    const [description, setDescription] = useState("");
    const [imageUrl, setImageUrl] = useState("");
    const [bannerUrl, setBannerUrl] = useState("");
    const [lat, setLat] = useState("");
    const [lng, setLng] = useState("");
    const [isOpen, setIsOpen] = useState(true);
    const [openTime, setOpenTime] = useState("08:00");
    const [closeTime, setCloseTime] = useState("22:00");
    const [isSaving, setIsSaving] = useState(false);
    const [saved, setSaved] = useState(false);
    const [isResettingLocation, setIsResettingLocation] = useState(false);
    const [isSettingTestLocation, setIsSettingTestLocation] = useState(false);
    const router = useRouter();

    useEffect(() => { loadData(); }, []);
    async function loadData() {
        try {
            const me = await apiJson("/auth/me"); setProfile(me);
            const restaurants = await apiJson(`/catalog/restaurants?merchant_id=${me.id}`);
            if (restaurants?.length) {
                const current = restaurants[0] as Restaurant; setRestaurant(current);
                setName(current.name || ""); setDescription(current.description || ""); setImageUrl(current.image_url || ""); setBannerUrl(current.banner_url || ""); setIsOpen(current.is_active ?? false);
                if (current.operating_hours) { const [open, close] = current.operating_hours.split("-"); if (open && close) { setOpenTime(open); setCloseTime(close); } }
                const coords = current.location?.coordinates; if (coords?.length === 2) { setLng(String(coords[0])); setLat(String(coords[1])); }
            }
        } catch (err) { console.error("Failed to load settings:", err); }
        finally { setLoading(false); }
    }

    async function handleSaveRestaurant() {
        const id = restaurant?.id || restaurant?._id; if (!id) return;
        setIsSaving(true); setSaved(false);
        try {
            const updated = await apiJson(`/catalog/restaurants/${id}`, { method: "PUT", body: JSON.stringify({ name, description, image_url: imageUrl, banner_url: bannerUrl, lat: lat ? Number(lat) : undefined, lng: lng ? Number(lng) : undefined, is_active: isOpen, operating_hours: `${openTime}-${closeTime}` }) });
            setRestaurant(updated); setSaved(true); window.setTimeout(() => setSaved(false), 2500);
        } catch (err) { console.error("Failed to save settings:", err); alert("Failed to save settings."); }
        finally { setIsSaving(false); }
    }

    async function handleResetLocation() { if (!restaurant) return; setIsResettingLocation(true); try { await apiJson("/catalog/admin/reset-locations?force_all=true", { method: "POST" }); await loadData(); } catch (err) { console.error("Failed to reset locations:", err); alert("Failed to reset restaurant locations."); } finally { setIsResettingLocation(false); } }
    async function handleSetTestLocation() { const id = restaurant?.id || restaurant?._id; if (!id) return; setIsSettingTestLocation(true); try { const testLat = 37.458; const testLng = -122.084; const updated = await apiJson(`/catalog/restaurants/${id}`, { method: "PUT", body: JSON.stringify({ lat: testLat, lng: testLng }) }); setRestaurant(updated); setLat(String(testLat)); setLng(String(testLng)); } catch (err) { console.error("Failed to set test location:", err); alert("Failed to set test location."); } finally { setIsSettingTestLocation(false); } }
    function handleSignOut() { clearAuth(); router.push("/login"); }

    if (loading) return <LoadingState />;

    return (
        <PageShell>
            <PageHeader eyebrow="OPERATIONS" title="Settings" description="Control how your restaurant appears, when customers can order, and where drivers collect orders." actions={<><span className={`text-sm font-bold text-primary transition-opacity ${saved ? "opacity-100" : "opacity-0"}`}>Changes saved</span><Button onClick={handleSaveRestaurant} isLoading={isSaving} disabled={!restaurant}><Save className="mr-2 h-4 w-4" />Save changes</Button></>} />
            <div className="grid items-start gap-6 xl:grid-cols-[1.45fr_.75fr]">
                <div className="space-y-6">
                    <Panel title="Store availability" description="Customers can only place orders while the store is open."><div className="p-6 sm:p-7"><Toggle checked={isOpen} onChange={() => setIsOpen(!isOpen)} label={isOpen ? "Open and accepting orders" : "Store is currently closed"} description={isOpen ? "Your menu is visible and orders can come in." : "Customers can browse, but checkout is unavailable."} /></div></Panel>

                    <Panel title="Restaurant profile" description="These details appear throughout the consumer app."><div className="grid gap-5 p-6 sm:grid-cols-2 sm:p-7"><Field label="Restaurant name" required className="sm:col-span-2"><Input value={name} onChange={(event) => setName(event.target.value)} /></Field><Field label="Description" className="sm:col-span-2"><textarea className="min-h-28 w-full rounded-xl border border-transparent bg-neutral-100 px-4 py-3 text-sm outline-none focus:border-neutral-900 focus:ring-2 focus:ring-neutral-900/10" value={description} onChange={(event) => setDescription(event.target.value)} /></Field><Field label="Logo" hint="Square images work best."><ImageUpload value={imageUrl} onChange={setImageUrl} placeholder="Upload logo" /></Field><Field label="Storefront banner" hint="Use a wide image that represents your food."><ImageUpload value={bannerUrl} onChange={setBannerUrl} placeholder="Upload banner" /></Field></div></Panel>

                    <Panel title="Hours and pickup location" description="Drivers and customers rely on this information for accurate delivery estimates."><div className="grid gap-5 p-6 sm:grid-cols-2 sm:p-7"><Field label="Opening time"><Input type="time" value={openTime} onChange={(event) => setOpenTime(event.target.value)} /></Field><Field label="Closing time"><Input type="time" value={closeTime} onChange={(event) => setCloseTime(event.target.value)} /></Field><Field label="Latitude"><Input type="number" step="0.000001" value={lat} onChange={(event) => setLat(event.target.value)} /></Field><Field label="Longitude"><Input type="number" step="0.000001" value={lng} onChange={(event) => setLng(event.target.value)} /></Field>{IS_DEV && <div className="flex flex-wrap gap-3 rounded-2xl bg-amber-50 p-4 sm:col-span-2"><Button variant="secondary" size="sm" onClick={handleResetLocation} isLoading={isResettingLocation}>Reset emulator location</Button><Button variant="secondary" size="sm" onClick={handleSetTestLocation} isLoading={isSettingTestLocation} disabled={!restaurant}>Set 4 km test location</Button></div>}</div></Panel>
                </div>

                <aside className="space-y-6 xl:sticky xl:top-6">
                    <StorePreview name={name} description={description} imageUrl={imageUrl} bannerUrl={bannerUrl} isOpen={isOpen} hours={`${openTime}–${closeTime}`} />
                    <Panel title="Partner account"><div className="space-y-4 p-6"><InfoRow icon={Building2} label="Account" value={profile?.full_name || "Merchant"} /><InfoRow icon={ShieldCheck} label="Role" value={profile?.role || "merchant"} /><InfoRow icon={ExternalLink} label="Contact" value={profile?.email || profile?.phone || "Not set"} /><Button variant="danger" className="mt-2 w-full" onClick={handleSignOut}><LogOut className="mr-2 h-4 w-4" />Sign out</Button></div></Panel>
                </aside>
            </div>
        </PageShell>
    );
}

function StorePreview({ name, description, imageUrl, bannerUrl, isOpen, hours }: { name: string; description: string; imageUrl: string; bannerUrl: string; isOpen: boolean; hours: string }) {
    return <Panel title="Customer preview" action={<StatusBadge active={isOpen} activeLabel="Open" inactiveLabel="Closed" />}><div className="p-4"><div className="relative h-36 overflow-hidden rounded-2xl bg-neutral-900">{bannerUrl ? <img src={bannerUrl} alt="Restaurant banner" className="h-full w-full object-cover" /> : <div className="absolute inset-0 bg-[radial-gradient(circle_at_top_right,#d7f654,transparent_45%)]" />}<div className="absolute inset-x-0 bottom-0 h-20 bg-gradient-to-t from-black/65 to-transparent" /><div className="absolute bottom-3 left-3 flex items-end gap-3">{imageUrl ? <img src={imageUrl} alt="Restaurant logo" className="h-12 w-12 rounded-xl border-2 border-white object-cover" /> : <span className="flex h-12 w-12 items-center justify-center rounded-xl border-2 border-white bg-white text-neutral-900"><Store className="h-5 w-5" /></span>}<div className="pb-0.5 text-white"><p className="font-black">{name || "Your restaurant"}</p><p className="text-xs text-white/75">{hours}</p></div></div></div><p className="mt-4 line-clamp-3 text-sm leading-6 text-neutral-500">{description || "Add a short description to tell customers what makes your restaurant special."}</p><div className="mt-4 flex items-center gap-2 text-xs font-bold text-neutral-600"><MapPin className="h-4 w-4 text-primary" />Pickup location configured</div></div></Panel>;
}

function InfoRow({ icon: Icon, label, value }: { icon: typeof Clock3; label: string; value: string }) { return <div className="flex items-center gap-3"><span className="flex h-10 w-10 items-center justify-center rounded-xl bg-neutral-100 text-neutral-600"><Icon className="h-4 w-4" /></span><div className="min-w-0"><p className="text-xs text-neutral-400">{label}</p><p className="truncate text-sm font-bold capitalize text-neutral-900">{value}</p></div></div>; }
