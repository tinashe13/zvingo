"use client";

import { useState, useEffect } from 'react';
import { apiJson } from '@/lib/api';
import ImageUpload from '@/components/ImageUpload';
import MultiImageUpload from '@/components/MultiImageUpload';

// Default coordinates used when a merchant first creates their restaurant
// (Harare CBD, Zimbabwe). Merchants can adjust the exact location afterwards
// in Settings. Overridable at build time via env for other deployments.
const DEFAULT_RESTAURANT_LAT = Number(process.env.NEXT_PUBLIC_DEFAULT_RESTAURANT_LAT || '-17.82');
const DEFAULT_RESTAURANT_LNG = Number(process.env.NEXT_PUBLIC_DEFAULT_RESTAURANT_LNG || '31.05');

type MenuItem = {
    id: string;
    name: string;
    price_usd: number;
    is_available: boolean;
    category: string;
    description?: string;
    image_url?: string;
    images?: string[];
};

export default function MenuPage() {
    const [items, setItems] = useState<MenuItem[]>([]);
    const [loading, setLoading] = useState(true);
    const [restaurant, setRestaurant] = useState<any>(null);
    const [merchantId, setMerchantId] = useState<string | null>(null);

    // Add form state
    const [showAddForm, setShowAddForm] = useState(false);
    const [newName, setNewName] = useState('');
    const [newPrice, setNewPrice] = useState('');
    const [newCategory, setNewCategory] = useState('');
    const [newDescription, setNewDescription] = useState('');
    const [newImages, setNewImages] = useState<string[]>([]);

    // Edit form state
    const [editingItem, setEditingItem] = useState<MenuItem | null>(null);
    const [editName, setEditName] = useState('');
    const [editPrice, setEditPrice] = useState('');
    const [editCategory, setEditCategory] = useState('');
    const [editDescription, setEditDescription] = useState('');
    const [editImages, setEditImages] = useState<string[]>([]);

    // New Restaurant form state
    const [restName, setRestName] = useState('');
    const [restDesc, setRestDesc] = useState('');
    const [restImageUrl, setRestImageUrl] = useState('');

    useEffect(() => {
        async function init() {
            try {
                const me = await apiJson('/auth/me');
                setMerchantId(me.id);

                const restaurants = await apiJson(`/catalog/restaurants?merchant_id=${me.id}`);
                if (restaurants.length > 0) {
                    setRestaurant(restaurants[0]);
                    setItems(restaurants[0].menu || []);
                }
            } catch (err) {
                console.error('Failed to load data:', err);
            } finally {
                setLoading(false);
            }
        }
        init();
    }, []);

    const createRestaurant = async () => {
        if (!restName) return;
        try {
            setLoading(true);
            const newRest = await apiJson('/catalog/restaurants', {
                method: 'POST',
                body: JSON.stringify({
                    name: restName,
                    description: restDesc,
                    lat: DEFAULT_RESTAURANT_LAT,
                    lng: DEFAULT_RESTAURANT_LNG,
                    categories: ["General"],
                    delivery_time_min: 30,
                    delivery_time_max: 45,
                    delivery_fee_usd: 2.00,
                    image_url: restImageUrl,
                })
            });
            setRestaurant(newRest);
            setItems([]);
        } catch (err) {
            console.error('Failed to create restaurant:', err);
            alert('Failed to create restaurant');
        } finally {
            setLoading(false);
        }
    };

    const toggleAvailability = async (itemId: string, currentStatus: boolean) => {
        if (!restaurant) return;

        // Optimistic update
        const originalItems = [...items];
        setItems(items.map(i => i.id === itemId ? { ...i, is_available: !currentStatus } : i));

        try {
            await apiJson(`/catalog/restaurants/${restaurant._id || restaurant.id}/menu/${itemId}`, {
                method: 'PUT',
                body: JSON.stringify({
                    is_available: !currentStatus
                })
            });
        } catch (err) {
            console.error("Failed to toggle:", err);
            setItems(originalItems); // Revert
            alert("Failed to update item availability");
        }
    };

    const handleAddItem = async () => {
        if (!newName || !newPrice || !newCategory || !restaurant) return;

        try {
            const updatedRestaurant = await apiJson(`/catalog/restaurants/${restaurant._id || restaurant.id}/menu`, {
                method: 'POST',
                body: JSON.stringify({
                    name: newName,
                    price_usd: parseFloat(newPrice),
                    category: newCategory,
                    description: newDescription,
                    image_url: newImages.length > 0 ? newImages[0] : null,
                    images: newImages,
                })
            });

            setItems(updatedRestaurant.menu || []);
            setNewName('');
            setNewPrice('');
            setNewCategory('');
            setNewDescription('');
            setNewImages([]);
            setShowAddForm(false);
        } catch (err) {
            console.error('Failed to add item:', err);
            alert('Failed to add item');
        }
    };

    const startEdit = (item: MenuItem) => {
        setEditingItem(item);
        setEditName(item.name);
        setEditPrice(item.price_usd.toString());
        setEditCategory(item.category);
        setEditDescription(item.description || '');
        setEditImages(item.images || (item.image_url ? [item.image_url] : []));
    };

    const handleDeleteItem = async (itemId: string, itemName: string) => {
        if (!restaurant) return;
        if (!confirm(`Delete "${itemName}" from the menu?`)) return;

        const originalItems = [...items];
        setItems(items.filter(i => i.id !== itemId));

        try {
            await apiJson(`/catalog/restaurants/${restaurant._id || restaurant.id}/menu/${itemId}`, {
                method: 'DELETE',
            });
        } catch (err) {
            console.error('Failed to delete item:', err);
            setItems(originalItems);
            alert('Failed to delete item');
        }
    };

    const handleUpdateItem = async () => {
        if (!editingItem || !restaurant) return;

        try {
            const updatedRestaurant = await apiJson(`/catalog/restaurants/${restaurant._id || restaurant.id}/menu/${editingItem.id}`, {
                method: 'PUT',
                body: JSON.stringify({
                    name: editName,
                    price_usd: parseFloat(editPrice),
                    category: editCategory,
                    description: editDescription,
                    image_url: editImages.length > 0 ? editImages[0] : null,
                    images: editImages,
                })
            });

            setItems(updatedRestaurant.menu || []);
            setEditingItem(null);
        } catch (err) {
            console.error('Failed to update item:', err);
            alert('Failed to update item');
        }
    };

    if (loading) {
        return (
            <div className="flex justify-center items-center h-64">
                <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-green-600"></div>
            </div>
        );
    }

    if (!restaurant) {
        return (
            <div className="max-w-md mx-auto mt-10 p-6 bg-white rounded-lg shadow">
                <h2 className="text-xl font-bold mb-4">Set up your Restaurant</h2>
                <div className="space-y-4">
                    <div>
                        <label className="block text-sm font-medium text-gray-700">Restaurant Name</label>
                        <input type="text" className="mt-1 block w-full border border-gray-300 rounded p-2" value={restName} onChange={e => setRestName(e.target.value)} />
                    </div>
                    <div>
                        <label className="block text-sm font-medium text-gray-700">Description</label>
                        <input type="text" className="mt-1 block w-full border border-gray-300 rounded p-2" value={restDesc} onChange={e => setRestDesc(e.target.value)} />
                    </div>
                    <div>
                        <label className="block text-sm font-medium text-gray-700">Logo</label>
                        <ImageUpload value={restImageUrl} onChange={setRestImageUrl} placeholder="Upload logo" />
                    </div>
                    <button onClick={createRestaurant} className="w-full bg-green-600 text-white p-2 rounded hover:bg-green-700">Create Restaurant</button>
                </div>
            </div>
        );
    }

    return (
        <div>
            <div className="flex justify-between items-center mb-6">
                <div>
                    <h2 className="text-2xl font-semibold text-gray-900">Menu Management</h2>
                    <p className="text-sm text-gray-500">{restaurant.name}</p>
                </div>
                <button onClick={() => setShowAddForm(!showAddForm)} className="bg-green-600 text-white py-2 px-4 rounded hover:bg-green-700">
                    {showAddForm ? 'Cancel' : '+ Add Item'}
                </button>
            </div>

            {/* Add Item Form */}
            {showAddForm && (
                <div className="bg-white shadow rounded-lg p-6 mb-6">
                    <h3 className="text-lg font-medium text-gray-900 mb-4">Add Menu Item</h3>
                    <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                        <div>
                            <label className="block text-sm font-medium text-gray-700 mb-1">Name *</label>
                            <input type="text" value={newName} onChange={(e) => setNewName(e.target.value)} className="w-full px-3 py-2 border border-gray-300 rounded-md" />
                        </div>
                        <div>
                            <label className="block text-sm font-medium text-gray-700 mb-1">Price (USD) *</label>
                            <input type="number" step="0.01" value={newPrice} onChange={(e) => setNewPrice(e.target.value)} className="w-full px-3 py-2 border border-gray-300 rounded-md" />
                        </div>
                        <div>
                            <label className="block text-sm font-medium text-gray-700 mb-1">Category *</label>
                            <input type="text" value={newCategory} onChange={(e) => setNewCategory(e.target.value)} className="w-full px-3 py-2 border border-gray-300 rounded-md" />
                        </div>
                        <div>
                            <label className="block text-sm font-medium text-gray-700 mb-1">Description</label>
                            <input type="text" value={newDescription} onChange={(e) => setNewDescription(e.target.value)} className="w-full px-3 py-2 border border-gray-300 rounded-md" />
                        </div>
                        <div className="sm:col-span-2">
                            <label className="block text-sm font-medium text-gray-700 mb-1">Item Images</label>
                            <MultiImageUpload values={newImages} onChange={setNewImages} />
                        </div>
                    </div>
                    <div className="mt-4">
                        <button onClick={handleAddItem} className="bg-green-600 text-white py-2 px-6 rounded hover:bg-green-700">Add to Menu</button>
                    </div>
                </div>
            )}

            {/* Edit Item Modal */}
            {editingItem && (
                <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center p-4 z-50">
                    <div className="bg-white rounded-lg shadow-xl max-w-2xl w-full p-6 max-h-[90vh] overflow-y-auto">
                        <div className="flex justify-between items-center mb-4">
                            <h3 className="text-lg font-bold">Edit Item</h3>
                            <button onClick={() => setEditingItem(null)} className="text-gray-500 hover:text-gray-700">✕</button>
                        </div>
                        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                            <div>
                                <label className="block text-sm font-medium text-gray-700 mb-1">Name *</label>
                                <input type="text" value={editName} onChange={(e) => setEditName(e.target.value)} className="w-full px-3 py-2 border border-gray-300 rounded-md" />
                            </div>
                            <div>
                                <label className="block text-sm font-medium text-gray-700 mb-1">Price (USD) *</label>
                                <input type="number" step="0.01" value={editPrice} onChange={(e) => setEditPrice(e.target.value)} className="w-full px-3 py-2 border border-gray-300 rounded-md" />
                            </div>
                            <div>
                                <label className="block text-sm font-medium text-gray-700 mb-1">Category *</label>
                                <input type="text" value={editCategory} onChange={(e) => setEditCategory(e.target.value)} className="w-full px-3 py-2 border border-gray-300 rounded-md" />
                            </div>
                            <div>
                                <label className="block text-sm font-medium text-gray-700 mb-1">Description</label>
                                <input type="text" value={editDescription} onChange={(e) => setEditDescription(e.target.value)} className="w-full px-3 py-2 border border-gray-300 rounded-md" />
                            </div>
                            <div className="sm:col-span-2">
                                <label className="block text-sm font-medium text-gray-700 mb-1">Item Images</label>
                                <MultiImageUpload values={editImages} onChange={setEditImages} />
                            </div>
                        </div>
                        <div className="mt-6 flex justify-end space-x-3">
                            <button onClick={() => setEditingItem(null)} className="px-4 py-2 border rounded text-gray-600 hover:bg-gray-50">Cancel</button>
                            <button onClick={handleUpdateItem} className="px-4 py-2 bg-green-600 text-white rounded hover:bg-green-700">Save Changes</button>
                        </div>
                    </div>
                </div>
            )}

            {/* Menu List */}
            <div className="bg-white shadow overflow-hidden sm:rounded-md mt-6">
                <ul className="divide-y divide-gray-200">
                    {items.map((item) => (
                        <li key={item.id} className="px-4 py-4 sm:px-6 flex items-center justify-between">
                            <div className="flex items-center">
                                <div className="h-16 w-16 rounded bg-gray-100 flex-shrink-0 mr-4 overflow-hidden border">
                                    {item.image_url ? (
                                        <img src={item.image_url} alt={item.name} className="h-full w-full object-cover" />
                                    ) : (
                                        <div className="h-full w-full flex items-center justify-center text-gray-400">
                                            <svg className="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" /></svg>
                                        </div>
                                    )}
                                </div>
                                <div>
                                    <p className="text-sm font-medium text-gray-900">{item.name}</p>
                                    <p className="text-sm text-gray-500">${item.price_usd.toFixed(2)} • {item.category}</p>
                                    {item.images && item.images.length > 1 && (
                                        <span className="text-xs text-blue-600 bg-blue-50 px-2 py-0.5 rounded-full">+{item.images.length - 1} more images</span>
                                    )}
                                </div>
                            </div>
                            <div className="flex items-center space-x-4">
                                {/* Toggle Switch */}
                                <div className="flex items-center">
                                    <span className={`mr-2 text-xs font-semibold ${item.is_available ? 'text-green-700' : 'text-gray-500'}`}>
                                        {item.is_available ? 'Active' : 'Hidden'}
                                    </span>
                                    <button
                                        onClick={() => toggleAvailability(item.id, item.is_available)}
                                        className={`relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-green-500 focus:ring-offset-2 ${item.is_available ? 'bg-green-600' : 'bg-gray-200'}`}
                                        role="switch"
                                        aria-checked={item.is_available}
                                    >
                                        <span aria-hidden="true" className={`pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out ${item.is_available ? 'translate-x-5' : 'translate-x-0'}`} />
                                    </button>
                                </div>

                                <button
                                    onClick={() => startEdit(item)}
                                    className="text-gray-400 hover:text-gray-500"
                                    title="Edit"
                                >
                                    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor" className="w-5 h-5">
                                        <path strokeLinecap="round" strokeLinejoin="round" d="M16.862 4.487l1.687-1.688a1.875 1.875 0 112.652 2.652L10.582 16.07a4.5 4.5 0 01-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 011.13-1.897l8.932-8.931zm0 0L19.5 7.125M18 14v4.75A2.25 2.25 0 0115.75 21H5.25A2.25 2.25 0 013 18.75V8.25A2.25 2.25 0 015.25 6H10" />
                                    </svg>
                                </button>

                                <button
                                    onClick={() => handleDeleteItem(item.id, item.name)}
                                    className="text-gray-400 hover:text-red-500"
                                    title="Delete"
                                >
                                    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor" className="w-5 h-5">
                                        <path strokeLinecap="round" strokeLinejoin="round" d="M14.74 9l-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 01-2.244 2.077H8.084a2.25 2.25 0 01-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 00-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 013.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 00-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 00-7.5 0" />
                                    </svg>
                                </button>
                            </div>
                        </li>
                    ))}
                </ul>
            </div>
        </div>
    );
}
