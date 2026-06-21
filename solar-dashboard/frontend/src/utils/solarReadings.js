import { absNumber } from './numbers';

/**
 * Live AWS payloads often return a single snapshot as [{ ... }].
 * Dashboard code expects a flat object with V1, I1, etc.
 */
export const unwrapPanelReadingsPayload = (data) => {
  if (data == null) return null;
  if (Array.isArray(data)) {
    for (let i = data.length - 1; i >= 0; i -= 1) {
      const row = data[i];
      if (row && typeof row === 'object' && !Array.isArray(row) && !row.error) return row;
    }
    return null;
  }
  if (typeof data === 'object') {
    const inner = data.data;
    if (Array.isArray(inner)) {
      for (let i = inner.length - 1; i >= 0; i -= 1) {
        const row = inner[i];
        if (row && typeof row === 'object' && !Array.isArray(row)) return row;
      }
    }
    return data;
  }
  return null;
};

/** Values > 50 are treated as milliamps (matches string-sensor payloads). */
export const sensorCurrentToAmps = (value) => {
  const n = absNumber(value);
  if (!Number.isFinite(n)) return 0;
  return Math.abs(n) > 50 ? n / 1000 : n;
};

export const pickReadingScalar = (obj, key) => {
  if (obj == null) return null;
  const raw = obj[key];
  if (raw != null && typeof raw === 'object' && 'value' in raw) return raw.value;
  return raw;
};

/** Total DC power (W) from V1–V4 / I1–I4 / optional P1–P4. */
export const totalPowerFromChannelsW = (row) => {
  if (!row || typeof row !== 'object') return 0;
  let sum = 0;
  for (let i = 1; i <= 4; i += 1) {
    const p = pickReadingScalar(row, `P${i}`);
    if (p != null && Number.isFinite(absNumber(p))) {
      sum += absNumber(p);
      continue;
    }
    const v = absNumber(pickReadingScalar(row, `V${i}`));
    const ia = sensorCurrentToAmps(pickReadingScalar(row, `I${i}`));
    sum += v * ia;
  }
  return sum;
};

/** Total current (A): explicit I, else sum of branch currents I1–I4. */
export const totalCurrentFromChannelsA = (row) => {
  if (!row || typeof row !== 'object') return 0;
  const direct = pickReadingScalar(row, 'I');
  if (direct != null && Number.isFinite(absNumber(direct))) {
    return sensorCurrentToAmps(direct);
  }
  let s = 0;
  for (let i = 1; i <= 4; i += 1) {
    const ik = pickReadingScalar(row, `I${i}`);
    if (ik != null && Number.isFinite(absNumber(ik))) s += sensorCurrentToAmps(ik);
  }
  return s;
};

/** Grid panel id → 1-based channel index (Vn / In / Pn) in flat AWS payloads. */
export const PANEL_ID_TO_READINGS_CHANNEL = {
  'PL01-B02-INV03-STR05-P01': 1,
  'PL01-B02-INV03-STR05-P02': 2,
  'PL01-B02-INV03-STR05-P03': 3,
  'PL01-B02-INV03-STR05-P04': 4,
};

export const DEFAULT_HEALTH_REPORT_PANEL_ID = 'PL01-B02-INV03-STR05-P01';

/** When opening Health Report without choosing a grid panel, use Panel 1 sensors (V1/I1/P1). */
export const panelIdOrDefaultForReadings = (panelId) =>
  panelId != null && String(panelId).trim() !== '' ? panelId : DEFAULT_HEALTH_REPORT_PANEL_ID;

export const readingsChannelIndexForPanel = (panelId) => {
  if (!panelId) return 1;
  return PANEL_ID_TO_READINGS_CHANNEL[panelId] ?? 1;
};

/** Instantaneous power (W) for one channel: Pn if present, else Vn × In. */
export const powerFromChannelW = (row, channelIndex) => {
  if (!row || typeof row !== 'object' || channelIndex < 1 || channelIndex > 4) return 0;
  const p = pickReadingScalar(row, `P${channelIndex}`);
  if (p != null && Number.isFinite(absNumber(p))) return absNumber(p);
  const v = absNumber(pickReadingScalar(row, `V${channelIndex}`));
  const ia = sensorCurrentToAmps(pickReadingScalar(row, `I${channelIndex}`));
  return Number.isFinite(v) && Number.isFinite(ia) ? v * ia : 0;
};
