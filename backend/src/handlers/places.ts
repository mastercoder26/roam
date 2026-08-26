import type { Request, Response } from "express";
import { z } from "zod";
import { autocompleteAddresses } from "../google/places.js";

const querySchema = z.string().trim().min(3).max(120);

export async function handleAddressAutocomplete(req: Request, res: Response): Promise<void> {
  const parsed = querySchema.safeParse(req.query.input);
  if (!parsed.success) {
    res.status(400).json({
      error: "Enter at least 3 characters to search for an address.",
      code: "INVALID_REQUEST",
    });
    return;
  }

  const apiKey = process.env.GOOGLE_MAPS_API_KEY;
  if (!apiKey) {
    res.status(503).json({
      error: "Address suggestions are temporarily unavailable.",
      code: "SERVICE_UNAVAILABLE",
    });
    return;
  }

  try {
    const suggestions = await autocompleteAddresses(parsed.data, apiKey);
    res.setHeader("Cache-Control", "private, max-age=60");
    res.status(200).json({ suggestions });
  } catch (error) {
    console.error(JSON.stringify({
      event: "address_autocomplete_failed",
      errorClass: error instanceof Error ? error.name : "UnknownError",
    }));
    res.status(503).json({
      error: "Address suggestions are temporarily unavailable.",
      code: "SERVICE_UNAVAILABLE",
    });
  }
}
