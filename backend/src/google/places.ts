import { z } from "zod";

const PLACES_AUTOCOMPLETE_URL = "https://places.googleapis.com/v1/places:autocomplete";
const FETCH_TIMEOUT_MS = 5_000;

const autocompleteResponse = z.object({
  suggestions: z.array(z.object({
    placePrediction: z.object({
      placeId: z.string().min(1),
      text: z.object({ text: z.string().min(1) }),
    }).optional(),
  })).optional(),
});

export interface AddressSuggestion {
  placeId: string;
  label: string;
}

export async function autocompleteAddresses(
  input: string,
  apiKey: string,
): Promise<AddressSuggestion[]> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);

  try {
    const response = await fetch(PLACES_AUTOCOMPLETE_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": apiKey,
      },
      body: JSON.stringify({ input, includeQueryPredictions: false }),
      signal: controller.signal,
    });

    if (!response.ok) {
      throw new Error(`Places autocomplete failed with HTTP ${response.status}`);
    }

    const parsed = autocompleteResponse.safeParse(await response.json());
    if (!parsed.success) {
      throw new Error("Places autocomplete returned invalid data");
    }

    return (parsed.data.suggestions ?? [])
      .flatMap((suggestion) => suggestion.placePrediction ? [{
        placeId: suggestion.placePrediction.placeId,
        label: suggestion.placePrediction.text.text,
      }] : [])
      .slice(0, 5);
  } finally {
    clearTimeout(timer);
  }
}
