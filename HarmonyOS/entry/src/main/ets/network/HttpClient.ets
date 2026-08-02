import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';

export interface HttpJsonResponse {
  code: number;
  body: string;
}

// GET returning the raw status and body without any status mapping. The
// caller supplies the exact header table to send: the spec engine builds it
// from the spec's header list (with ${apiKey} already interpolated), so the
// client no longer hard-codes Authorization/Accept and MiniMax's Content-Type
// header flows through like any other. See Contracts/README.md ("Request
// steps and status branches").
export async function getJsonWithStatus(
  url: string,
  headers: Record<string, string>
): Promise<HttpJsonResponse> {
  const request = http.createHttp();
  try {
    let response: http.HttpResponse;
    try {
      response = await request.request(url, {
        method: http.RequestMethod.GET,
        header: headers,
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
