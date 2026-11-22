import { Card } from "@/components/ui/Card";

export const metadata = {
  title: "Privacy Policy | Roam",
  description: "What Roam collects, what stays on your iPhone, and how to delete your data.",
};

const EFFECTIVE_DATE = "November 22, 2026";
const CONTACT_EMAIL = "akhilkonduru23@gmail.com";

const sections: Array<{ title: string; paragraphs?: string[]; items?: string[] }> = [
  {
    title: "The short version",
    paragraphs: [
      "Roam is a driving coach for new drivers. It scores a planned route and, when you choose to record a practice drive, scores that drive on your iPhone. Roam has no ads, does not track you across other apps or websites, and does not sell personal information.",
    ],
  },
  {
    title: "What stays on your iPhone",
    items: [
      "The GPS trace of each recorded drive, including where driving events happened.",
      "Raw motion-sensor readings. They are used while a drive is recording and are not saved.",
      "Your recent routes, appearance settings, and local driver profile when you are not signed in.",
    ],
  },
  {
    title: "What Roam sends to its servers",
    items: [
      "Route requests: the start and destination you enter (an address or, if you choose your current location, its coordinates) and the departure time. They are used to compute that route's difficulty and are not stored in your account.",
      "Account details, if you create an account: your email address, name, and a user ID.",
      "Driver profile, if you are signed in: display name, license stage, and practice preferences.",
      "Drive summaries, if you are signed in: start time, duration, distance, top speed, score, the type and time of driving events, and data-quality and practice-coverage figures. Map coordinates and the GPS trace are removed before upload.",
    ],
  },
  {
    title: "Services Roam relies on",
    paragraphs: [
      "Roam shares only what each service needs to do its job:",
    ],
    items: [
      "Clerk provides sign-in and stores your account credentials.",
      "Google Maps Platform receives route endpoints and route geometry to return directions, traffic, speed limits, and address suggestions.",
      "Open-Meteo receives points along a route to return a weather forecast.",
      "OpenStreetMap's Overpass API receives the area around a route to return road details.",
      "Google Cloud and Render host Roam's servers and database.",
    ],
  },
  {
    title: "Permissions",
    items: [
      "Location: used to fill in your starting point and, during a drive you start yourself, to measure distance, speed changes, and turns. \"Always\" access is only needed to keep recording with the screen locked.",
      "Motion: used during a recorded drive to detect driving events and check how the phone is mounted.",
    ],
  },
  {
    title: "Keeping and deleting data",
    paragraphs: [
      "You can delete any recorded drive in the app. Deleting your account from Profile removes your account, driver profile, and backed-up drive summaries from Roam's servers. Data stored only on your iPhone is removed when you delete the app.",
      "Roam can be used without an account. Route analysis and on-device drive recording work the same way; signing in only adds backup.",
    ],
  },
  {
    title: "Younger drivers",
    paragraphs: [
      "Roam is intended for people old enough to hold a learner's permit and for the adults supervising them. It is not directed to children under 13, and Roam does not knowingly collect personal information from them.",
    ],
  },
  {
    title: "Changes and contact",
    paragraphs: [
      "If this policy changes, the new version will be posted here with a new effective date.",
    ],
  },
];

export default function PrivacyPage() {
  return (
    <div className="roam-reveal mx-auto flex max-w-3xl flex-col gap-8">
      <header className="border-b border-card pb-8">
        <p className="mb-3 text-[10px] font-semibold uppercase tracking-[0.14em] text-accent">
          Effective {EFFECTIVE_DATE}
        </p>
        <h1 className="text-[clamp(2.25rem,5vw,3.5rem)] font-semibold leading-[1] tracking-[-0.04em] text-ink-primary">
          Privacy Policy
        </h1>
      </header>

      {sections.map((section) => (
        <section key={section.title} className="flex flex-col gap-3">
          <h2 className="text-xl font-semibold tracking-[-0.025em] text-ink-primary">{section.title}</h2>
          {section.paragraphs?.map((paragraph) => (
            <p key={paragraph} className="text-[15px] leading-7 text-ink-secondary">{paragraph}</p>
          ))}
          {section.items ? (
            <ul className="flex list-disc flex-col gap-2 pl-5 text-[15px] leading-7 text-ink-secondary">
              {section.items.map((item) => (
                <li key={item}>{item}</li>
              ))}
            </ul>
          ) : null}
        </section>
      ))}

      <Card>
        <p className="text-[14px] leading-6 text-ink-secondary">
          Questions or deletion requests:{" "}
          <a className="font-semibold text-accent underline-offset-4 hover:underline" href={`mailto:${CONTACT_EMAIL}`}>
            {CONTACT_EMAIL}
          </a>
        </p>
      </Card>
    </div>
  );
}
