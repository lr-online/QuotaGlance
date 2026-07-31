import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';

export interface HttpJsonResponse {
  code: number;
  body: string;
}

// Shared HTTP-status-to-error mapping used by Swift's ProviderHTTPStatus.validate.
export function throwForHttpStatus(code: number): void {
  if (code >= 200 && code < 300) {
    return;
  }
  if (code === 401 || code === 403) {
    throw new Error('invalidCredential');
  }
  if (code === 429) {
    throw new Error('rateLimited');
  }
  throw new Error(`httpStatus:${code}`);
}

// Authenticated GET returning the raw status and body without status mapping.
// Providers that react to specific statuses (e.g. BioMap Coding's 403/404/405
// fallback) use this directly; everyone else pairs it with throwForHttpStatus.
export async function getJsonWithStatus(url: string, apiKey: string): Promise<HttpJsonResponse> {
  const request = http.createHttp();
  try {
    let response: http.HttpResponse;
    try {
      response = await request.request(url, {
        method: http.RequestMethod.GET,
        header: {
          'Authorization': `Bearer ${apiKey}`,
          'Accept': 'application/json'
        },
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 10000,
        readTimeout: 10000
      });
    } catch (error) {
      const businessError = error as BusinessError;
      throw new Error(`network:${businessError.code}`);
    }
    const result: HttpJsonResponse = {
      code: response.responseCode,
      body: response.result as string
    };
    return result;
  } finally {
    request.destroy();
  }
}

// Shared authenticated GET for all usage providers: Bearer key + JSON accept,
// 10s timeouts, and the shared status mapping. Returns the body as a string.
export async function getJson(url: string, apiKey: string): Promise<string> {
  const response = await getJsonWithStatus(url, apiKey);
  throwForHttpStatus(response.code);
  return response.body;
}
