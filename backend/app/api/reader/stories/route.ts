import { fetchStoryIds } from '../../../../lib/hacker-news.js';
import { errorResponse, json, safeErrorStatus } from '../../../../lib/http.js';

export async function GET(request: Request): Promise<Response> {
  const type = new URL(request.url).searchParams.get('type');
  if (type !== 'top' && type !== 'latest') return errorResponse('invalid_request', 400);
  try {
    return json(await fetchStoryIds(type));
  } catch (error) {
    const message = error instanceof Error ? error.message : 'internal_error';
    return errorResponse(message, safeErrorStatus(message));
  }
}
