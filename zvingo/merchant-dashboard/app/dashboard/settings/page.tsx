"use client";

import { useState, useEffect } from 'react';
import { apiJson } from '@/lib/api';
import { useRouter } from 'next/navigation';
import { clearAuth } from '@/lib/api';
import ImageUpload from '@/components/ImageUpload';

// Emulator/test location helpers are dev-only scaffolding (they hardcode the
// Android emulator's Googleplex coordinates) and are hidden in production.
const IS_DEV = process.env.NODE_ENV === 'development';

export default function SettingsPage() {
    const [profile, setProfile] = useState<any>(null);
    const [restaurant, setRestaurant] = useState<any>(null);

    // Form States
    const [name, setName] = useState('');
    const [description, setDescription] = useState('');
    const [imageUrl, setImageUrl] = useState('');
    const [bannerUrl, setBannerUrl] = useState('');
    const [lat, setLat] = useState('');
    const [lng, setLng] = useState('');
    const [isSaving, setIsSaving] = useState(false);
    const [isResettingLocation, setIsResettingLocation] = useState(false);
    const [isSettingTestLocation, setIsSettingTestLocation] = useState(false);

    // Business Hours / Status (Local state for now)
    const [isOpen, setIsOpen] = useState(true);
    const [openTime, setOpenTime] = useState('08:00');
    const [closeTime, setCloseTime] = useState('22:00');

    const router = useRouter();

    useEffect(() => {
        loadData();
    }, []);

    async function loadData() {
        try {
            const me = await apiJson('/auth/me');
            setProfile(me);

            // Fetch Restaurant for this merchant
            const restaurants = await apiJson(`/catalog/restaurants?merchant_id=${me.id}`);
            if (restaurants && restaurants.length > 0) {
                const r = restaurants[0];
                // Ensure ID is accessible (Beanie/Mongo might return _id)
                if (!r.id && r._id) r.id = r._id;

                setRestaurant(r);
                setName(r.name);
                setDescription(r.description || '');
                setImageUrl(r.image_url || '');
                setBannerUrl(r.banner_url || '');
                setIsOpen(r.is_active || false);
                const coords = r.location?.coordinates;
                if (coords && coords.length === 2) {
                    setLng(String(coords[0]));
                    setLat(String(coords[1]));
                }
            }
        } catch (err) {
            console.error('Failed to load data:', err);
        }
    }

    const handleSaveRestaurant = async () => {
        if (!restaurant) return;
        const id = restaurant.id || restaurant._id;
        if (!id) {
            alert('Error: Restaurant ID missing');
            return;
        }

        setIsSaving(true);
        try {
            const updated = await apiJson(`/catalog/restaurants/${id}`, {
                method: 'PUT',
                body: JSON.stringify({
                    name,
                    description,
                    image_url: imageUrl,
                    banner_url: bannerUrl,
                    lat: lat ? Number(lat) : undefined,
                    lng: lng ? Number(lng) : undefined,
                })
            });
            setRestaurant(updated);
            alert('Restaurant settings saved!');
        } catch (err) {
            console.error('Failed to save:', err);
            alert('Failed to save settings.');
        } finally {
            setIsSaving(false);
        }
    };

    const handleResetLocation = async () => {
        if (!restaurant) return;
        setIsResettingLocation(true);
        try {
            await apiJson('/catalog/admin/reset-locations?force_all=true', {
                method: 'POST',
            });
            await loadData();
            alert('Restaurant locations reset to emulator default.');
        } catch (err) {
            console.error('Failed to reset locations:', err);
            alert('Failed to reset restaurant locations.');
        } finally {
            setIsResettingLocation(false);
        }
    };

    // Set location 4km from California emulator default (37.4219983, -122.084)
    // 4km ≈ 0.036 degrees latitude
    const handleSetTestLocation = async () => {
        if (!restaurant) return;
        const id = restaurant.id || restaurant._id;
        if (!id) {
            alert('Error: Restaurant ID missing');
            return;
        }

        setIsSettingTestLocation(true);
        try {
            // Emulator default: 37.4219983, -122.084 (Googleplex)
            // Set restaurant 4km north: 37.4219983 + 0.036 = 37.458
            const testLat = 37.458;
            const testLng = -122.084;

            const updated = await apiJson(`/catalog/restaurants/${id}`, {
                method: 'PUT',
                body: JSON.stringify({
                    lat: testLat,
                    lng: testLng,
                })
            });
            setRestaurant(updated);
            setLat(String(testLat));
            setLng(String(testLng));
            alert(`Restaurant location set to ${testLat}, ${testLng} (4km from emulator)`);
        } catch (err) {
            console.error('Failed to set test location:', err);
            alert('Failed to set test location.');
        } finally {
            setIsSettingTestLocation(false);
        }
    };

    const handleSignOut = () => {
        clearAuth();
        router.push('/login');
    };

    return (
        <div>
            <h2 className="text-2xl font-semibold text-gray-900 mb-6">Business Settings</h2>

            {/* Profile Info */}
            {profile && (
                <div className="bg-white shadow overflow-hidden sm:rounded-lg mb-6">
                    <div className="px-4 py-5 sm:p-6">
                        <h3 className="text-lg leading-6 font-medium text-gray-900">Account Info</h3>
                        <div className="mt-4 space-y-2">
                            <p className="text-sm text-gray-600"><span className="font-medium">Name:</span> {profile.full_name}</p>
                            <p className="text-sm text-gray-600"><span className="font-medium">Email:</span> {profile.email || 'Not set'}</p>
                            <p className="text-sm text-gray-600"><span className="font-medium">Role:</span> {profile.role}</p>
                        </div>
                    </div>
                </div>
            )}

            {/* Restaurant Details */}
            <div className="bg-white shadow overflow-hidden sm:rounded-lg mb-6">
                <div className="px-4 py-5 sm:p-6">
                    <h3 className="text-lg leading-6 font-medium text-gray-900 mb-4">Restaurant Details</h3>
                    <div className="space-y-4">
                        {/* Name */}
                        <div>
                            <label className="block text-sm font-medium text-gray-700">Restaurant Name</label>
                            <input
                                type="text"
                                className="mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-green-500 focus:border-green-500 sm:text-sm"
                                value={name}
                                onChange={(e) => setName(e.target.value)}
                            />
                        </div>

                        {/* Description */}
                        <div>
                            <label className="block text-sm font-medium text-gray-700">Description</label>
                            <textarea
                                className="mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-green-500 focus:border-green-500 sm:text-sm"
                                rows={3}
                                value={description}
                                onChange={(e) => setDescription(e.target.value)}
                            />
                        </div>

                        {/* Logo */}
                        <div>
                            <label className="block text-sm font-medium text-gray-700 mb-2">Logo</label>
                            <div className="w-32">
                                <ImageUpload value={imageUrl} onChange={setImageUrl} placeholder="Logo URL" />
                            </div>
                        </div>

                        {/* Banner */}
                        <div>
                            <label className="block text-sm font-medium text-gray-700 mb-2">Banner Image</label>
                            <div className="w-full max-w-md">
                                <ImageUpload value={bannerUrl} onChange={setBannerUrl} placeholder="Banner URL" />
                            </div>
                        </div>

                        {/* Location */}
                        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                            <div>
                                <label className="block text-sm font-medium text-gray-700">Latitude</label>
                                <input
                                    type="number"
                                    step="0.000001"
                                    className="mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-green-500 focus:border-green-500 sm:text-sm"
                                    value={lat}
                                    onChange={(e) => setLat(e.target.value)}
                                />
                            </div>
                            <div>
                                <label className="block text-sm font-medium text-gray-700">Longitude</label>
                                <input
                                    type="number"
                                    step="0.000001"
                                    className="mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-green-500 focus:border-green-500 sm:text-sm"
                                    value={lng}
                                    onChange={(e) => setLng(e.target.value)}
                                />
                            </div>
                        </div>

                        {IS_DEV && (
                            <div className="pt-2 flex flex-wrap gap-2">
                                <button
                                    onClick={handleResetLocation}
                                    disabled={isResettingLocation}
                                    className="bg-gray-100 text-gray-800 py-2 px-4 rounded-md hover:bg-gray-200 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-gray-400 disabled:opacity-50"
                                >
                                    {isResettingLocation ? 'Resetting...' : 'Reset Location To Emulator Default'}
                                </button>
                                <button
                                    onClick={handleSetTestLocation}
                                    disabled={isSettingTestLocation || !restaurant}
                                    className="bg-blue-100 text-blue-800 py-2 px-4 rounded-md hover:bg-blue-200 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-400 disabled:opacity-50"
                                >
                                    {isSettingTestLocation ? 'Setting...' : 'Set 4km from Emulator (Test)'}
                                </button>
                            </div>
                        )}

                        <div className="pt-2">
                            <button
                                onClick={handleSaveRestaurant}
                                disabled={isSaving || !restaurant}
                                className="bg-green-600 text-white py-2 px-4 rounded-md hover:bg-green-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500 disabled:opacity-50"
                            >
                                {isSaving ? 'Saving...' : 'Save Changes'}
                            </button>
                        </div>
                    </div>
                </div>
            </div>

            {/* Store Status (UI Only for now) */}
            <div className="bg-white shadow overflow-hidden sm:rounded-lg mb-6">
                <div className="px-4 py-5 sm:p-6">
                    <h3 className="text-lg leading-6 font-medium text-gray-900">Store Status</h3>
                    <div className="mt-2 max-w-xl text-sm text-gray-500">
                        <p>Toggle your store&apos;s availability.</p>
                    </div>
                    <div className="mt-5 flex items-center">
                        <button
                            type="button"
                            onClick={() => setIsOpen(!isOpen)}
                            className={`${isOpen ? 'bg-green-600' : 'bg-gray-200'} relative inline-flex flex-shrink-0 h-6 w-11 border-2 border-transparent rounded-full cursor-pointer transition-colors ease-in-out duration-200 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500`}
                            aria-pressed={isOpen}
                        >
                            <span className={`${isOpen ? 'translate-x-5' : 'translate-x-0'} pointer-events-none inline-block h-5 w-5 rounded-full bg-white shadow transform ring-0 transition ease-in-out duration-200`}></span>
                        </button>
                        <span className="ml-3 text-sm font-medium text-gray-900">
                            {isOpen ? 'Open for Business' : 'Currently Closed'}
                        </span>
                    </div>
                </div>

                <div className="border-t border-gray-200 px-4 py-5 sm:p-6">
                    <h3 className="text-lg leading-6 font-medium text-gray-900">Business Hours</h3>
                    <div className="mt-4 grid grid-cols-1 gap-y-6 gap-x-4 sm:grid-cols-6">
                        <div className="sm:col-span-3">
                            <label className="block text-sm font-medium text-gray-700">Open Time</label>
                            <input
                                type="time"
                                value={openTime}
                                onChange={(e) => setOpenTime(e.target.value)}
                                className="mt-1 focus:ring-green-500 focus:border-green-500 block w-full shadow-sm sm:text-sm border-gray-300 rounded-md"
                            />
                        </div>
                        <div className="sm:col-span-3">
                            <label className="block text-sm font-medium text-gray-700">Close Time</label>
                            <input
                                type="time"
                                value={closeTime}
                                onChange={(e) => setCloseTime(e.target.value)}
                                className="mt-1 focus:ring-green-500 focus:border-green-500 block w-full shadow-sm sm:text-sm border-gray-300 rounded-md"
                            />
                        </div>
                    </div>
                </div>
            </div>

            {/* Sign Out */}
            <div>
                <button
                    onClick={handleSignOut}
                    className="bg-red-50 text-red-700 py-2 px-4 rounded-md border border-red-200 hover:bg-red-100 text-sm font-medium"
                >
                    Sign Out
                </button>
            </div>
        </div>
    );
}
