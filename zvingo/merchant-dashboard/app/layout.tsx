import type { Metadata, Viewport } from "next";
import { Inter } from "next/font/google";
import "./globals.css";

// §2 — Inter across all three surfaces. Variable weights 400–800 cover the
// whole type scale (body 400 → display 800) from a single download.
const inter = Inter({
  subsets: ["latin"],
  variable: "--font-inter",
  display: "swap",
  weight: ["400", "500", "600", "700", "800"],
  fallback: ["system-ui", "Segoe UI", "Roboto", "Helvetica Neue", "Arial"],
  adjustFontFallback: true,
});

export const metadata: Metadata = {
  title: {
    default: "Zvingo Partner",
    template: "%s · Zvingo Partner",
  },
  description:
    "Run your restaurant on Zvingo: accept orders, manage your menu, launch promotions and track sales.",
  applicationName: "Zvingo Partner",
  robots: { index: false, follow: false },
  icons: { icon: "/favicon.ico" },
  formatDetection: { telephone: false, address: false, email: false },
};

// Counter tablets and back-office laptops. Zoom stays enabled — never trap a
// user who needs 200% text (§7).
export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  minimumScale: 1,
  maximumScale: 5,
  userScalable: true,
  themeColor: "#101210",
  colorScheme: "light",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className={inter.variable} suppressHydrationWarning>
      <body className="min-h-screen bg-background font-sans text-body text-text-secondary antialiased">
        {children}
      </body>
    </html>
  );
}
