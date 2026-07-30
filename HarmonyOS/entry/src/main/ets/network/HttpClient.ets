import { http } from '@kit.NetworkKit';

export const DEEPSEEK_BALANCE_ENDPOINT = 'https://api.deepseek.com/user/balance';

export async function fetchBalance(apiKey: string): Promise<string> {
  const request = http.createHttp();
  try {
    const response = await request.request(DEEPSEEK_BALANCE_ENDPOINT, {
      method: http.RequestMethod.GET,
      header: {
        'Authorization': `Bearer ${apiKey}`,
        'Accept': 'application/json'
      },
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 10000,
      readTimeout: 10000
    });
    const code = response.responseCode;
    if (code === 401 || code === 403) {
      throw new Error('invalidCredential');
    }
    if (code === 429) {
      throw new Error('rateLimited');
    }
    if (code < 200 || code >= 300) {
      throw new Error(`httpStatus:${code}`);
    }
    return response.result as string;
  } finally {
    request.destroy();
  }
}
