export const toFiniteNumber = (value, fallback = 0) => {
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
};

export const absNumber = (value) => {
  const n = toFiniteNumber(value, 0);
  return Math.abs(n);
};

export const truncTo = (value, decimals = 2) => {
  const n = toFiniteNumber(value, 0);
  const factor = 10 ** decimals;
  return Math.trunc(n * factor) / factor;
};

export const formatAbsFixed = (value, decimals = 2) => {
  const n = absNumber(value);
  return truncTo(n, decimals).toFixed(decimals);
};
