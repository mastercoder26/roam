import { clerkMiddleware } from "@clerk/nextjs/server";

// The route-scoring API call happens client-side against the deployed
// Cloud Run backend, which verifies the Clerk session token itself. This
// middleware only needs to keep Clerk's session state available to every
// route; it does not gate any page, matching the iOS app (which lets you
// browse before signing in and only requires a session to analyze a route).
export default clerkMiddleware();

export const config = {
  matcher: [
    "/((?!_next|[^?]*\\.(?:html?|css|js(?!on)|jpe?g|webp|png|gif|svg|ttf|woff2?|ico|csv|docx?|xlsx?|zip|webmanifest)).*)",
    "/(api|trpc)(.*)",
  ],
};
