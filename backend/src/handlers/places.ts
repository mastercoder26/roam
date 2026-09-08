import type { Request, Response } from "express";
import { z } from "zod";
import { autocompleteAddresses } from "../google/places.js";
import { createRequestId, logInternalFailure } from "../errors.js";

const querySchema = z.string().trim().min(3).max(120);

export async function handleAddressAutocomplete(req: Request, res: Response): Promise<void> {
  const requestId = createRequestId();
  const parsed = querySchema.safeParse(req.query.input);
  if (!parsed.success) {
    res.status(400).json({
      error: "Enter at least 3 characters to search for an address.",
      code: "INVALID_REQUEST",
      requestId,
    });
    return;
  }

  const apiKey = process.env.GOOGLE_MAPS_API_KEY;
  if (!apiKey) {
    logInternalFailure(requestId, { endpoint: "places-autocomplete" }, new Error("GOOGLE_MAPS_API_KEY is not configured"));
    res.status(503).json({
      error: "Address suggestions are temporarily unavailable.",
      code: "SERVICE_UNAVAILABLE",
      requestId,
    });
    return;
  }

  try {
    const suggestions = await autocompleteAddresses(parsed.data, apiKey);
    res.setHeader("Cache-Control", "private, max-age=60");
    res.status(200).json({ suggestions });
  } catch (error) {
    logInternalFailure(requestId, { endpoint: "places-autocomplete" }, error);
    res.status(503).json({
      error: "Address suggestions are temporarily unavailable.",
      code: "SERVICE_UNAVAILABLE",
      requestId,
    });
  }
}
