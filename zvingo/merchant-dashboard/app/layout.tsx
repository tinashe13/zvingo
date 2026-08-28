import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Zvingo Merchant Dashboard",
  description: "Manage your restaurant and orders",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body className="font-sans antialiased text-neutral-600 bg-neutral-50">
        {children}
      </body>
    </html>
  );
}
