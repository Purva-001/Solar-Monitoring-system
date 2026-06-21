import axios from 'axios';

/** Latest snapshot for I–V / P–V (proxies AWS_API_ENDPOINT). Accepts JSON object or array. */
export const fetchSolarIvPvSnapshot = async ({ timeoutMs = 10000 } = {}) => {
  try {
    const res = await axios.get('/api/solar-iv-pv', { timeout: timeoutMs });
    const data = res?.data;
    if (data == null) return null;
    return data;
  } catch (err) {
    const status = err?.response?.status;
    const data = err?.response?.data;
    const msg =
      (typeof data === 'string' ? data : null) ||
      data?.detail ||
      data?.message ||
      data?.error ||
      err?.message ||
      'Failed to fetch solar I–V / P–V snapshot';

    if (status) {
      throw new Error(`Solar snapshot request failed (${status}): ${msg}`);
    }

    throw new Error(msg);
  }
};

export const fetchSolarHistory = async ({ assetId, timeoutMs = 10000 } = {}) => {
  if (!assetId) throw new Error('assetId is required');

  try {
    const res = await axios.get('/api/solar-history', {
      params: { assetId },
      timeout: timeoutMs
    });

    const data = res?.data;
    if (!Array.isArray(data)) {
      throw new Error('Unexpected API response: expected an array');
    }

    return data;
  } catch (err) {
    const status = err?.response?.status;
    const data = err?.response?.data;
    const msg =
      (typeof data === 'string' ? data : null) ||
      data?.detail ||
      data?.message ||
      err?.message ||
      'Failed to fetch solar history';

    if (status) {
      throw new Error(`Solar history request failed (${status}): ${msg}`);
    }

    throw new Error(msg);
  }
};
