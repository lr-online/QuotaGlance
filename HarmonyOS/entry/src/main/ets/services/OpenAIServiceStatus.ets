import { getJsonWithStatus } from '../network/HttpClient';

export type ServiceStatusLevel = 'operational' | 'degraded' | 'outage' | 'unknown';
export interface OpenAIServiceStatus {
  available: boolean;
  source: string;
  overall?: ServiceStatusLevel;
  summary?: string;
  affectedComponents: string[];
  activeIncidents: string[];
}

const SUMMARY_URL: string = 'https://status.openai.com/api/v2/summary.json';

export async function fetchOpenAIServiceStatus(): Promise<OpenAIServiceStatus> {
  try {
    const response = await getJsonWithStatus(SUMMARY_URL, { 'Accept': 'application/json' });
    if (response.code < 200 || response.code >= 300) return unavailable();
    return parseOpenAIServiceStatus(response.body);
  } catch (_) { return unavailable(); }
}

export function parseOpenAIServiceStatus(body: string): OpenAIServiceStatus {
  try {
    const payload: Record<string, Object> = JSON.parse(body) as Record<string, Object>;
    const status = payload['status'] as Record<string, Object>;
    const summary = String(status?.['description'] ?? '').trim();
    if (summary.length === 0) return unavailable();
    const affectedComponents: string[] = [];
    const components = payload['components'] as Object[];
    if (Array.isArray(components)) components.forEach((item: Object) => {
      const component = item as Record<string, Object>;
      if (String(component['status'] ?? '') !== 'operational') affectedComponents.push(String(component['name'] ?? 'Unknown'));
    });
    const activeIncidents: string[] = [];
    const incidents = payload['incidents'] as Object[];
    if (Array.isArray(incidents)) incidents.forEach((item: Object) => {
      const incident = item as Record<string, Object>;
      if (String(incident['status'] ?? '') !== 'resolved') activeIncidents.push(String(incident['name'] ?? 'Incident'));
    });
    return { source: 'openAI', available: true, overall: overallLevel(String(status?.['indicator'] ?? '')), summary, affectedComponents, activeIncidents };
  } catch (_) { return unavailable(); }
}

function overallLevel(indicator: string): ServiceStatusLevel {
  if (indicator === 'none') return 'operational';
  if (indicator === 'minor') return 'degraded';
  if (indicator === 'major' || indicator === 'critical') return 'outage';
  return 'unknown';
}
function unavailable(): OpenAIServiceStatus { return { source: 'openAI', available: false, affectedComponents: [], activeIncidents: [] }; }
