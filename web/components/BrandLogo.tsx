import Image from "next/image";
import Link from "next/link";

export function BrandLogo({ compact = false }: { compact?: boolean }) {
  return (
    <Link
      href="/"
      aria-label="Roam home"
      className="roam-jiggle inline-flex shrink-0 items-center rounded-lg focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent focus-visible:ring-offset-4"
    >
      <Image
        src="/brand/roam-wordmark.png"
        alt="Roam"
        width={224}
        height={80}
        priority
        className={compact ? "h-[30px] w-auto" : "h-9 w-auto"}
      />
    </Link>
  );
}
